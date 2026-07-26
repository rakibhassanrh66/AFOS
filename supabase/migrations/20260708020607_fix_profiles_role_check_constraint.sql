-- Found via a live test signup while adding staff support: profiles_role_check
-- still only allowed the ancient wrong role vocabulary
-- ('faculty','club_president','hall_manager','dept_head' — the same
-- deprecated strings already purged from every RLS policy in earlier
-- sessions) and never actually included 'staff', 'dept_admin', or
-- 'exam_controller' at all, even though the `roles` reference table and
-- extensive RLS policies throughout the app assume all three are real,
-- assignable roles. get_my_profile_role() reads this flat profiles.role
-- column directly (not the role_id join), so this constraint has been
-- silently blocking every staff/dept_admin/exam_controller RLS check from
-- ever being satisfiable — confirmed no existing row currently uses any of
-- the old bogus values (only student/teacher/super_admin exist live), so
-- this is safe to narrow to the real vocabulary in one step.
alter table profiles drop constraint profiles_role_check;
alter table profiles add constraint profiles_role_check
  check (role = any (array['student','teacher','staff','admin','dept_admin','super_admin','exam_controller']));
