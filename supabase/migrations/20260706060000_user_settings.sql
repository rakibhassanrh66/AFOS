-- Per-user settings: accent color, notification sound preference, chat
-- background, display language — synced via DB (not just local Hive) so
-- they follow the user across devices/reinstalls, per spec ("after saving
-- immediately world database as well").
CREATE TABLE user_settings (
  profile_id uuid PRIMARY KEY REFERENCES profiles(id) ON DELETE CASCADE,
  accent_color text NOT NULL DEFAULT '#1E6FFF',
  notification_sound text NOT NULL DEFAULT 'default' CHECK (notification_sound IN ('default', 'chime', 'bell', 'none')),
  chat_background text NOT NULL DEFAULT 'default',
  language text NOT NULL DEFAULT 'en',
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY own_settings ON user_settings
  FOR ALL
  USING (auth.uid() = profile_id)
  WITH CHECK (auth.uid() = profile_id);
