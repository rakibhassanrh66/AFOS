-- A profile with no role_id could promote ITSELF to super_admin.
--
-- THE HOLE. protect_profile_privileged_columns() guards role, role_id and
-- is_verified on UPDATE. Its condition read:
--
--     IF (role/role_id/is_verified changed)
--        AND OLD.role_id IS NOT NULL              <-- this line
--        AND NOT (get_my_profile_role() = ANY (ARRAY['admin','super_admin']))
--     THEN RAISE ...
--
-- so the entire guard was skipped whenever OLD.role_id was NULL. RLS already
-- lets a user UPDATE their own row ("own_profile_update": auth.uid() = id), and
-- the trigger was the only thing standing between that and a role change. For a
-- profile with a NULL role_id there was nothing standing there at all.
--
-- HOW A NULL role_id HAPPENS. handle_new_user() did:
--
--     select id into v_role_id from roles where name = v_account_type;
--
-- A SELECT INTO that matches no row does not error — it assigns NULL. So any
-- signup where the roles lookup missed produced exactly the unguarded profile
-- described above, silently.
--
-- WHY IT MATTERED MORE THAN THE ODDS SUGGEST. This repository is PUBLIC, and
-- `manual_admin_assignment.sql` sat in its root spelling out the payload:
-- UPDATE profiles SET role_id = (the super_admin role) WHERE id = <you>. The
-- exploit and its instructions were published together. That file is removed in
-- the same change as this migration.
--
-- Verified before and after against the live database with a BEGIN/ROLLBACK
-- probe. Before: "ESCALATION SUCCEEDED - a null role_id lets a student become
-- super_admin". After: null-role_id escalation blocked, normal self-promotion
-- blocked, and the server-side assignment path still allowed.
--
-- THE FIX, AND WHY IT IS SHAPED THIS WAY. The tempting repair is to delete the
-- `OLD.role_id IS NOT NULL` line. That breaks signup: handle_new_user() ends in
-- an upsert whose ON CONFLICT DO UPDATE sets role_id, which fires this very
-- trigger, and at that moment the new user is not an admin — so the guard would
-- reject the account it is trying to create. That is presumably why the escape
-- hatch was added.
--
-- The real distinction is not "does this row have a role yet" but "is a USER
-- doing this to themselves". A request carrying no JWT is not a user: it is the
-- signup trigger, an edge function on the service role, or a migration. So the
-- guard now exempts `auth.uid() IS NULL` and applies to every authenticated
-- caller regardless of what role_id currently holds.
--
-- handle_new_user() is additionally hardened to never produce the NULL in the
-- first place: it falls back to the 'student' role, and refuses the signup
-- outright rather than create an account with no role.

create or replace function public.protect_profile_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if NEW.role      is distinct from OLD.role
     or NEW.role_id    is distinct from OLD.role_id
     or NEW.is_verified is distinct from OLD.is_verified
  then
    -- No JWT on the request = server-side context: the signup trigger's own
    -- upsert, an edge function on the service role, a migration. Those are the
    -- paths that legitimately assign a role, and none of them is a user acting
    -- on themselves.
    if auth.uid() is null then
      return NEW;
    end if;

    if not (get_my_profile_role() = any (array['admin', 'super_admin'])) then
      raise exception 'Not authorized to change role, role_id, or is_verified.';
    end if;
  end if;

  return NEW;
end;
$function$;

-- Belt and braces: stop the NULL role_id being creatable at all. Only the two
-- lookup/guard lines differ from the previous definition; the rest is carried
-- over verbatim so this migration replays the whole function as it now stands.
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
  v_department_id  uuid;
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

  -- A missing roles row used to leave role_id NULL, and a NULL role_id was an
  -- unguarded profile. Fall back to 'student', and refuse the signup outright
  -- rather than create an account with no role.
  if v_role_id is null then
    select id into v_role_id from roles where name = 'student';
  end if;
  if v_role_id is null then
    raise exception 'Cannot create profile: no role row found for % or student', v_account_type;
  end if;

  select id into v_department_id from departments
    where code = new.raw_user_meta_data->>'department';

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
