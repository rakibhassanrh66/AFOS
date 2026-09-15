-- Corrects the placeholder row that got inserted with literal template text
-- (version 'X.Y.Z', title 'RELEASE TITLE') and already sent a push to 20
-- recipients. UPDATE, not delete+insert, so this does NOT re-trigger the
-- announce/push flow (that fires on INSERT) and does not double-notify
-- anyone. Corrects the in-app "What's New" content and makes `version` a
-- real, comparable value so AppUpdateService.isNewer() works correctly.

UPDATE app_releases
SET
  version = '2.13.1',
  title = 'Updates That Can''t Be Broken Anymore',
  highlights = ARRAY[
    'Updating the app is now safe no matter what you do while it is downloading. Minimizing AFOS, closing the update screen, or tapping Update again partway through could previously leave you with an install that silently failed or behaved oddly - the app now tracks one download at a time correctly, so nothing you do after tapping Update can break it.',
    'Searching for a student or book while issuing a library loan is noticeably faster and no longer sends a request on every keystroke.',
    'Small behind-the-scenes cleanups to keep the app fast and lean.'
  ]
WHERE version = 'X.Y.Z' AND title = 'RELEASE TITLE';

-- Confirm exactly one row changed, and that it now reads correctly:
SELECT version, release_date, title, highlights, push_sent_at, push_recipients
FROM app_releases
ORDER BY release_date DESC, created_at DESC
LIMIT 3;
