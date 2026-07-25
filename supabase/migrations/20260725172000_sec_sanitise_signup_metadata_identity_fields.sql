-- =====================================================================
--  AFOS — Make signup resilient to out-of-format batch/section metadata.
--
--  WHY. sec_input_validation_and_normalisation added CHECK constraints to
--  students.batch_label / students.section. handle_new_user copies both
--  straight out of raw_user_meta_data, which is attacker-controlled and,
--  more importantly, user-typed. A student who types a 5-character section
--  would fail the CHECK inside the auth trigger, which aborts the whole
--  auth.users insert -- turning a trivial typo into "account creation is
--  broken" with no field-level feedback anywhere.
--
--  Losing an optional field is strictly better than losing the account:
--  the value is dropped to NULL and recorded in the audit log, and the
--  user is asked for it again on the complete-profile screen, which now
--  format-validates it properly (AppValidators.batch / .section).
--
--  This is the untrusted-metadata boundary, so it sanitises rather than
--  raises. Every other write path validates client-side AND is rejected by
--  the CHECK, which is the behaviour we want there.
--
--  Verified by a rolled-back probe: a signup carrying section 'ABCDE'
--  now succeeds with section NULL + a signup_section_rejected audit row,
--  while a valid-but-messy ' b ' is still stored as 'B'.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_requested_type text := coalesce(new.raw_user_meta_data->>'account_type', 'student');
  v_account_type   text;
  v_role_id        uuid;
  v_department_id  uuid;
  v_program_id     uuid;
  v_completed      boolean;
  v_batch          text;
  v_section        text;
begin
  -- Whitelist: only self-service account types may be self-assigned at
  -- signup. Anything else (super_admin/admin/dept_admin/exam_controller or
  -- a garbage value) is forced to 'student' and recorded.
  if v_requested_type in ('student', 'teacher', 'staff') then
    v_account_type := v_requested_type;
  else
    v_account_type := 'student';
    perform log_audit('auth.users', new.id, 'signup_role_rejected',
      jsonb_build_object('requested_account_type', v_requested_type), NULL);
  end if;

  select id into v_role_id from roles where name = v_account_type;

  select id into v_department_id from departments
    where code = new.raw_user_meta_data->>'department';

  if v_account_type = 'student' and new.raw_user_meta_data->>'program_id' is not null then
    v_program_id := (new.raw_user_meta_data->>'program_id')::uuid;
  end if;

  -- Normalise to the same shape trg_normalise_student_identity would produce,
  -- then drop anything that still fails the CHECK rather than letting the
  -- constraint abort the signup.
  v_batch   := nullif(btrim(new.raw_user_meta_data->>'batch'), '');
  v_section := nullif(upper(btrim(new.raw_user_meta_data->>'section')), '');

  if v_batch is not null and v_batch !~ '^[A-Za-z0-9-]{1,10}$' then
    perform log_audit('auth.users', new.id, 'signup_batch_rejected',
      jsonb_build_object('value', v_batch), NULL);
    v_batch := null;
  end if;

  if v_section is not null and v_section !~ '^[A-Z0-9]{1,4}$' then
    perform log_audit('auth.users', new.id, 'signup_section_rejected',
      jsonb_build_object('value', v_section), NULL);
    v_section := null;
  end if;

  v_completed := new.raw_user_meta_data->>'full_name' is not null
    and new.raw_user_meta_data->>'department' is not null
    and new.raw_user_meta_data->>'semester' is not null;

  insert into profiles (
    id, email, full_name,
    student_id, university_id,
    department, department_id, semester,
    role, role_id, profile_completed, gender
  ) values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', 'New User'),
    new.raw_user_meta_data->>'university_id',
    new.raw_user_meta_data->>'university_id',
    coalesce(new.raw_user_meta_data->>'department', 'CSE'),
    v_department_id,
    coalesce((new.raw_user_meta_data->>'semester')::int, 1),
    v_account_type,
    v_role_id,
    v_completed,
    new.raw_user_meta_data->>'gender'
  )
  on conflict (id) do update set
    full_name     = case
                      when profiles.full_name = 'New User'
                      then coalesce(excluded.full_name, profiles.full_name)
                      else profiles.full_name
                    end,
    student_id    = coalesce(excluded.student_id,    profiles.student_id),
    university_id = coalesce(excluded.university_id, profiles.university_id),
    department    = coalesce(excluded.department,    profiles.department),
    department_id = coalesce(excluded.department_id, profiles.department_id),
    semester      = coalesce(excluded.semester,      profiles.semester),
    role_id       = coalesce(excluded.role_id,       profiles.role_id),
    gender        = coalesce(excluded.gender,        profiles.gender);

  if v_account_type = 'teacher' then
    insert into teachers (profile_id, department_id, designation)
    values (new.id, v_department_id, new.raw_user_meta_data->>'designation')
    on conflict (profile_id) do update set
      department_id = coalesce(excluded.department_id, teachers.department_id),
      designation   = coalesce(excluded.designation,   teachers.designation);
  elsif v_account_type = 'staff' then
    insert into staff (profile_id, department_id, designation, category)
    values (new.id, v_department_id, new.raw_user_meta_data->>'designation',
            new.raw_user_meta_data->>'staff_category')
    on conflict (profile_id) do update set
      department_id = coalesce(excluded.department_id, staff.department_id),
      designation   = coalesce(excluded.designation,   staff.designation),
      category      = coalesce(excluded.category,      staff.category);
  else
    insert into students (profile_id, department_id, program_id, batch_label, section, current_semester_no, status)
    values (
      new.id, v_department_id, v_program_id,
      v_batch,
      v_section,
      coalesce((new.raw_user_meta_data->>'semester')::int, 1),
      'active'
    )
    on conflict (profile_id) do update set
      department_id        = coalesce(excluded.department_id, students.department_id),
      program_id           = coalesce(excluded.program_id, students.program_id),
      batch_label           = coalesce(excluded.batch_label, students.batch_label),
      section               = coalesce(excluded.section, students.section),
      current_semester_no   = coalesce(excluded.current_semester_no, students.current_semester_no);
  end if;

  return new;
end;
$function$;
