-- Registration proved the FORMAT of a @diu.edu.bd address, never CONTROL of
-- the mailbox. Measured on this project 2026-08-16: all 12 auth.users rows
-- carried conf_mail_sent = false, confirmed = true — not one verification mail
-- had ever been sent, because auto_confirm_email stamped email_confirmed_at on
-- every insert. Anyone who knew DIU's address pattern could register as a
-- student they had never met, and management adjudicated identity with no
-- evidence attached.
--
-- This adds the staging + delivery substrate so a signup proves mailbox
-- control BEFORE an auth user exists, and stops the trigger inventing
-- confirmations. See db/proposed/003 for the long-form rationale.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Staged registrations. Deliberately NOT a profile row: nothing unproven
-- touches the real tables.
-- ---------------------------------------------------------------------------
create table if not exists pending_registrations (
  id            uuid primary key default gen_random_uuid(),
  email         text not null,
  email_norm    text generated always as (lower(btrim(email))) stored,
  -- The signUp metadata verbatim, replayed into admin.createUser's
  -- user_metadata on redemption so handle_new_user() builds the profile
  -- exactly as it does today. That trigger is NOT modified.
  payload       jsonb not null,
  -- Never the code itself: HMAC with a pepper held only in the edge function
  -- env, so a database leak alone yields nothing usable.
  code_hash     text not null,
  token_hash    text not null,
  attempts      smallint not null default 0,
  max_attempts  smallint not null default 5,
  expires_at    timestamptz not null,
  created_at    timestamptz not null default now(),
  last_sent_at  timestamptz,
  send_count    smallint not null default 1,
  ip_hash       text,
  consumed_at   timestamptz,

  -- THE MANUAL FALLBACK.
  --
  -- The emailed code is the primary gate and settles the overwhelming
  -- majority: match it and the account is created and approved with no human
  -- involved. Admin approval is the SECONDARY path, for the person the code
  -- failed — mail never arrived, it expired while they were in a lecture, they
  -- burned all five attempts on a typo.
  --
  -- Without this the failure mode was silent: a stuck signup sat in this
  -- service-role-only table where no admin could see it, and the person had no
  -- route forward except registering again and hoping. Now an exhausted or
  -- expired attempt raises its hand.
  review_state  text not null default 'none'
                  check (review_state in ('none','needs_review','approved','rejected')),
  review_reason text,
  reviewed_by   uuid references auth.users(id) on delete set null,
  reviewed_at   timestamptz
);

create index if not exists pending_registrations_review_idx
  on pending_registrations (review_state, created_at desc)
  where review_state = 'needs_review';

-- One live registration per address: a re-request UPDATEs rather than
-- accumulating, which keeps this table near-zero-growth during a rush.
create unique index if not exists pending_registrations_live_email_idx
  on pending_registrations (email_norm) where consumed_at is null;
create index if not exists pending_registrations_expiry_idx
  on pending_registrations (expires_at);
create index if not exists pending_registrations_token_idx
  on pending_registrations (token_hash) where consumed_at is null;

-- RLS on with ZERO policies: only service_role (which bypasses RLS) can reach
-- these, i.e. only the edge functions. anon/authenticated get nothing.
alter table pending_registrations enable row level security;
revoke all on pending_registrations from public, anon, authenticated;

comment on table pending_registrations is
  'Signup payloads held while the DIU mailbox is unproven. The auth user is created only on redemption. Service-role only.';

-- ---------------------------------------------------------------------------
-- Staged password resets. A separate table, not a `purpose` column on the one
-- above: register-verify looks rows up by email_norm, and a reset row sharing
-- that table would be matched by the registration path and fed to
-- admin.createUser.
-- ---------------------------------------------------------------------------
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
  'Code-first password reset challenges with a prefetch-safe link. Replaces auth.resetPasswordForEmail, which is mail-quota bound and whose single-use link is burned by university mail scanners. Service-role only.';

-- ---------------------------------------------------------------------------
-- Overflow lane. NOT the normal path — the edge functions send inline and
-- return; this only catches what the per-minute provider budget could not take,
-- so a burst degrades into a short queue instead of a failed signup.
-- ---------------------------------------------------------------------------
create table if not exists email_outbox (
  id            bigint generated always as identity primary key,
  to_email      text not null,
  template      text not null,
  payload       jsonb not null default '{}'::jsonb,
  -- hash(email + purpose + time bucket): five rage-taps on Resend collapse to
  -- one queued mail. Cheapest volume cut available, costs one index.
  dedupe_key    text,
  priority      smallint not null default 5,
  state         text not null default 'queued'
                  check (state in ('queued','sending','sent','failed','dropped')),
  attempts      smallint not null default 0,
  max_attempts  smallint not null default 6,
  provider            text,
  provider_message_id text,
  last_error          text,
  created_at    timestamptz not null default now(),
  send_after    timestamptz not null default now(),
  sent_at       timestamptz
);

create unique index if not exists email_outbox_dedupe_idx
  on email_outbox (dedupe_key) where state in ('queued','sending');
create index if not exists email_outbox_drain_idx
  on email_outbox (priority, send_after) where state = 'queued';

alter table email_outbox enable row level security;
revoke all on email_outbox from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Rate limits: reuse the existing token bucket (20260725080021), add policy
-- rows only. Without these the mail quota IS the denial-of-service surface —
-- a loop on one address both burns the provider budget and mail-bombs a real
-- student.
-- ---------------------------------------------------------------------------
insert into rate_limit_policies (bucket, capacity, refill_per_minute, description) values
  ('email_verify_addr',      3,   0.05, 'Verification/reset mails per address (burst 3, ~1 per 20 min sustained)'),
  ('email_verify_ip',        10,  0.5,  'Verification/reset mails per client IP'),
  ('email_verify_attempt',   8,   0.25, 'Code redemption attempts per address — blunts online brute force'),
  ('email_provider_resend',  100, 100,  'Resend inline dispatch budget per minute; overflow diverts to email_outbox')
on conflict (bucket) do nothing;

-- ---------------------------------------------------------------------------
-- Approval policy as data, not code. Owner decision 2026-08-16: auto-approve
-- every account whose mailbox is proven. Kept configurable so tightening
-- teacher/staff back to manual review is a one-row UPDATE.
--
-- Standing caveat: a proven @diu.edu.bd mailbox shows the person controls a
-- DIU address. It does NOT show they are faculty.
-- ---------------------------------------------------------------------------
alter table app_config
  add column if not exists auto_approve_roles text[] not null
    default array['student','teacher','staff'];
alter table app_config
  add column if not exists registration_open boolean not null default true;

comment on column app_config.auto_approve_roles is
  'Roles auto-approved once the mailbox is proven. Remove teacher/staff to send those back to manual review.';

-- ---------------------------------------------------------------------------
-- Atomic batch claim for the drain worker. FOR UPDATE SKIP LOCKED is the whole
-- point: two workers, or a cron tick overlapping a slow previous tick, must
-- never claim the same row and send the same code twice.
-- ---------------------------------------------------------------------------
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
-- Housekeeping. Codes die in 15 minutes, delivered mail rows in 24 hours, so
-- even a 25,000-signup rush leaves only the in-flight window on disk.
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

-- ---------------------------------------------------------------------------
-- STOP INVENTING CONFIRMATIONS.
--
-- Before: email_confirmed_at := COALESCE(NEW.email_confirmed_at, now()), which
-- marked EVERY account confirmed the moment it was inserted. That single line
-- is why no verification mail has ever been sent and why the DIU address check
-- proved nothing about ownership.
--
-- After: the column is left exactly as the caller supplied it. Only
-- register-verify — which runs admin.createUser(email_confirm => true) after
-- matching the emailed code — produces a confirmed account. A raw auth.signUp
-- now yields an UNCONFIRMED user.
--
-- This deliberately does NOT raise an exception on unconfirmed inserts. That
-- stricter form is in the commented block below and is NOT enabled here,
-- because whether GoTrue stamps email_confirmed_at during the INSERT or in a
-- follow-up UPDATE decides whether it would also reject register-verify's own
-- user — and that has not been tested against this project. Enabling it
-- untested risks breaking registration outright. Rejecting nothing cannot.
--
-- The allowlist keeps its auto-confirm so a broken edge function can never
-- lock the owner out of their own project.
create or replace function public.auto_confirm_email()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $$
begin
  if new.email_confirmed_at is null
     and exists (select 1 from auth_email_domain_allowlist where email = new.email)
  then
    new.email_confirmed_at := now();
  end if;
  return new;
end;
$$;

-- REQUIRED NEXT STEP, DASHBOARD ONLY (no SQL and no API can do it):
--   Authentication → Providers → Email → turn ON "Confirm email".
--
-- Until that is on, an unconfirmed user can still obtain a session, so a
-- direct API call to auth.signUp still produces a usable account even though
-- the app no longer offers that path. With it on, an unconfirmed user cannot
-- sign in at all, and register-verify's accounts are unaffected because they
-- are created already confirmed.
--
-- OPTIONAL HARDENING, only after a real signup has been proven end-to-end:
--
--   create or replace function public.auto_confirm_email()
--   returns trigger language plpgsql security definer
--   set search_path to 'public','pg_temp' as $fn$
--   begin
--     if new.email_confirmed_at is not null then return new; end if;
--     if exists (select 1 from auth_email_domain_allowlist where email = new.email) then
--       new.email_confirmed_at := now(); return new;
--     end if;
--     raise exception 'Accounts must be created through the AFOS verification flow.'
--       using errcode = '42501';
--   end; $fn$;
--
-- Test BEFORE enabling that: register a throwaway @diu.edu.bd address, redeem
-- the code, and confirm the account is created. If it is, the strict version is
-- safe. If registration fails with 42501, GoTrue confirms in a second step and
-- the strict version must not be used.
