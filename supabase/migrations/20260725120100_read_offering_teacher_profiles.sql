-- =====================================================================
--  AFOS — Let authenticated users read the profile of a teacher who owns
--  an approved course offering.
--
--  With the FK from 20260725120000 in place, the schema-cache error is
--  gone but browse_courses_screen.dart still renders "Taught by Faculty"
--  for most teachers, because the `profiles!teacher_id(full_name,
--  avatar_url)` embed comes back NULL under RLS:
--
--    - admin_read_all requires the READER to be admin/teacher, so it does
--      nothing for a student browsing courses.
--    - auth_read_teacher_profiles requires teacher_initial IS NOT NULL,
--      and 5 of the 7 teacher-role accounts currently have it NULL.
--
--  Rather than weaken auth_read_teacher_profiles, this follows the
--  precedent its own migration set (20260704080000): teacher_initial is a
--  routine-screen-specific field, so a feature that needs teacher identity
--  for an unrelated reason gets its own correctly-scoped policy -- exactly
--  how auth_read_mentor_profiles was added there for mentorship.
--
--  Scope is deliberately narrow: only teachers who have an APPROVED
--  offering, which is already world-readable to authenticated users
--  anyway via course_offerings' public_read_offerings policy. A pending
--  or rejected offering exposes nothing.
-- =====================================================================

DROP POLICY IF EXISTS "auth_read_offering_teacher_profiles" ON profiles;
CREATE POLICY "auth_read_offering_teacher_profiles" ON profiles FOR SELECT TO authenticated USING (
  EXISTS (
    SELECT 1 FROM course_offerings co
    WHERE co.teacher_id = profiles.id
      AND co.status = 'approved'
  )
);

NOTIFY pgrst, 'reload schema';
