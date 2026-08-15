-- Accepting a claim is not the same event as handing the item over.
--
-- APPLIED 2026-08-15. Found while TESTING the migration above, which is the
-- only reason it was found at all: a THIRD disconnected track nobody had
-- named. `handle_claim_accepted` did two jobs in one trigger:
--
--     UPDATE lost_found_posts  SET status = 'returned' ...
--     UPDATE lost_found_claims SET status = 'rejected' ...
--
-- So the moment a poster accepted a claim, the item was recorded as RETURNED
-- -- before the two people had met, with nothing recording who received it,
-- and with no way to distinguish "agreed you can have it" from "you have it".
-- It also silently overwrote the awaiting_handover state that
-- complete_lost_found_handover exists to consume; the new RPC only appeared to
-- work because it happened to write after the trigger, which is luck, not
-- design.
--
-- The trigger keeps the half that is genuinely useful -- closing the other
-- claims, which also covers a direct UPDATE that bypasses the RPC -- and stops
-- deciding that the item has been returned.
--
-- 'superseded', not 'rejected': the other claimants were not turned down on
-- the merits, someone else was accepted first. Telling five people they were
-- rejected when they were simply not first is a small lie the UI then carries.
create or replace function public.handle_claim_accepted()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
BEGIN
  IF NEW.status = 'accepted' AND OLD.status IS DISTINCT FROM 'accepted' THEN
    -- awaiting_handover, NOT returned. It becomes returned only via
    -- complete_lost_found_handover (VR-ID verified) or
    -- close_lost_found_unverified (recorded as unproven).
    UPDATE lost_found_posts
       SET status = 'awaiting_handover'
     WHERE id = NEW.post_id
       AND status <> 'returned';

    UPDATE lost_found_claims SET status = 'superseded'
      WHERE post_id = NEW.post_id AND id <> NEW.id AND status = 'pending';
  END IF;
  RETURN NEW;
END; $function$;
