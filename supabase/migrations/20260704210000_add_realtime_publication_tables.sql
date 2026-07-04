-- The `supabase_realtime` publication existed but had ZERO tables in it
-- (puballtables = false, pg_publication_tables empty) — meaning
-- .stream()-based realtime silently never fired for ANY table in this
-- project, not just dept_messages. This is the actual root cause behind
-- "must leave and re-enter to see my own message" and would equally have
-- affected live notices/schedule/transport updates without anyone
-- necessarily noticing (those change far less often while a screen is
-- open). Add every table the Flutter app currently drives via
-- SupabaseQueryBuilder.stream().
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['dept_messages','notices','schedule_slots','transport_routes','transport_live_status']
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND tablename = t
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE %I', t);
    END IF;
  END LOOP;
END $$;
