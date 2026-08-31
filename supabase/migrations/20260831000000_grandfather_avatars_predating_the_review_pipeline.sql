-- Grandfather pre-existing avatars into the new photo-review gate.
--
-- profile_is_complete() (20260830164152) requires avatar_review_status IN
-- ('pending','approved') once verified_at is more than 48h in the past. The
-- migration that introduced the column correctly backfilled verified_at from
-- created_at, but never backfilled avatar_review_status for accounts that
-- already had a perfectly good avatar_url from before this review pipeline
-- existed -- so every pre-2026-08-30 account with a real photo was left at
-- the 'none' default, with a 48h grace window that was already exhausted the
-- moment the migration ran (verified_at was backfilled from created_at, not
-- now()). Confirmed live: an already-verified account with a set avatar_url
-- was permanently stuck on /complete-profile, re-showing "Upload a real,
-- formal photo" for a photo it already had, on every visit.
--
-- Safe to scope this broadly and permanently, not just as a one-time
-- backfill: 20260830165726 (self_edit_cannot_forge_its_own_avatar_approval)
-- already closed the direct-write bypass, so avatar_url can now ONLY be set
-- by admin_approve_avatar(), which always sets avatar_review_status =
-- 'approved' in the same statement. avatar_url is not null AND
-- avatar_review_status = 'none' is therefore a combination that can only
-- exist as a pre-existing-photo leftover, never as a new row -- there is no
-- future account this could ever misclassify.
update public.profiles
   set avatar_review_status = 'approved',
       avatar_reviewed_at = coalesce(avatar_reviewed_at, now())
 where avatar_review_status = 'none'
   and avatar_url is not null;
