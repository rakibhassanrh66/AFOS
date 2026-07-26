-- =====================================================================
--  AFOS — Fix stale profiles.role CHECK constraint
--  The constraint predates the v8 roles table and never allowed
--  'teacher' or 'super_admin', silently breaking teacher registration
--  and any super_admin promotion.
-- =====================================================================

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE profiles ADD CONSTRAINT profiles_role_check CHECK (
  role = ANY (ARRAY[
    'student'::text, 'teacher'::text, 'admin'::text, 'super_admin'::text,
    'faculty'::text, 'club_president'::text, 'hall_manager'::text, 'dept_head'::text
  ])
);
