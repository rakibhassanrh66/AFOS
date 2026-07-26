-- =====================================================================
--  AFOS — Cascade profile deletion to students/teachers extension rows
--
--  Found while testing (twice): deleting a profile whose id is still
--  referenced by students/teachers fails with a foreign key violation,
--  since neither FK had ON DELETE CASCADE. That blocks legitimate account
--  deletion (Super Admin removing a user, a user closing their account)
--  the same way it blocked test cleanup here.
-- =====================================================================

ALTER TABLE students DROP CONSTRAINT students_profile_id_fkey;
ALTER TABLE students ADD CONSTRAINT students_profile_id_fkey
  FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;

ALTER TABLE teachers DROP CONSTRAINT teachers_profile_id_fkey;
ALTER TABLE teachers ADD CONSTRAINT teachers_profile_id_fkey
  FOREIGN KEY (profile_id) REFERENCES profiles(id) ON DELETE CASCADE;
