-- A release reaches people the moment it goes live, and can never ship a dead
-- download link again.
--
-- TWO THINGS WERE WRONG.
--
-- 1. `version` kept being written WITH the build number. 12 of the 15 rows in
--    this table read like `2.3.2+21`, and the client builds its download URL
--    from that value:
--        https://github.com/<owner>/AFOS/releases/download/v2.3.2+21/AFOS-v2.3.2+21.apk
--    The git tag and the release asset are `v2.3.2` / `AFOS-v2.3.2.apk`, so
--    every one of those rows 404s. Worse, the client's version comparison split
--    on '.', found the last segment was the string '2+21', failed to parse it
--    and counted it as 0 — so `2.3.2+21` compared as **2.3.0**, older than the
--    release it was announcing.
--
--    The client now normalises the value on read, which repairs the rows
--    already here. This constraint stops NEW ones being written that way.
--    NOT VALID on purpose: the 12 historical rows stay exactly as they are
--    (six of them would collapse onto `1.0.0` and destroy real history if they
--    were rewritten), while every future insert and update is checked.
--
-- 2. Nothing told anyone. A row landed in this table and the only way to find
--    out was to open Settings and let it poll. The trigger below writes the
--    in-app notification for every account inside the same transaction as the
--    release row, so "published" and "announced" cannot come apart.
--    user_notifications is in the realtime publication, so a running app shows
--    it immediately.
--
-- The push banner to a CLOSED app is still separate: send-notification runs
-- with verify_jwt, so a trigger could only reach it by holding a service-role
-- key in the database. That is a deliberate omission, not an oversight.

ALTER TABLE app_releases
  DROP CONSTRAINT IF EXISTS app_releases_version_no_build;

ALTER TABLE app_releases
  ADD CONSTRAINT app_releases_version_no_build
  CHECK (position('+' in version) = 0) NOT VALID;

CREATE OR REPLACE FUNCTION notify_new_release()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- Everyone, deliberately. A release note is not role-scoped, and this
  -- project's audience-consistency audit exists precisely because "who gets
  -- told" kept drifting from "who it is for".
  INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
  SELECT p.id,
         'AFOS ' || NEW.version || ' is available',
         COALESCE(NULLIF(NEW.title, ''), 'A new version of AFOS is ready to install.'),
         'app_update',
         -- /settings, not /releases: this notification exists so the user can
         -- UPDATE, and the Update button lives on Settings. /releases is the
         -- read-only What's New list and would be a dead end from here.
         '/settings'
  FROM profiles p;

  RETURN NEW;
END;
$fn$;

-- INSERT only. Fixing a typo in a title must not re-announce the release to
-- every user a second time.
DROP TRIGGER IF EXISTS trg_notify_new_release ON app_releases;
CREATE TRIGGER trg_notify_new_release
  AFTER INSERT ON app_releases
  FOR EACH ROW EXECUTE FUNCTION notify_new_release();

REVOKE ALL ON FUNCTION notify_new_release() FROM public, anon, authenticated;
