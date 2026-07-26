-- 20260704020000 fixed most 'faculty'/'dept_head'/'hall_manager' role-string
-- bugs, but a live audit of pg_policies found 4 more policies still checking
-- against 'faculty' — which handle_new_user() never assigns (real teacher
-- accounts get role='teacher') — so these have silently never matched a real
-- teacher account since creation. Normalize to the same role vocabulary used
-- everywhere else.

DROP POLICY IF EXISTS "admin_write_routes" ON transport_routes;
CREATE POLICY "admin_write_routes" ON transport_routes FOR ALL TO authenticated USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
      AND profiles.role = ANY (ARRAY['admin','teacher','dept_admin','super_admin'])
  )
);

DROP POLICY IF EXISTS "admin_write_schedule" ON schedule_slots;
CREATE POLICY "admin_write_schedule" ON schedule_slots FOR ALL TO authenticated USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
      AND profiles.role = ANY (ARRAY['admin','teacher','dept_admin','super_admin'])
  )
);

DROP POLICY IF EXISTS "admin_read_all" ON profiles;
CREATE POLICY "admin_read_all" ON profiles FOR SELECT USING (
  auth.uid() = id
  OR get_my_profile_role() = ANY (ARRAY['admin','teacher','dept_admin','super_admin'])
);

DROP POLICY IF EXISTS "system_insert" ON user_notifications;
CREATE POLICY "system_insert" ON user_notifications FOR INSERT WITH CHECK (
  auth.uid() = user_id
  OR get_my_profile_role() = ANY (ARRAY['admin','teacher','dept_admin','super_admin'])
);
