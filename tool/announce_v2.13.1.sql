-- Standalone announce script for v2.13.1 — separate from publish_release.sql
-- on purpose, so running it does not re-run every historical INSERT in that
-- file (those have no ON CONFLICT guard and would fail on duplicate version).
--
-- Run ONLY after confirming the release APK is actually published:
--   https://github.com/rakibhassanrh66/AFOS/releases/tag/v2.13.1
-- (already verified in this session: all 4 assets present, URLs return 200).

INSERT INTO app_releases (version, release_date, title, highlights, platforms)
VALUES (
  '2.13.1',
  current_date,
  'Updates That Can''t Be Broken Anymore',
  ARRAY[
    'Updating the app is now safe no matter what you do while it is downloading. Minimizing AFOS, closing the update screen, or tapping Update again partway through could previously leave you with an install that silently failed or behaved oddly - the app now tracks one download at a time correctly, so nothing you do after tapping Update can break it.',
    'Searching for a student or book while issuing a library loan is noticeably faster and no longer sends a request on every keystroke.',
    'Small behind-the-scenes cleanups to keep the app fast and lean.'
  ],
  ARRAY['android','web']
);
