-- =====================================================================
--  AFOS v2.13.2 — the announcement row.
--
--  RUN THIS ONLY AFTER the v2.13.2 release job has published the APK.
--  Check first:
--    https://github.com/rakibhassanrh66/AFOS/releases/tag/v2.13.2
--    curl -sIL "https://github.com/rakibhassanrh66/AFOS/releases/download/v2.13.2/AFOS-v2.13.2.apk" \
--      -o /dev/null -w "status=%{http_code}\n"     # must be 200
--
--  Inserting this row is what makes the Update button light up. It does all
--  three of these in one transaction, via triggers:
--    - writes an in-app notification for every account,
--    - queues the OneSignal push, so phones with AFOS CLOSED get a banner,
--    - pushes over realtime, so an app that is OPEN raises its update card.
--  Do NOT also send a manual broadcast. It is already done.
--
--  `version` carries NO +build suffix. '2.13.2', never '2.13.2+5029' — a
--  trigger rejects the latter, and historically every row written that way
--  produced a 404 download URL and compared as older than itself.
--
--  A NOTE ON THE LAST ONE. v2.13.1 went out with literal template text in
--  this row ('X.Y.Z' / 'RELEASE TITLE') and pushed that to 20 people before
--  it was corrected by UPDATE (see fix_bad_announce_row.sql). The INSERT
--  below is written out in full, with no placeholders left to forget.
-- =====================================================================

INSERT INTO app_releases (version, release_date, title, highlights, platforms)
VALUES (
  '2.13.2',
  current_date,
  'Faster To Open, Easier To Hear',
  ARRAY[
    -- Say what is different FOR THEM. Not what changed in the code.
    'The app opens faster, and it no longer sits on a blank screen when you are on a weak or half-connected network. Startup used to wait on a connection check that could take four seconds to give up — exactly the situation where it mattered most.',
    'AFOS now works properly with TalkBack and other screen readers. Buttons, cards and icon controls announce what they are and what they do; before, most of them were read out as ordinary text with no indication they could be tapped.',
    'Turning off vibration in Settings now actually turns it off everywhere. The bottom navigation bar and the emergency button were ignoring that switch.',
    'Uploading an exam seat plan or a transport timetable is significantly faster — a re-upload used to make one request per row group and could look like it had frozen.',
    'What''s New now explains how updating works, including that you never need to download anything yourself.',
    'Smaller download: two unused libraries were removed from the build.'
  ],
  ARRAY['android','web']
);

-- Confirm it landed, and that the push actually went:
SELECT version, release_date, title, push_sent_at, push_recipients
FROM app_releases
ORDER BY release_date DESC, created_at DESC
LIMIT 3;
