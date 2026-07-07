-- Registration only ever let someone sign up as 'student' or 'teacher' —
-- there was no real way to register as 'staff' at all: the UI toggle's
-- second option was labeled "Teacher / Staff" but always submitted
-- account_type='teacher', and handle_new_user() only ever branched
-- teacher-vs-ELSE-is-student, so a genuine 'staff' account_type would have
-- been inserted into `students` (wrong table entirely). This migration adds
-- real staff support: a reference table of actual DIU staff job titles
-- (grouped by category, admin-manageable via is_active), a `staff` side
-- table mirroring `students`/`teachers`, and fixes the trigger's branching.

-- ── Reference data: real DIU staff designations ─────────────────────────
create table staff_designations (
  id uuid primary key default gen_random_uuid(),
  category text not null,
  title text not null unique,
  sort_order int not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table staff_designations enable row level security;

-- Needed unauthenticated (anon) — the registration screen populates this
-- dropdown before the user has a session, same as departments/programs.
create policy public_read_staff_designations on staff_designations
  for select using (is_active = true);

create policy super_admin_manage_staff_designations on staff_designations
  for all using (get_my_profile_role() = 'super_admin')
  with check (get_my_profile_role() = 'super_admin');

insert into staff_designations (category, title, sort_order) values
  -- Executive Leadership & Top Administration
  ('Executive Leadership & Top Administration', 'Vice Chancellor (VC)', 100),
  ('Executive Leadership & Top Administration', 'Pro-Vice Chancellor', 101),
  ('Executive Leadership & Top Administration', 'Registrar', 102),
  ('Executive Leadership & Top Administration', 'Controller of Examinations', 103),
  ('Executive Leadership & Top Administration', 'Director (Finance & Accounts)', 104),
  -- Department-Level Designations (highest to lowest)
  ('Department-Level Designations', 'Director / Head of Department', 200),
  ('Department-Level Designations', 'Additional Director / Joint Director', 201),
  ('Department-Level Designations', 'Deputy Director (DD)', 202),
  ('Department-Level Designations', 'Assistant Director (AD)', 203),
  ('Department-Level Designations', 'Senior Administrative Officer (SAO)', 204),
  ('Department-Level Designations', 'Administrative Officer (AO)', 205),
  ('Department-Level Designations', 'Assistant Administrative Officer (AAO)', 206),
  -- Project & Research Roles
  ('Project & Research Roles', 'Expert Consultant', 300),
  ('Project & Research Roles', 'Research Assistant (RA)', 301),
  ('Project & Research Roles', 'Project Fellow / Master''s Fellow', 302),
  ('Project & Research Roles', 'Accountant cum Computer Operator', 303),
  -- Campus Support & Student Opportunities
  ('Campus Support & Student Opportunities', 'Student Associate', 400),
  ('Campus Support & Student Opportunities', 'Teaching Apprentice Fellow (TAF)', 401),
  ('Campus Support & Student Opportunities', 'Photographer / Content Designer', 402),
  ('Campus Support & Student Opportunities', 'Program Coordinator', 403),
  ('Campus Support & Student Opportunities', 'Office Assistant', 404);

-- ── staff side table (mirrors students/teachers shape) ──────────────────
-- Deliberately no privilege distinction by title here — every designation
-- (even ones that sound senior, like Registrar/Director) maps to the same
-- 'staff' app role. Granting real admin/dept_admin/super_admin permissions
-- must always go through a super_admin's manual promotion in Manage Users,
-- never through a self-selected job title at signup — the same principle
-- that closed the earlier self-promotion-to-super_admin vulnerability.
create table staff (
  profile_id uuid primary key references profiles(id) on delete cascade,
  department_id uuid references departments(id),
  designation text,
  category text,
  joining_date date,
  created_at timestamptz not null default now()
);

alter table staff enable row level security;

create policy staff_read_all on staff
  for select to authenticated using (true);

create policy own_staff_update on staff
  for update using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

create policy super_admin_manage_staff on staff
  for all using (get_my_profile_role() = 'super_admin')
  with check (get_my_profile_role() = 'super_admin');

-- ── Fix handle_new_user(): staff now gets its own branch instead of
-- falling into the students INSERT (the actual latent bug) ──────────────
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
