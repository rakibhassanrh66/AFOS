-- =====================================================================
--  AFOS — Transport route upload support
--  Enables the admin file-upload feature (parse-routine edge function)
--  to upsert parsed transport routes the same way it already upserts
--  schedule_slots, and aligns admin write policies with the full set of
--  admin-capable roles ('admin','faculty','super_admin') introduced by
--  20260702140000_fix_profiles_role_check.sql (schedule_slots previously
--  only allowed 'admin'/'faculty', silently excluding 'super_admin').
-- =====================================================================

-- 1. Allow upsert-by-route_number from the parse-routine edge function.
ALTER TABLE transport_routes
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'transport_routes_route_number_key'
  ) THEN
    ALTER TABLE transport_routes ADD CONSTRAINT transport_routes_route_number_key UNIQUE (route_number);
  END IF;
END $$;

-- 2. Admin/faculty/super_admin write policy for transport_routes
--    (previously read-only for everyone, no write path at all).
DROP POLICY IF EXISTS "admin_write_routes" ON transport_routes;
CREATE POLICY "admin_write_routes" ON transport_routes FOR ALL TO authenticated USING (
  EXISTS(SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role IN ('admin','faculty','super_admin')));

-- 3. Fix schedule_slots admin write policy to also include 'super_admin'
--    (it was written before 'super_admin' existed as a role and only
--    checked 'admin'/'faculty', so a super_admin uploading a routine via
--    the app's own client — as opposed to the edge function's service-role
--    key, which bypasses RLS — would have been silently blocked).
DROP POLICY IF EXISTS "admin_write_schedule" ON schedule_slots;
CREATE POLICY "admin_write_schedule" ON schedule_slots FOR ALL TO authenticated USING (
  EXISTS(SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role IN ('admin','faculty','super_admin')));
