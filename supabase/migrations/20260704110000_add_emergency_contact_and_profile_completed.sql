-- =====================================================================
--  AFOS — Add emergency contact field + a profile-completion flag
--
--  profile_completed lets the app force first-time profile completion
--  (name/department/semester/etc were skippable at signup) without
--  re-deriving "is this profile complete" from scattered null-checks
--  every time — it's set true once the user saves the completion form,
--  and the router can gate on this single boolean.
-- =====================================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS emergency_contact text;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS profile_completed boolean NOT NULL DEFAULT false;

-- Anyone who already has the core fields filled in (pre-existing users)
-- shouldn't suddenly get forced through a completion screen.
UPDATE profiles SET profile_completed = true
WHERE full_name IS NOT NULL AND full_name <> 'New User'
  AND department IS NOT NULL AND semester IS NOT NULL;
