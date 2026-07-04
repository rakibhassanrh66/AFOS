-- ══════════════════════════════════════════════════════════════════════
--  AFOS — Let any authenticated user read teacher profile rows (name +
--  avatar + initials), so the class routine screen can resolve a
--  routine's bare teacher initials into a real name and photo. Existing
--  policies only let a user read their own profile or (if faculty/admin)
--  everyone's — students otherwise couldn't see any teacher's name/photo.
-- ══════════════════════════════════════════════════════════════════════

CREATE POLICY "auth_read_teacher_profiles" ON profiles FOR SELECT TO authenticated USING (
  role IN ('faculty','admin','dept_head') AND teacher_initial IS NOT NULL
);
