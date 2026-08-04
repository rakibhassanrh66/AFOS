-- A new release reaches a phone that isn't running AFOS — and the in-app
-- watcher that was supposed to catch it while the app IS running actually
-- fires.
--
-- WHAT WAS STILL BROKEN AFTER 20260804095848.
--
-- 1. THE LIVE WATCHER WAS SUBSCRIBED TO NOTHING. AppUpdateService.start()
--    subscribes to INSERTs on app_releases to raise the update banner the
--    moment a release lands. `app_releases` was never added to the
--    `supabase_realtime` publication, so Postgres never emitted those changes
--    and the callback could not fire — a silent no-op, because an empty
--    realtime stream is indistinguishable from "no releases yet".
--
-- 2. NOTHING REACHED A CLOSED APP. The trigger writes the durable in-app row
--    for every profile, which is right and unlosable, but a notification
--    telling you to install an update is worth least to the one person
--    guaranteed to see it — someone already using the app. The push banner is
--    the whole point, and it was explicitly left out.
--
-- WHY POSTGRES IS ALLOWED TO MAKE THIS HTTP CALL.
--
-- 20260725202958 states the rule: "Postgres has no business making outbound
-- HTTP calls inside a transaction." That rule stands, and this does not break
-- it. `net.http_post` does not perform a request — it appends a row to pg_net's
-- queue, which a background worker drains AFTER the transaction commits. The
-- insert never blocks on OneSignal, and a failed push can never roll back a
-- published release. A synchronous `http` (curl) extension call, which is what
-- that rule was written against, would do both.
--
-- WHY THE ENDPOINT NEEDS NO SECRET. See supabase/functions/announce-release.
-- The bearer token below is the project's PUBLISHABLE key, which is already
-- compiled into every copy of the app (lib/config/supabase_config.dart:6) —
-- writing it here discloses nothing that shipping the APK did not. It exists
-- only to satisfy the function gateway, which keeps verify_jwt ON so anonymous
-- internet traffic is refused before reaching the function at all.
--
-- The endpoint is safe to reach regardless: it takes no caller-supplied content
-- or audience, and claim_release_announcement() below stamps the row in the
-- same statement that reads it, so calling it twice sends once.
--
-- The alternative — a service-role key stored in the database so a trigger
-- could call send-notification — would put full project credentials behind
-- every SQL-injection and every over-permissive definer function in the
-- schema, to send one notification.

-- Queue-based, non-blocking HTTP. See the note above on why this is compatible
-- with the no-HTTP-in-a-transaction rule.
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ---------------------------------------------------------------------------
-- 1. The live in-app watcher can actually receive something.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'app_releases'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.app_releases;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. Un-freeze the twelve historical rows.
-- ---------------------------------------------------------------------------
-- Yesterday's migration added `app_releases_version_no_build` as a NOT VALID
-- CHECK, on the belief that NOT VALID leaves the existing rows alone. It does
-- not. NOT VALID only skips the one-time full-table validation; every
-- subsequent INSERT *and UPDATE* is still checked. So the twelve legacy rows
-- whose version reads `2.3.2+21` became permanently un-updatable — not to fix a
-- typo in a title, not to set any column added later.
--
-- That is how this was found: the very next statement in this migration, the
-- push_sent_at backfill, failed against those rows.
--
-- A CHECK cannot express "constrain the value only when it is being written",
-- so this becomes a trigger, which can. Identical guarantee — no insert and no
-- edit may introduce a `+` — without freezing history that predates the rule.
-- The name is kept deliberately: error_formatter.dart matches on it (substring)
-- to turn a bare 23514 into a message that says what to write instead.
ALTER TABLE public.app_releases
  DROP CONSTRAINT IF EXISTS app_releases_version_no_build;

CREATE OR REPLACE FUNCTION public.app_releases_reject_build_suffix()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF position('+' in NEW.version) > 0
     AND (TG_OP = 'INSERT' OR NEW.version IS DISTINCT FROM OLD.version) THEN
    RAISE EXCEPTION
      'app_releases_version_no_build: release version must not include the build number (got "%")',
      NEW.version
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_app_releases_version_no_build ON public.app_releases;
CREATE TRIGGER trg_app_releases_version_no_build
  BEFORE INSERT OR UPDATE ON public.app_releases
  FOR EACH ROW EXECUTE FUNCTION public.app_releases_reject_build_suffix();

-- ---------------------------------------------------------------------------
-- 3. Exactly-once bookkeeping for the push.
-- ---------------------------------------------------------------------------
ALTER TABLE public.app_releases
  ADD COLUMN IF NOT EXISTS push_sent_at timestamptz;

-- Every release that already exists is marked as announced. Without this the
-- first thing the new machinery would do is push "AFOS 2.5.5 is available" to
-- everyone — a release from over a week ago, and one that is not even the
-- newest build any more.
UPDATE public.app_releases SET push_sent_at = COALESCE(push_sent_at, created_at);

COMMENT ON COLUMN public.app_releases.push_sent_at IS
  'When the OneSignal broadcast for this release went out. NULL means still '
  'pending; the announce-release function claims it by stamping this, and the '
  'pg_cron safety net retries anything still NULL.';

-- ---------------------------------------------------------------------------
-- 4. Claiming a release to announce.
-- ---------------------------------------------------------------------------

-- Returns the newest release if it has not been pushed yet, and marks it as
-- pushed in the same statement — so a second concurrent caller blocks on the
-- row lock, re-reads `push_sent_at IS NULL` as false, and gets nothing back.
-- That single property is what lets the trigger and a retrying cron job both
-- poke the endpoint without anyone being notified twice.
--
-- LANGUAGE sql, not plpgsql, on purpose: a plpgsql function with RETURNS TABLE
-- (id, version, title) would have output variables shadowing those same column
-- names in the RETURNING list.
CREATE OR REPLACE FUNCTION public.claim_release_announcement()
RETURNS TABLE (id uuid, version text, title text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH newest AS (
    SELECT r.id FROM public.app_releases r
    ORDER BY r.release_date DESC, r.created_at DESC
    LIMIT 1
  )
  UPDATE public.app_releases r
     SET push_sent_at = now()
    FROM newest n
   WHERE r.id = n.id
     AND r.push_sent_at IS NULL
  RETURNING r.id, r.version, r.title;
$$;

-- Hands a claim back when the push got nowhere, so the safety net retries
-- instead of the release being permanently recorded as announced.
CREATE OR REPLACE FUNCTION public.release_announcement_failed(p_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.app_releases SET push_sent_at = NULL WHERE id = p_id;
$$;

-- Both are SECURITY DEFINER and must not be reachable by anon — the standing
-- assertion in .github/scripts/check_definer_acls.py, which this repo has
-- tripped three times. CREATE FUNCTION grants EXECUTE to PUBLIC by default.
REVOKE ALL ON FUNCTION public.claim_release_announcement() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.release_announcement_failed(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_release_announcement() TO service_role;
GRANT EXECUTE ON FUNCTION public.release_announcement_failed(uuid) TO service_role;

-- ---------------------------------------------------------------------------
-- 5. The trigger: announce, and know when not to.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_new_release()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE
  v_superseded boolean;
BEGIN
  -- A backfill is not an announcement. Four shipped releases (2.5.21 through
  -- 2.6.2) were never written to this table, and adding them later must not
  -- fire four "AFOS 2.5.21 is available" notifications at everyone for builds
  -- that are already superseded.
  --
  -- Two independent guards, because the cheap structural one covers the case
  -- the operator forgets:
  --   * any row that is not the newest release is self-evidently history;
  --   * `SET LOCAL afos.suppress_release_announce = 'on'` silences the rest.
  SELECT EXISTS (
    SELECT 1 FROM public.app_releases r
    WHERE r.id <> NEW.id
      AND (r.release_date, r.created_at) > (NEW.release_date, NEW.created_at)
  ) INTO v_superseded;

  IF v_superseded
     OR COALESCE(current_setting('afos.suppress_release_announce', true), '') = 'on' THEN
    -- Stamped so it can never be picked up later if dates are corrected.
    UPDATE public.app_releases SET push_sent_at = now()
      WHERE id = NEW.id AND push_sent_at IS NULL;
    RETURN NEW;
  END IF;

  -- Everyone, deliberately. A release note is not role-scoped, and this
  -- project's audience-consistency audit exists precisely because "who gets
  -- told" kept drifting from "who it is for". announce-release resolves its
  -- push audience from this same table, so the two cannot disagree.
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

  -- Queued, not sent. Drains after this transaction commits; if the request is
  -- lost the pg_cron job below picks it up within five minutes.
  PERFORM net.http_post(
    url := 'https://dtsptjallznnvattadlu.supabase.co/functions/v1/announce-release',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer sb_publishable_x92WJ4FXzEVBTTY_9IKN5Q_0qK9qyuc'
    ),
    timeout_milliseconds := 10000
  );

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION public.notify_new_release() FROM public, anon, authenticated;

-- INSERT only. Fixing a typo in a title must not re-announce the release to
-- every user a second time.
DROP TRIGGER IF EXISTS trg_notify_new_release ON public.app_releases;
CREATE TRIGGER trg_notify_new_release
  AFTER INSERT ON public.app_releases
  FOR EACH ROW EXECUTE FUNCTION public.notify_new_release();

-- ---------------------------------------------------------------------------
-- 6. Safety net, so "the moment it goes live" survives a bad five minutes.
-- ---------------------------------------------------------------------------
-- The trigger's pg_net request is best-effort by nature: OneSignal can be down,
-- the worker can be mid-restart, the request can time out. This turns the push
-- from best-effort into eventually-guaranteed — it retries until push_sent_at
-- is set. The WHERE clause means it is a single cheap query and no HTTP call at
-- all on the ~99.9% of runs where there is nothing pending.
SELECT cron.unschedule('announce-pending-release')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'announce-pending-release');

SELECT cron.schedule(
  'announce-pending-release',
  '*/5 * * * *',
  $cron$
  SELECT net.http_post(
    url := 'https://dtsptjallznnvattadlu.supabase.co/functions/v1/announce-release',
    body := '{}'::jsonb,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer sb_publishable_x92WJ4FXzEVBTTY_9IKN5Q_0qK9qyuc'
    ),
    timeout_milliseconds := 10000
  )
  WHERE EXISTS (
    SELECT 1 FROM (
      SELECT push_sent_at FROM public.app_releases
      ORDER BY release_date DESC, created_at DESC LIMIT 1
    ) newest
    WHERE newest.push_sent_at IS NULL
  );
  $cron$
);
