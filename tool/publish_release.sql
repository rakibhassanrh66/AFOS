-- =====================================================================
--  AFOS — publishing a release, and backfilling the ones that got away.
--
--  The `app_releases` row is written BY HAND. That is deliberate and
--  documented in .github/workflows/main.yml: a generated changelog once
--  shipped "fix: PostgREST profiles embeds on enrollments/course_offerings
--  (v2.5.3)" to students as release notes. Commit subjects are written for
--  `git log`; release notes are written for someone deciding whether to
--  install. Mechanically deriving one from the other cannot work.
--
--  This file is the ritual, not automation of it.
--
--  ORDER OF OPERATIONS — this matters.
--
--    1. Bump `version:` in pubspec.yaml, commit, push.
--    2. Tag it:  git tag v2.7.7 && git push origin v2.7.7
--    3. WAIT for the `release` job to finish and publish the APK asset.
--    4. ONLY THEN run section 1 below.
--
--  Step 3 is not optional. Inserting the row is what tells every user an
--  update exists, and the download URL the app builds from it is
--      https://github.com/rakibhassanrh66/AFOS/releases/download/v<X>/AFOS-v<X>.apk
--  which does not exist until the release job has uploaded it. Announcing
--  first means everyone who taps Update gets an error until CI catches up.
--
--  `version` MUST NOT carry the +build suffix — write '2.7.7', not
--  '2.7.7+63'. A trigger rejects it now, because twelve historical rows were
--  written that way and every one of them produced a 404 download URL and
--  compared as OLDER than the release it was announcing.
-- =====================================================================


-- ---------------------------------------------------------------------
--  1. PUBLISH a new release. This one announces.
-- ---------------------------------------------------------------------
--  Inserting this row does all of the following, in one transaction:
--    * writes an in-app notification for every account (trigger);
--    * queues the OneSignal push so phones with AFOS CLOSED get a banner
--      (announce-release edge function, via pg_net);
--    * pushes the row over realtime so an app that is OPEN raises its
--      update banner without the user doing anything.
--
--  Nothing else is required. Do not also send a manual broadcast.

INSERT INTO app_releases (version, release_date, title, highlights, platforms)
VALUES (
  '2.7.7',
  current_date,
  'TITLE HERE — what changed, in the user''s words',
  ARRAY[
    'One sentence per change, written for someone deciding whether to install.',
    'Say what they will notice, not which function was edited.'
  ],
  ARRAY['android']
);


-- ---------------------------------------------------------------------
--  2. BACKFILL history. This one stays silent.
-- ---------------------------------------------------------------------
--  Seven releases exist as GitHub tags but were never written here, so they
--  are missing from What's New:
--
--    1.2.1  (2026-07-18)   2.5.2   (2026-07-24)   2.6.1  (2026-07-26)
--    2.3.3  (2026-07-23)   2.5.21  (2026-07-26)   2.6.2  (2026-07-26)
--                          2.6.0   (2026-07-26)
--
--  SET LOCAL afos.suppress_release_announce = 'on' is what keeps this quiet.
--  Without it the newest row in this batch would announce itself — every
--  one of these shares release_date 2026-07-26 with the current newest row
--  (2.5.5), so created_at breaks the tie and a freshly-inserted 2.6.2 WOULD
--  read as the newest release in the table. It is not: 2.7.x has shipped
--  since. "AFOS 2.6.2 is available" is not something anyone should receive.
--
--  Run the whole block as one transaction — SET LOCAL is scoped to it.

BEGIN;

SET LOCAL afos.suppress_release_announce = 'on';

INSERT INTO app_releases (version, release_date, title, highlights, platforms) VALUES
  ('1.2.1',  '2026-07-18', 'TITLE', ARRAY['TODO'], ARRAY['android']),
  ('2.3.3',  '2026-07-23', 'TITLE', ARRAY['TODO'], ARRAY['android']),
  ('2.5.2',  '2026-07-24', 'TITLE', ARRAY['TODO'], ARRAY['android']),
  ('2.5.21', '2026-07-26', 'TITLE', ARRAY['TODO'], ARRAY['android']),
  ('2.6.0',  '2026-07-26', 'TITLE', ARRAY['TODO'], ARRAY['android']),
  ('2.6.1',  '2026-07-26', 'TITLE', ARRAY['TODO'], ARRAY['android']),
  ('2.6.2',  '2026-07-26', 'TITLE', ARRAY['TODO'], ARRAY['android'])
ON CONFLICT (version) DO NOTHING;

-- Confirm nothing was announced before committing. Expect 0.
SELECT count(*) AS should_be_zero
  FROM user_notifications
 WHERE category = 'app_update'
   AND created_at > now() - interval '1 minute';

COMMIT;


-- ---------------------------------------------------------------------
--  3. Did the push actually go out?
-- ---------------------------------------------------------------------
--  push_sent_at is stamped by announce-release when OneSignal accepts the
--  broadcast, and cleared again if it did not, so a NULL here on the newest
--  row means the pg_cron job ('announce-pending-release', every 5 minutes)
--  still has work to do rather than that the push was lost.

SELECT version, release_date, push_sent_at
  FROM app_releases
 ORDER BY release_date DESC, created_at DESC
 LIMIT 5;
