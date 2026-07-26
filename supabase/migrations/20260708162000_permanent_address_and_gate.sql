-- Mandatory home-address fields for the SOS/Emergency Alert system: when a
-- user is NOT on campus, alerts need to reach people registered in the same
-- home district (zila). profiles.phone already exists (since
-- 20260623160352) but was never actually required; address never existed
-- at all. This migration adds the columns and reuses the existing
-- profile_completed force-gate (app_router.dart already redirects to
-- /complete-profile whenever profile_completed = false) rather than adding
-- a second gate mechanism.

alter table profiles add column if not exists permanent_division text;
alter table profiles add column if not exists permanent_district text;
alter table profiles add column if not exists permanent_upazila text;

-- Forces every EXISTING account back through /complete-profile on next app
-- open — not just new signups. This is a one-time retroactive reset, same
-- mechanism as the original 20260704110000 migration that first introduced
-- profile_completed.
update profiles set profile_completed = false where permanent_district is null;

-- handle_new_user() must also require the address fields for brand-new
-- signups (the registration form doesn't collect them, so v_completed will
-- simply stay false until the user fills them in at /complete-profile —
-- one single place still owns "is my profile complete").
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_account_type   text := coalesce(new.raw_user_meta_data->>'account_type', 'student');
  v_role_id        uuid;
  v_department_id  uuid;
  v_program_id     uuid;
  v_completed      boolean;
begin
  select id into v_role_id from roles where name = v_account_type;

  select id into v_department_id from departments
    where code = new.raw_user_meta_data->>'department';

  if v_account_type = 'student' and new.raw_user_meta_data->>'program_id' is not null then
    v_program_id := (new.raw_user_meta_data->>'program_id')::uuid;
  end if;

  v_completed := new.raw_user_meta_data->>'full_name' is not null
    and new.raw_user_meta_data->>'department' is not null
    and new.raw_user_meta_data->>'semester' is not null
    and new.raw_user_meta_data->>'permanent_district' is not null;

  insert into profiles (
    id, email, full_name,
    student_id, university_id,
    department, department_id, semester,
    role, role_id, profile_completed, gender,
    permanent_division, permanent_district, permanent_upazila
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
    new.raw_user_meta_data->>'gender',
    new.raw_user_meta_data->>'permanent_division',
    new.raw_user_meta_data->>'permanent_district',
    new.raw_user_meta_data->>'permanent_upazila'
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
      new.raw_user_meta_data->>'batch',
      new.raw_user_meta_data->>'section',
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
