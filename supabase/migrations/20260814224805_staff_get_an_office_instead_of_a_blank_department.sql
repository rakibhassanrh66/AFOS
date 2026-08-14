-- A staff member had nowhere to say which office they work in, so every one of
-- them carried department = '' and the app drew them an empty chip.
--
-- WHAT WAS ON SCREEN. slide_menu.dart renders `_Chip(_user?.department ?? '')`
-- unconditionally. For the one real staff account in the database
-- (designation "Registrar") `profiles.department` was the empty STRING — not
-- null, so `?? ''` never fired and nothing downstream treated it as missing.
-- The chip drew its pill, its padding and its background with no text inside:
-- a small blank blob sitting next to the person's name.
--
-- WHY IT WAS EMPTY. The register screen deliberately hides the department
-- dropdown from staff, and correctly so — `departments` is the ACADEMIC list
-- (CSE, EEE, ...) and a Registrar, an accounts officer or IT support has no
-- honest answer in it. But the screen still submitted
-- `department: _selectedDept?.code ?? ''`, so hiding the field did not remove
-- the field's value; it just made it blank forever. There was no other place
-- to record where a staff member actually works.
--
-- THE SHAPE OF THE FIX. Two different facts were being forced into one column:
--
--   profiles.department  the ACADEMIC department code, for the staff who
--                        genuinely belong to one (a departmental officer for
--                        CSE). NULL for everyone else — and NULL is now
--                        actually representable, where '' pretended not to be.
--   staff.office         free text, for central offices with no academic
--                        code: "Registrar Office", "Accounts", "IT Support".
--
-- Normally exactly one of the two is set. The UI reads department, falls back
-- to office, and renders no chip at all when both are absent — rather than
-- rendering an empty one.
--
-- handle_new_user() is updated to match: it stops coalescing a staff member's
-- department to 'CSE' (which would have been a plain lie once the field was
-- submitted as null), records `office` on the staff row, and counts a profile
-- complete when EITHER a department or an office is known.
--
-- Existing rows are normalised: `department = ''` becomes NULL.

-- (function bodies below reproduce what was applied)

alter table public.staff add column if not exists office text;

comment on column public.staff.office is
  'Free-text office/section for staff who do not belong to an ACADEMIC '
  'department (Registrar, Accounts, IT, ...). profiles.department stays the '
  'academic code and is NULL for them. Exactly one of the two is normally set.';

update public.profiles set department = null
 where department is not null and btrim(department) = '';

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_requested_type text := coalesce(new.raw_user_meta_data->>'account_type', 'student');
  v_account_type   text;
  v_role_id        uuid;
  v_department     text;
  v_department_id  uuid;
  v_office         text;
  v_program_id     uuid;
  v_completed      boolean;
  v_batch          text;
  v_section        text;
begin
  if v_requested_type in ('student', 'teacher', 'staff') then
    v_account_type := v_requested_type;
  else
    v_account_type := 'student';
    perform log_audit('auth.users', new.id, 'signup_role_rejected',
      jsonb_build_object('requested_account_type', v_requested_type), NULL);
  end if;

  select id into v_role_id from roles where name = v_account_type;
  if v_role_id is null then
    select id into v_role_id from roles where name = 'student';
  end if;
  if v_role_id is null then
    raise exception 'Cannot create profile: no role row found for % or student', v_account_type;
  end if;

  v_department := nullif(btrim(coalesce(new.raw_user_meta_data->>'department', '')), '');
  v_office     := nullif(btrim(coalesce(new.raw_user_meta_data->>'office', '')), '');

  -- Students and teachers always belong to an academic department, so the old
  -- 'CSE' fallback stays for them. Staff frequently do NOT (Registrar,
  -- Accounts, IT), and forcing a wrong academic code on them was what produced
  -- profiles carrying an empty or misleading department in the first place.
  if v_account_type <> 'staff' then
    v_department := coalesce(v_department, 'CSE');
  end if;

  select id into v_department_id from departments where code = v_department;

  if v_account_type = 'student' and new.raw_user_meta_data->>'program_id' is not null then
    v_program_id := (new.raw_user_meta_data->>'program_id')::uuid;
  end if;

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
    and new.raw_user_meta_data->>'semester' is not null
    and (v_department is not null or v_office is not null);

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
    v_department,
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
    insert into staff (profile_id, department_id, designation, category, office)
    values (new.id, v_department_id, new.raw_user_meta_data->>'designation',
            new.raw_user_meta_data->>'staff_category', v_office)
    on conflict (profile_id) do update set
      department_id = coalesce(excluded.department_id, staff.department_id),
      designation   = coalesce(excluded.designation,   staff.designation),
      category      = coalesce(excluded.category,      staff.category),
      office        = coalesce(excluded.office,        staff.office);
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
