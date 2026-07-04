-- Dept chat channels were only ever seeded for CSE/EEE/BBA (001_init.sql,
-- 004_chat_upgrade.sql). The other 9 real DIU departments have zero
-- dept_channels rows, meaning there is no student/teacher audience
-- separation infrastructure for them at all. Seed all departments
-- data-driven off the real `departments` table instead of more hardcoded
-- per-department literals. Idempotent via the existing
-- UNIQUE(department, channel_name) constraint.

INSERT INTO dept_channels (department, channel_name, description, audience)
SELECT d.code, x.channel_name, x.description, x.audience
FROM departments d
CROSS JOIN (VALUES
  ('general',        'General discussion',         'all'),
  ('notices',        'Official notices',           'teachers'),
  ('academic',       'Academic help',               'students'),
  ('events',         'Events & activities',         'all'),
  ('student-lounge', 'Students only — daily chat',  'students'),
  ('faculty-room',   'Faculty only — daily chat',   'teachers')
) AS x(channel_name, description, audience)
ON CONFLICT (department, channel_name) DO NOTHING;
