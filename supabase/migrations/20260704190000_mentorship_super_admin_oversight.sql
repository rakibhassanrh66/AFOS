-- Super admin needs to observe mentorship activity and remove/ban an
-- abusive mentor, but should NOT be able to run mentorship features
-- themselves — so this is read-only on bookings, and update/delete-only
-- (never insert) on mentors, rather than a blanket FOR ALL.

-- Read-only oversight — super_admin can see every booking but not create
-- fabricated ones (no INSERT/UPDATE grant here).
CREATE POLICY "super_admin_read_bookings" ON mentorship_bookings FOR SELECT
  USING (get_my_profile_role() = 'super_admin');

-- Deactivate/remove a mentor profile deemed abusive. Scoped to UPDATE
-- (soft-disable via is_accepting_bookings=false) and DELETE (hard removal)
-- rather than FOR ALL, since super_admin should not be able to fabricate
-- a mentor row for someone else.
CREATE POLICY "super_admin_manage_mentors" ON mentors FOR UPDATE
  USING (get_my_profile_role() = 'super_admin')
  WITH CHECK (get_my_profile_role() = 'super_admin');
CREATE POLICY "super_admin_delete_mentors" ON mentors FOR DELETE
  USING (get_my_profile_role() = 'super_admin');
