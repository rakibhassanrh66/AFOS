-- Teacher self-service course offerings (admin-approved) + student join requests
-- (teacher-approved), syncing into the live schedule_slots table on approval.

alter table course_offerings
  add column if not exists department text,
  add column if not exists batch text,
  add column if not exists semester integer,
  add column if not exists day_of_week integer,
  add column if not exists start_time time,
  add column if not exists end_time time,
  add column if not exists room_number text,
  add column if not exists building text,
  add column if not exists status text not null default 'pending',
  add column if not exists reviewed_by uuid references profiles(id),
  add column if not exists reviewed_at timestamptz,
  add column if not exists rejection_reason text,
  add column if not exists created_at timestamptz not null default now();

alter table course_offerings
  add constraint course_offerings_status_check check (status in ('pending','approved','rejected'));
alter table course_offerings
  add constraint course_offerings_semester_check check (semester is null or (semester between 1 and 12));
alter table course_offerings
  add constraint course_offerings_day_of_week_check check (day_of_week is null or (day_of_week between 0 and 6));

alter table schedule_slots
  add column if not exists course_offering_id uuid references course_offerings(id) on delete set null;

alter table enrollments
  add column if not exists status text not null default 'pending',
  add column if not exists created_at timestamptz not null default now();
alter table enrollments
  add constraint enrollments_status_check check (status in ('pending','approved','rejected'));

-- courses: dead has_permission-based policy replaced with the live
-- role-check-or-caller_can pattern (matches halls/sos_alerts/
-- conference_room_requests), plus a teacher-insert path so a teacher can
-- add a new course code on the fly when self-declaring an offering.
drop policy if exists admin_write_courses on courses;
create policy teacher_insert_course on courses
  for insert with check (get_my_profile_role() = 'teacher');
create policy admin_manage_courses on courses
  for all
  using (get_my_profile_role() = any (array['admin','dept_admin','super_admin']) or caller_can('courses','manage'))
  with check (get_my_profile_role() = any (array['admin','dept_admin','super_admin']) or caller_can('courses','manage'));

-- course_offerings
drop policy if exists admin_write_offerings on course_offerings;
create policy teacher_insert_own_offering on course_offerings
  for insert with check (teacher_id = auth.uid() and status = 'pending');
create policy teacher_update_own_pending_offering on course_offerings
  for update
  using (teacher_id = auth.uid() and status = 'pending')
  with check (teacher_id = auth.uid() and status = 'pending');
create policy teacher_delete_own_pending_offering on course_offerings
  for delete using (teacher_id = auth.uid() and status = 'pending');
create policy admin_manage_offerings on course_offerings
  for all
  using (get_my_profile_role() = any (array['admin','dept_admin','super_admin']) or caller_can('course_offerings','manage'))
  with check (get_my_profile_role() = any (array['admin','dept_admin','super_admin']) or caller_can('course_offerings','manage'));

-- enrollments
drop policy if exists student_insert_own_enrollment on enrollments;
create policy student_insert_own_enrollment on enrollments
  for insert with check (student_id = auth.uid() and status = 'pending');
create policy teacher_read_offering_enrollments on enrollments
  for select using (exists (
    select 1 from course_offerings co where co.id = enrollments.offering_id and co.teacher_id = auth.uid()
  ));
create policy teacher_update_offering_enrollments on enrollments
  for update
  using (exists (
    select 1 from course_offerings co where co.id = enrollments.offering_id and co.teacher_id = auth.uid()
  ))
  with check (exists (
    select 1 from course_offerings co where co.id = enrollments.offering_id and co.teacher_id = auth.uid()
  ));
drop policy if exists admin_write_enrollments on enrollments;
create policy admin_manage_enrollments on enrollments
  for all
  using (get_my_profile_role() = any (array['admin','dept_admin','super_admin']) or caller_can('enrollments','manage'))
  with check (get_my_profile_role() = any (array['admin','dept_admin','super_admin']) or caller_can('enrollments','manage'));

-- Extend the delegable-permissions catalog (surfaces in Manage Users >
-- "Distribute admin work") so a super_admin can hand this off to a
-- specific non-admin-tier user without granting the full admin role.
insert into permissions (resource, action, scope)
select v.resource, v.action, v.scope
from (values ('course_offerings','manage','all'), ('courses','manage','all'), ('enrollments','manage','all')) as v(resource, action, scope)
where not exists (
  select 1 from permissions p where p.resource = v.resource and p.action = v.action and p.scope = v.scope
);
