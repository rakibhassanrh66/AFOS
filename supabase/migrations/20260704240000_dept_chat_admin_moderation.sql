-- dept_members_read/members_send both join profiles.department = dept_channels.department,
-- so even a super_admin could only ever see their OWN department's channels/messages —
-- there was no way for anyone to moderate/oversee chat across departments. Add an
-- explicit admin-tier bypass (read all + delete any message) separate from the
-- department-scoped member policies, for the new cross-department moderation screen.

CREATE POLICY "admin_read_all_channels" ON dept_channels FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
      AND profiles.role = ANY (ARRAY['admin','super_admin'])
  )
);

CREATE POLICY "admin_read_all_messages" ON dept_messages FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
      AND profiles.role = ANY (ARRAY['admin','super_admin'])
  )
);

CREATE POLICY "admin_delete_any_message" ON dept_messages FOR DELETE USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
      AND profiles.role = ANY (ARRAY['admin','super_admin'])
  )
);
