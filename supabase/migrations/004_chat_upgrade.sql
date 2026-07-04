-- ══════════════════════════════════════════════════════════════════════
--  AFOS — Dept chat: role-scoped channels + 24h message auto-expiry
--  Run after 001_init.sql. Requires pg_cron extension (enable via
--  Supabase Dashboard → Database → Extensions → pg_cron if this errors).
-- ══════════════════════════════════════════════════════════════════════

-- 'students'/'teachers' channels are visible only to that role; 'all' is
-- the common informal channel both roles share.
ALTER TABLE dept_channels ADD COLUMN IF NOT EXISTS audience TEXT DEFAULT 'all'
  CHECK (audience IN ('students','teachers','all'));

-- Re-seed: keep 'general' as the common student+teacher channel, add a
-- students-only lounge and a teachers-only room per department.
UPDATE dept_channels SET audience = 'all' WHERE channel_name IN ('general','events');
UPDATE dept_channels SET audience = 'teachers' WHERE channel_name = 'notices';
UPDATE dept_channels SET audience = 'students' WHERE channel_name = 'academic';

INSERT INTO dept_channels(department,channel_name,description,audience) VALUES
  ('CSE','student-lounge','Students only — daily chat','students'),
  ('CSE','faculty-room','Faculty only — daily chat','teachers'),
  ('EEE','student-lounge','Students only — daily chat','students'),
  ('EEE','faculty-room','Faculty only — daily chat','teachers'),
  ('BBA','student-lounge','Students only — daily chat','students'),
  ('BBA','faculty-room','Faculty only — daily chat','teachers')
ON CONFLICT DO NOTHING;

-- Replace read/send policies to also gate on audience vs the caller's role.
DROP POLICY IF EXISTS "auth_read_channels" ON dept_channels;
CREATE POLICY "auth_read_channels" ON dept_channels FOR SELECT TO authenticated USING (
  audience = 'all'
  OR (audience = 'teachers' AND EXISTS(SELECT 1 FROM profiles WHERE id=auth.uid() AND role IN ('faculty','admin','dept_head')))
  OR (audience = 'students' AND EXISTS(SELECT 1 FROM profiles WHERE id=auth.uid() AND role NOT IN ('faculty','admin','dept_head')))
);

DROP POLICY IF EXISTS "dept_members_read" ON dept_messages;
CREATE POLICY "dept_members_read" ON dept_messages FOR SELECT TO authenticated USING (
  EXISTS(
    SELECT 1 FROM profiles p JOIN dept_channels c ON p.department = c.department
    WHERE p.id = auth.uid() AND c.id = channel_id
      AND (
        c.audience = 'all'
        OR (c.audience = 'teachers' AND p.role IN ('faculty','admin','dept_head'))
        OR (c.audience = 'students' AND p.role NOT IN ('faculty','admin','dept_head'))
      )
  )
);

DROP POLICY IF EXISTS "members_send" ON dept_messages;
CREATE POLICY "members_send" ON dept_messages FOR INSERT WITH CHECK (
  auth.uid() = sender_id
  AND EXISTS(
    SELECT 1 FROM profiles p JOIN dept_channels c ON p.department = c.department
    WHERE p.id = auth.uid() AND c.id = channel_id
      AND (
        c.audience = 'all'
        OR (c.audience = 'teachers' AND p.role IN ('faculty','admin','dept_head'))
        OR (c.audience = 'students' AND p.role NOT IN ('faculty','admin','dept_head'))
      )
  )
);

-- Poster can delete their own message manually.
DROP POLICY IF EXISTS "own_message_delete" ON dept_messages;
CREATE POLICY "own_message_delete" ON dept_messages FOR DELETE USING (auth.uid() = sender_id);

-- 24-hour auto-expiry: schedule a recurring cleanup rather than relying
-- on client-side filtering, so messages are actually gone (storage +
-- everyone's view) once they age out, not just hidden.
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.unschedule(jobid) FROM cron.job WHERE jobname = 'expire-dept-messages';
SELECT cron.schedule(
  'expire-dept-messages',
  '*/15 * * * *',
  $$DELETE FROM dept_messages WHERE created_at < now() - interval '24 hours'$$
);
