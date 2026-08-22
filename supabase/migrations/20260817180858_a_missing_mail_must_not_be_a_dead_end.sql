-- A MISSING MAIL MUST NOT BE A DEAD END.
--
-- Applied 2026-08-17 as ledger version 20260817180858.
--
-- Measured 2026-08-17. Two defects, one symptom: an applicant who receives no
-- mail has no route to an account.
--
-- 1. The secondary path could only be ENTERED BY FAILING AT THE PRIMARY ONE.
--    register-verify raises review_state = 'needs_review' when a code expires
--    or burns all five attempts. Someone who never received a code can do
--    neither -- you cannot exhaust attempts on a code you do not have. They
--    waited out the ten minutes and then had nothing: no queue entry, no
--    administrator aware of them, no button. This is not hypothetical while
--    MAIL_FROM is Resend's sandbox sender (onboarding@resend.dev), which
--    delivers ONLY to the Resend account owner -- today, every applicant but
--    one is in exactly this position.
--
-- 2. purge_identity_ephemera() then deleted the queue. Its sweep removed any
--    unconsumed row 24 hours past expiry with no regard for review_state, so a
--    signup flagged for HUMAN review was destroyed before a human plausibly
--    looked at it. The fallback queue emptied itself daily.
--
-- Adds no table and no policy. One config flag, one rate-limit row, and a
-- purge that stops deleting the thing it was meant to preserve.

-- ---------------------------------------------------------------------------
-- The fallback as DATA, matching auto_approve_roles and registration_open
-- rather than inventing a second mechanism. Turn it off with a one-row UPDATE
-- the day a real sending domain is verified; the button then stops being
-- offered by the client on the next registration request, with no redeploy.
-- ---------------------------------------------------------------------------
alter table app_config
  add column if not exists manual_approval_fallback boolean not null default true;

comment on column app_config.manual_approval_fallback is
  'Offers the applicant an "I never received the email" button that raises their signup for human review. ON while mail delivery is unreliable; set false once a verified sending domain is in place.';

-- ---------------------------------------------------------------------------
-- Its own bucket, deliberately NOT email_verify_attempt. Raising a hand is not
-- a guess at a code, and spending guess budget on it would let an applicant
-- lock themselves out of the very code they are still waiting for.
--
-- Capacity 2, refill 0.02/min (~1 per 50 minutes sustained). Asking twice does
-- not make an administrator arrive sooner, and this write is what puts a row
-- in front of a human -- so it is spammable by definition and wants a tighter
-- bucket than the mail paths, not a looser one.
--
-- Until this row exists consume_rate_limit() returns TRUE for an unknown
-- bucket, so the endpoint runs unlimited on this axis. That is why the
-- function also spends the existing email_verify_ip bucket, which already
-- exists and therefore protects the endpoint before this migration lands.
-- ---------------------------------------------------------------------------
insert into rate_limit_policies (bucket, capacity, refill_per_minute, description) values
  ('registration_review_request', 2, 0.02, 'Applicant-raised manual approval requests per address')
on conflict (bucket) do nothing;

-- ---------------------------------------------------------------------------
-- STOP DELETING THE REVIEW QUEUE.
--
-- Before: one sweep took every unconsumed row 24 hours past expiry. Codes
-- expire in 10 minutes, so a signup awaiting a human had ~24 hours to live --
-- shorter than a weekend, and shorter than most people answer in.
--
-- After: 'needs_review' is exempt from the short sweep and kept 30 days. Every
-- other state behaves exactly as before. 'rejected' is deliberately still
-- swept at 24 hours -- a decision was made and the row is spent -- and the
-- review-request endpoint never revives a rejected row.
-- ---------------------------------------------------------------------------
create or replace function public.purge_identity_ephemera()
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  delete from pending_registrations
   where consumed_at is not null and consumed_at < now() - interval '1 hour';

  -- Abandoned or declined. Identical to the original sweep except for the one
  -- clause that stops it eating the queue.
  delete from pending_registrations
   where consumed_at is null
     and review_state <> 'needs_review'
     and expires_at < now() - interval '24 hours';

  -- Waiting on a person. Kept long enough that a human is the reason it
  -- leaves, not a cron tick -- but still bounded, so an ignored queue cannot
  -- hold encrypted passwords forever.
  delete from pending_registrations
   where consumed_at is null
     and review_state = 'needs_review'
     and created_at < now() - interval '30 days';

  delete from pending_password_resets
   where consumed_at is not null and consumed_at < now() - interval '1 hour';
  delete from pending_password_resets
   where consumed_at is null and expires_at < now() - interval '24 hours';
  delete from email_outbox
   where state = 'sent' and sent_at < now() - interval '24 hours';
  delete from email_outbox
   where state = 'dropped' and created_at < now() - interval '7 days';
end;
$$;

revoke all on function public.purge_identity_ephemera() from public, anon, authenticated;
