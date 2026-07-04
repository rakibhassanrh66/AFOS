-- =====================================================================
--  AFOS — Fix teacher profile visibility (role-vocabulary drift, again)
--
--  auth_read_teacher_profiles (007_teacher_directory_read.sql) checked
--  role IN ('faculty','admin','dept_head') — none of which are real
--  values; handle_new_user only ever assigns 'student'/'teacher'/whatever
--  an admin sets via admin_manage_all_profiles. This policy has never
--  actually matched a real teacher account, so:
--   - the class routine screen could never resolve a teacher's initials
--     into a real name/photo (its stated original purpose)
--   - students could never see a teacher's name/photo/department in the
--     mentorship "Find Mentor" list (the profiles!student_id/profiles
--     embed silently came back null)
--
--  Also adding a distinct, correctly-scoped policy for mentorship: a
--  teacher's profile should be visible to any authenticated user once
--  they've published a mentors row, independent of whether they've also
--  filled in a teacher_initial (a routine-specific field, unrelated to
--  mentorship).
-- =====================================================================

DROP POLICY IF EXISTS "auth_read_teacher_profiles" ON profiles;
CREATE POLICY "auth_read_teacher_profiles" ON profiles FOR SELECT TO authenticated USING (
  role = ANY (ARRAY['teacher','admin','dept_admin','super_admin']) AND teacher_initial IS NOT NULL
);

CREATE POLICY "auth_read_mentor_profiles" ON profiles FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM mentors m WHERE m.id = profiles.id)
);
