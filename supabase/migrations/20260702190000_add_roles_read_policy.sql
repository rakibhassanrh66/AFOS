-- =====================================================================
--  AFOS — roles table has RLS enabled but zero policies, so every read
--  (including the roles(name) embed on profiles) is silently denied,
--  returning null instead of the actual role name. Role names are not
--  sensitive reference data — same treatment as departments/programs.
-- =====================================================================

CREATE POLICY public_read_roles ON roles FOR SELECT
  TO anon, authenticated USING (true);
