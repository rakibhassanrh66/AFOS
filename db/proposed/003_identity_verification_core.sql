-- 003_identity_verification_core.sql
--
-- APPLIED 2026-08-16. Kept as the reviewed proposal it was; the authoritative
-- copy is supabase/migrations/20260816190000_prove_the_mailbox_not_the_string.sql
-- and any further change belongs in a NEW migration, never in this file.
--
-- Originally: PROPOSED — NOT APPLIED. Reviewed by the project owner before any migration
-- is generated from it (CLAUDE.md HARD RULE 1).
--
-- WHY THIS EXISTS
-- ---------------
-- Today `enforce_email_domain` proves an address *ends in* @diu.edu.bd and
-- `auto_confirm_email` then force-stamps email_confirmed_at on every insert.
-- Measured on the live project 2026-08-16: all 12 auth.users rows carry
-- conf_mail_sent = false, confirmed = true. Not one verification mail has ever
-- been sent. The system therefore proves the FORMAT of an address and never
-- proves CONTROL of the mailbox, so anyone who knows DIU's address pattern can
-- register as a student they have never met, and management is asked to
-- adjudicate identity with no evidence attached.
--
-- This file adds the staging + delivery substrate that lets registration prove
-- mailbox control before an auth user is ever created.
--
-- DESIGN NOTE — the flow inverts. auth.signUp is no longer called by the
-- client. A signup writes to pending_registrations; the auth user is created by
-- the register-verify edge function (service role, admin API) only after the
-- emailed code or link is redeemed. auth.users then contains only
-- mailbox-proven accounts and junk never reaches profiles/students/teachers.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. Staged registrations
-- ---------------------------------------------------------------------------
-- Holds the signup payload while the mailbox is unproven. Deliberately NOT a
-- profile row: nothing unproven touches the real tables.
create table if not exists pending_registrations (
  id            uuid primary key default gen_random_uuid(),
  email         text not null,
  -- lower(btrim(...)) is immutable, so it is indexable as a stored generated
  -- column. Matching is always done on this, never on raw email.
  email_norm    text generated always as (lower(btrim(email))) stored,

  -- The signUp metadata verbatim (full_name, university_id, department,
  -- semester, account_type, gender, program_id, batch, section, designation,
  -- staff_category, office). Replayed into admin.createUser's user_metadata on
  -- redemption so handle_new_user() builds the profile EXACTLY as it does
  -- today — that trigger is not modified by this change.
  payload       jsonb not null,

  -- Never store the code or token themselves. HMAC-SHA256 with a server-side
  -- pepper held in the edge function's env, so a database leak alone does not
  -- yield a usable code.
  code_hash     text not null,
  token_hash    text not null,

  attempts      smallint not null default 0,
  max_attempts  smallint not null default 5,

  expires_at    timestamptz not null,
  created_at    timestamptz not null default now(),
  last_sent_at  timestamptz,
  send_count    smallint not null default 1,

  -- Salted hash only. Used for abuse correlation; never a raw IP at rest.
  ip_hash       text,
  consumed_at   timestamptz
);

-- One live registration per address. A re-request UPDATEs this row (new code,
-- new expiry) rather than accumulating rows, which is what keeps the table
-- ~zero-growth under a semester rush.
create unique index if not exists pending_registrations_live_email_idx
  on pending_registrations (email_norm) where consumed_at is null;
create index if not exists pending_registrations_expiry_idx
  on pending_registrations (expires_at);
create index if not exists pending_registrations_token_idx
  on pending_registrations (token_hash) where consumed_at is null;

-- Service role only. No policies are defined on purpose: with RLS enabled and
-- zero policies, only service_role (which bypasses RLS) can read or write —
-- i.e. only the edge functions. anon/authenticated get nothing.
alter table pending_registrations enable row level security;
revoke all on pending_registrations from public, anon, authenticated;

comment on table pending_registrations is
  'Signup payloads held while the DIU mailbox is unproven. The auth user is created only on redemption. Service-role only.';

-- ---------------------------------------------------------------------------
-- 1b. Staged password resets
-- ---------------------------------------------------------------------------
-- A SEPARATE table rather than a `purpose` column on pending_registrations,
-- deliberately. register-verify looks a row up by email_norm; if a reset row
-- could live in that table it would be matched by the registration path and
-- fed to admin.createUser. The two flows are mutually exclusive in principle
-- (you cannot register an address that has an account, or reset one that does
-- not) but relying on that invariant to keep two different payload shapes
-- apart in one table is exactly the kind of coupling that breaks quietly later.
--
-- WHAT THIS REPLACES. Reset currently goes through
-- auth.resetPasswordForEmail, which means Supabase's capped built-in mailer
-- AND a link-only, GET-consumed token. University mail runs link scanners that
-- fetch every URL in a message, so a single-use recovery link is routinely
-- burned before the student clicks it — they see "link expired" on the first
-- try. A typed code is immune, and the link here is only spent by an explicit
-- POST from the app.
create table if not exists pending_password_resets (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references auth.users(id) on delete cascade,
  email         text not null,
  email_norm    text generated always as (lower(btrim(email))) stored,
  code_hash     text not null,
  token_hash    text not null,
  attempts      smallint not null default 0,
  max_attempts  smallint not null default 5,
  expires_at    timestamptz not null,
  created_at    timestamptz not null default now(),
  last_sent_at  timestamptz,
  ip_hash       text,
  consumed_at   timestamptz
);

create unique index if not exists pending_password_resets_live_email_idx
  on pending_password_resets (email_norm) where consumed_at is null;
create index if not exists pending_password_resets_token_idx
  on pending_password_resets (token_hash) where consumed_at is null;
create index if not exists pending_password_resets_expiry_idx
  on pending_password_resets (expires_at);

alter table pending_password_resets enable row level security;
revoke all on pending_password_resets from public, anon, authenticated;

comment on table pending_password_resets is
  'Password reset challenges. Code-first, with a prefetch-safe link. Replaces auth.resetPasswordForEmail, which is both mail-quota bound and burned by university link scanners. Service-role only.';

-- ---------------------------------------------------------------------------
-- 2. Email outbox — the overflow lane
-- ---------------------------------------------------------------------------
-- NOT the normal path. register-request sends inline and returns (~1s). This
-- table only catches what the provider budget could not take this second, so a
-- burst degrades into a short queue instead of a failed signup. See the
-- two-lane dispatch note in the plan.
create table if not exists email_outbox (
  id            bigint generated always as identity primary key,
  to_email      text not null,
  template      text not null,
  payload       jsonb not null default '{}'::jsonb,

  -- hash(email + purpose + time-bucket). Five rage-taps on "Resend" collapse
  -- to ONE queued mail instead of five. This is the cheapest volume cut we
  -- have, and it costs a unique index.
  dedupe_key    text,

  priority      smallint not null default 5,  -- 1 = highest
  state         text not null default 'queued'
                  check (state in ('queued','sending','sent','failed','dropped')),
  attempts      smallint not null default 0,
  max_attempts  smallint not null default 6,

  provider            text,
  provider_message_id text,
  last_error          text,

  created_at    timestamptz not null default now(),
  send_after    timestamptz not null default now(),  -- exponential backoff
  sent_at       timestamptz
);

create unique index if not exists email_outbox_dedupe_idx
  on email_outbox (dedupe_key) where state in ('queued','sending');
create index if not exists email_outbox_drain_idx
  on email_outbox (priority, send_after) where state = 'queued';

alter table email_outbox enable row level security;
revoke all on email_outbox from public, anon, authenticated;

comment on table email_outbox is
  'Overflow lane for transactional mail. The hot path sends inline; this catches provider-budget overflow so a rush degrades into a queue rather than a failure.';

-- ---------------------------------------------------------------------------
-- 3. Rate limits — reuse the existing token bucket, add no new machinery
-- ---------------------------------------------------------------------------
-- consume_rate_limit(bucket, key, cost) already exists
-- (20260725080021_sec_token_bucket_rate_limiting.sql) and its own header notes
-- that edge functions may call it keyed by caller IP. These are new policy
-- rows, not new infrastructure.
--
-- Without these, the mail quota IS the denial-of-service surface: an attacker
-- loops registration for one address and both burns the provider budget and
-- mail-bombs a real student.
insert into rate_limit_policies (bucket, capacity, refill_per_minute, description) values
  ('email_verify_addr',      3,   0.05, 'Verification/reset mails per address (burst 3, ~1 per 20 min sustained)'),
  ('email_verify_ip',        10,  0.5,  'Verification/reset mails per client IP'),
  ('email_verify_attempt',   8,   0.25, 'Code redemption attempts per address — blunts online brute force'),
  ('email_provider_resend',  100, 100,  'Resend inline dispatch budget per minute; overflow diverts to email_outbox')
on conflict (bucket) do nothing;

-- ---------------------------------------------------------------------------
-- 4. Approval policy as data, not code
-- ---------------------------------------------------------------------------
-- Owner decision 2026-08-16: auto-approve every account whose mailbox is
-- proven. Recorded as a config row rather than hardcoded so tightening
-- teacher/staff back to manual review is a one-row UPDATE, not a migration and
-- a redeploy.
--
-- Standing caveat, deliberately left in the schema: a proven @diu.edu.bd
-- mailbox demonstrates the person controls a DIU address. It does NOT
-- demonstrate they are faculty. Narrowing this array is the lever if a fake
-- teacher account ever appears.
alter table app_config
  add column if not exists auto_approve_roles text[] not null
    default array['student','teacher','staff'];
alter table app_config
  add column if not exists registration_open boolean not null default true;

comment on column app_config.auto_approve_roles is
  'Roles auto-approved once the mailbox is proven. Remove teacher/staff to send those back to manual review.';

-- ---------------------------------------------------------------------------
-- 4b. Atomic batch claim for the drain worker
-- ---------------------------------------------------------------------------
-- FOR UPDATE SKIP LOCKED is the whole point: two workers (or a cron tick that
-- overlaps a slow previous tick) must never claim the same row and send the
-- same code twice. A plain "select then update" from the edge function cannot
-- express this and would double-send under exactly the burst conditions the
-- outbox exists to handle.
create or replace function public.claim_email_batch(p_limit int default 20)
returns setof email_outbox
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  return query
  update email_outbox o
     set state = 'sending',
         attempts = o.attempts + 1
   where o.id in (
     select id from email_outbox
      where state = 'queued' and send_after <= now()
      order by priority, send_after
      limit greatest(1, least(p_limit, 100))
      for update skip locked
   )
  returning o.*;
end;
$$;

revoke all on function public.claim_email_batch(int) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 5. Housekeeping — answers the storage concern directly
-- ---------------------------------------------------------------------------
-- Steady-state footprint is near zero: codes die in 15 minutes, delivered mail
-- rows in 24 hours. Even a 25,000-signup rush leaves only the in-flight window
-- on disk.
create or replace function public.purge_identity_ephemera()
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  delete from pending_registrations
   where consumed_at is not null and consumed_at < now() - interval '1 hour';
  delete from pending_registrations
   where consumed_at is null and expires_at < now() - interval '24 hours';
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

-- Scheduled separately once applied:
--   select cron.schedule('purge-identity-ephemera', '*/15 * * * *',
--                        $$select public.purge_identity_ephemera()$$);
--   select cron.schedule('drain-email-outbox', '* * * * *', <pg_net call to the drain fn>);

-- ---------------------------------------------------------------------------
-- 6. Closing the original hole
-- ---------------------------------------------------------------------------
-- Deliberately NOT dropped in this file, because dropping it without the
-- dashboard toggle below would leave the door open rather than close it:
--
--   drop trigger if exists auto_confirm_email_trigger on auth.users;
--
-- Sequence that must be honoured, or there is a window where BOTH gates are
-- down:
--   1. Ship the edge functions + client so registration no longer calls
--      auth.signUp.
--   2. Turn ON "Confirm email" in Supabase Auth settings (dashboard — only the
--      project owner can do this; the MCP server cannot).
--   3. THEN drop auto_confirm_email_trigger.
--
-- After that a raw auth.signUp leaves an unconfirmed user who cannot obtain a
-- session, while register-verify creates its users pre-confirmed through the
-- admin API and is unaffected. enforce_email_domain stays exactly as it is —
-- it remains a useful cheap first filter.
