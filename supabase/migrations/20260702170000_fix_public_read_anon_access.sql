-- =====================================================================
--  AFOS — Fix departments/programs public-read policies to cover anon
--  Registration happens before the user has a session (anon role), but
--  the existing "public_read_*" policies were scoped TO authenticated
--  only, so the department/program dropdowns always returned zero rows
--  during signup and blocked registration entirely.
-- =====================================================================

DROP POLICY IF EXISTS public_read_departments ON departments;
CREATE POLICY public_read_departments ON departments FOR SELECT
  TO anon, authenticated USING (true);

DROP POLICY IF EXISTS public_read_programs ON programs;
CREATE POLICY public_read_programs ON programs FOR SELECT
  TO anon, authenticated USING (true);
