-- =====================================================================
--  AFOS — Add direct FK constraints so PostgREST can embed `profiles`
--  off `enrollments` and `course_offerings`, with delete behaviour that
--  matches 20260706000100_user_deletion_cascade.sql's convention.
--
--  PART 1 — the reported bug.
--
--  enrollments.student_id only had a FK to students(profile_id), and
--  course_offerings.teacher_id only had a FK to teachers(profile_id).
--  students.profile_id / teachers.profile_id each separately reference
--  profiles(id), but that's a two-hop chain -- PostgREST can only
--  auto-resolve an embed hint across a DIRECT foreign key between the
--  two tables named in .select(). Client queries doing
--  `.from('enrollments').select('profiles!student_id(...)')` and
--  `.from('course_offerings').select('profiles!teacher_id(...)')`
--  (course_offering_repository.dart lines 71, 142, 170) failed with
--  "Could not find a relationship between 'enrollments' and 'profiles'
--  in the schema cache", breaking join requests for teachers and course
--  browsing for students.
--
--  Same root cause and fix shape as 20260702180000_add_missing_profiles_fks.sql.
--  course_offerings will then have TWO FKs to profiles (reviewed_by and
--  teacher_id), which is fine: the `!teacher_id` column-name hint
--  disambiguates, exactly as vr_access_log's two profiles FKs already do
--  in production today with `profiles!scanned_by_id` (vr_id_screen.dart:320).
--
--  PART 2 — delete behaviour, so this fix doesn't break account deletion.
--
--  20260706000100_user_deletion_cascade.sql exists precisely because a
--  plain FK to profiles.id made auth.admin.deleteUser() "fail outright".
--  It set the house rule: a user's own content/activity CASCADEs, pure
--  attribution fields SET NULL. The course-offering system (20260724143117)
--  landed after that migration and did not follow it, so it left three
--  NO ACTION FKs that will block deleting any account once this feature
--  has real data:
--    - course_offerings.reviewed_by -> profiles   (blocks deleting an admin
--      who ever reviewed an offering)          -> attribution, so SET NULL
--    - course_offerings.teacher_id -> teachers   (blocks deleting a teacher)
--    - enrollments.offering_id -> course_offerings (blocks the cascade above,
--      via OTHER students' enrollments in that teacher's offering)
--
--  Adding PART 1's two FKs as ON DELETE CASCADE resolves the teacher_id
--  and student_id chains on its own (the referencing rows are removed
--  before the NO ACTION checks run at end of statement), so only
--  offering_id and reviewed_by still need correcting.
--
--  Safe to apply: enrollments and course_offerings are both empty (0 rows),
--  and every non-null value would already satisfy the new constraint via
--  the existing students/teachers -> profiles chain regardless.
-- =====================================================================

-- PART 1 -- the embeds PostgREST needs.
ALTER TABLE enrollments
  ADD CONSTRAINT enrollments_student_id_profiles_fkey
  FOREIGN KEY (student_id) REFERENCES profiles(id) ON DELETE CASCADE;

ALTER TABLE course_offerings
  ADD CONSTRAINT course_offerings_teacher_id_profiles_fkey
  FOREIGN KEY (teacher_id) REFERENCES profiles(id) ON DELETE CASCADE;

-- PART 2 -- bring the course-offering system's own FKs in line with
-- 20260706000100's convention so deleting an account stays possible.

-- Deleting an offering must take its join requests with it; they are
-- meaningless without the offering, and leaving them NO ACTION blocks the
-- teacher-deletion cascade established above.
ALTER TABLE enrollments DROP CONSTRAINT IF EXISTS enrollments_offering_id_fkey;
ALTER TABLE enrollments
  ADD CONSTRAINT enrollments_offering_id_fkey
  FOREIGN KEY (offering_id) REFERENCES course_offerings(id) ON DELETE CASCADE;

-- reviewed_by is attribution ("which admin approved this"), not the
-- reviewer's own content -- the offering must outlive the reviewer's
-- account, so SET NULL, matching notices.author_id / audit_log.changed_by.
ALTER TABLE course_offerings DROP CONSTRAINT IF EXISTS course_offerings_reviewed_by_fkey;
ALTER TABLE course_offerings
  ADD CONSTRAINT course_offerings_reviewed_by_fkey
  FOREIGN KEY (reviewed_by) REFERENCES profiles(id) ON DELETE SET NULL;

NOTIFY pgrst, 'reload schema';
