-- =====================================================================
--  AFOS — Add RULE/ANNOUNCEMENT to notices.category, matching the app's
--  existing uppercase convention (GENERAL, EXAM, EVENT, URGENT already
--  in use) — found live-testing the new Manage Notices & Rules screen,
--  whose first insert attempt was rejected outright by this constraint.
-- =====================================================================

ALTER TABLE notices DROP CONSTRAINT notices_category_check;
ALTER TABLE notices ADD CONSTRAINT notices_category_check
  CHECK (category = ANY (ARRAY['GENERAL','EXAM','EVENT','URGENT','RULE','ANNOUNCEMENT']));
