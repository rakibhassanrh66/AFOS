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
  'Updates That Actually Install',
  ARRAY[
    'Tapping Update now installs. The download link pointed at a release that did not exist, and the error page it fetched was handed to Android as if it were the app — which is exactly what "There was a problem parsing the package" was telling you.',
    'A half-finished or corrupted download is now detected and thrown away instead of being installed, and a failed attempt can no longer poison the next one.',
    'When Android refuses an install you are told why, instead of nothing happening. Usually it is "Install unknown apps", which needs turning on for AFOS once.',
    'You are told as soon as a new version is released — including when AFOS is closed — instead of having to open Settings and check.',
    'After an update finishes installing, AFOS comes back on its own. Where Android blocks that, you get a tap-to-open notification instead.'
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

--  DRAFTED, NOT FINAL. Written by reading each tag's actual commit range and
--  saying what a student or teacher would notice — not generated from commit
--  subjects. Edit freely before running; you know what these felt like to use.

INSERT INTO app_releases (version, release_date, title, highlights, platforms) VALUES

  ('1.2.1', '2026-07-18', 'Fingerprint Login, New Navigation & Transport', ARRAY[
    'Sign in with your fingerprint or face instead of typing your password every time.',
    'A new floating bottom navigation bar, with the SOS button moved somewhere it is not in the way, and a proper side rail on desktop web.',
    'Transport rebuilt: routes grouped sensibly, working time pickers, and schedule data that is actually normalised.',
    'Fixed the navigation labels overlapping their icons, and the splash screen popping out of place on launch.'
  ], ARRAY['android', 'web']),

  ('2.3.3', '2026-07-23', 'Smoother Live Screens & Transport Search', ARRAY[
    'Live screens no longer flicker when several updates land at once — they are batched instead of redrawing on every single change.',
    'Search every transport route from one place, rather than opening them one at a time.',
    'Transport stops stay in step with the route they belong to.',
    'Search no longer errors on unusual characters.'
  ], ARRAY['android', 'web']),

  ('2.5.2', '2026-07-24', 'Network Performance', ARRAY[
    'Fewer and smaller network requests throughout the app, so screens settle noticeably faster on a slow or crowded connection.'
  ], ARRAY['android', 'web']),

  ('2.5.21', '2026-07-26', 'Attendance, Grading & Joining a Course', ARRAY[
    'Attendance registers, including lab groups and bonus marks.',
    'Full DIU mark components, a CGPA and SGPA engine, and assignment grading.',
    'Module leaders can allocate teaching load to their team.',
    'Students can cancel a join request they no longer want; teachers can admit everyone matching the right batch and section in one action.',
    'Ended courses are visible again and can be restored if one was closed by mistake.',
    'Results are grouped by semester and show SGPA.',
    'Fixed: Join Requests and All Routes rendered as empty pages when they had data all along, results notifications went to the entire batch instead of the class, and some students were missing from rosters and notifications entirely.'
  ], ARRAY['android', 'web']),

  ('2.6.0', '2026-07-26', 'Teaching Allocations & Student Attendance', ARRAY[
    'Teachers can accept or decline a teaching allocation rather than having it simply assigned.',
    'Students can see their own attendance record.',
    'Who gets notified now comes from a single shared definition, so the people told in the app and the people sent a push are always the same people.'
  ], ARRAY['android', 'web']),

  ('2.6.1', '2026-07-26', 'Notification Safeguard', ARRAY[
    'A standing automated check that a notification''s in-app audience and its push audience cannot quietly drift apart. Invisible day to day — it exists because they had already drifted twice without anyone noticing.'
  ], ARRAY['android', 'web']),

  ('2.6.2', '2026-07-26', 'Offering Approvals Tightened', ARRAY[
    'A course offering can only be created from a teaching allocation that was actually accepted, closing a gap where one could be raised against an allocation nobody had agreed to.'
  ], ARRAY['android', 'web'])

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
