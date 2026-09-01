-- Know the mail is about to run out BEFORE a student is told to check an inbox.
--
-- WHY. The provider has a DAILY ceiling (Resend's free plan is ~100/day) and
-- this system had no idea it existed. `email_provider_resend` caps the INLINE
-- burst at 100 per MINUTE — roughly 1,400x the provider's real daily
-- allowance — so the app would keep sending confidently while the provider
-- started refusing, and every refusal past the cap would look to a student
-- exactly like the bug we just spent a night diagnosing: fill in the form, get
-- told to check your email, and nothing ever arrives.
--
-- The failure this project actually had was worse than slow: it was SILENT. It
-- ran from 2026-08-17 (the date in register-request's own comment) to
-- 2026-09-01 with nobody knowing, because nothing anywhere reports that mail
-- did not go out. Capacity that fails quietly is the problem; this makes it
-- announce itself.
--
-- THREE PIECES:
--   1. a daily budget, separate from the per-minute burst budget
--   2. a way to ASK how much is left without spending any of it
--   3. an alert to the people who can act, fired once per threshold crossing
--      rather than on every send

-- ---------------------------------------------------------------------------
-- 1. The daily budget.
-- ---------------------------------------------------------------------------
-- Capacity is the plan's daily allowance. Refill is capacity/1440 per minute,
-- which spreads a day's allowance evenly instead of resetting at a fixed hour:
-- a rolling window degrades gently, where a midnight reset means a burst at
-- 23:50 leaves the next ten minutes dead for no reason a user could understand.
--
-- CHANGE `capacity` WHEN THE PLAN CHANGES. That is the single number that has
-- to match reality, and it lives in a row precisely so upgrading the Resend
-- plan is an UPDATE and not a deploy:
--   update rate_limit_policies
--      set capacity = 50000, refill_per_minute = 50000/1440.0
--    where bucket = 'email_provider_resend_daily';
INSERT INTO rate_limit_policies (bucket, capacity, refill_per_minute, enabled, description)
VALUES (
  'email_provider_resend_daily',
  100,
  100 / 1440.0,
  true,
  'Provider DAILY allowance (Resend free = 100/day). Rolling 24h refill. '
  'Raise capacity AND refill_per_minute together when the plan changes.'
)
ON CONFLICT (bucket) DO UPDATE
  SET description = EXCLUDED.description;

-- ---------------------------------------------------------------------------
-- 2. Peek, without spending.
-- ---------------------------------------------------------------------------
-- consume_rate_limit() takes a token to tell you anything, which is useless for
-- "are we about to run out?" — asking the question would itself consume the
-- last of the answer. This applies the same refill maths read-only.
--
-- Returns tokens remaining, capacity, and the fraction left, so a caller can
-- decide between "send normally", "send and warn" and "do not send at all"
-- without hardcoding the plan size.
CREATE OR REPLACE FUNCTION public.mail_budget_status()
RETURNS TABLE (remaining numeric, capacity numeric, fraction numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_capacity numeric;
  v_refill   numeric;
  v_enabled  boolean;
  v_tokens   numeric;
  v_updated  timestamptz;
BEGIN
  SELECT p.capacity, p.refill_per_minute, p.enabled
    INTO v_capacity, v_refill, v_enabled
  FROM rate_limit_policies p WHERE p.bucket = 'email_provider_resend_daily';

  -- No policy, or disabled: report unlimited rather than pretending it is
  -- empty. A missing row must never be read as "stop sending".
  IF v_capacity IS NULL OR NOT v_enabled THEN
    RETURN QUERY SELECT 999999::numeric, 999999::numeric, 1.0::numeric;
    RETURN;
  END IF;

  SELECT b.tokens, b.updated_at INTO v_tokens, v_updated
  FROM rate_limit_buckets b
  WHERE b.bucket = 'email_provider_resend_daily' AND b.key = 'global';

  -- Never used today => full.
  IF v_tokens IS NULL THEN
    RETURN QUERY SELECT v_capacity, v_capacity, 1.0::numeric;
    RETURN;
  END IF;

  v_tokens := LEAST(
    v_capacity,
    v_tokens + (EXTRACT(epoch FROM (now() - v_updated)) / 60.0) * v_refill
  );
  v_tokens := GREATEST(v_tokens, 0);

  RETURN QUERY SELECT v_tokens, v_capacity,
                      CASE WHEN v_capacity = 0 THEN 0::numeric
                           ELSE v_tokens / v_capacity END;
END;
$$;

REVOKE ALL ON FUNCTION public.mail_budget_status() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mail_budget_status() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. Tell the people who can act.
-- ---------------------------------------------------------------------------
-- One row per threshold crossing, so the alert can be fired from the send path
-- without notifying anyone twice for the same exhaustion event.
CREATE TABLE IF NOT EXISTS mail_capacity_alerts (
  id          bigint generated always as identity primary key,
  threshold   text not null check (threshold in ('low','exhausted')),
  remaining   numeric not null,
  capacity    numeric not null,
  raised_at   timestamptz not null default now()
);

-- At most one alert per threshold per hour. Without this, a registration burst
-- would send an admin one push per applicant at the exact moment they most
-- need a single clear signal.
--
-- `AT TIME ZONE 'UTC'` is not decoration: date_trunc() on a timestamptz is only
-- STABLE, because its answer depends on the session's TimeZone setting, and
-- Postgres refuses a non-IMMUTABLE expression in an index. Pinning the zone
-- converts to a plain timestamp first, which is immutable — and UTC rather than
-- local so the hour boundary cannot move under a client that connects with a
-- different TimeZone.
CREATE UNIQUE INDEX IF NOT EXISTS mail_capacity_alerts_once_idx
  ON mail_capacity_alerts (threshold, date_trunc('hour', raised_at AT TIME ZONE 'UTC'));

ALTER TABLE mail_capacity_alerts ENABLE ROW LEVEL SECURITY;

CREATE POLICY mail_capacity_alerts_admin_read ON mail_capacity_alerts
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM profiles p
                  WHERE p.id = auth.uid() AND p.role = 'super_admin'));

-- Raises an alert if the budget has crossed a threshold, and returns whether
-- mail should still be attempted at all.
--
-- Deliberately does BOTH: the caller needs one answer ("can I send?") and the
-- alert must not depend on the caller remembering to raise it. Separating them
-- is how the previous outage stayed invisible.
CREATE OR REPLACE FUNCTION public.mail_check_and_alert()
RETURNS TABLE (can_send boolean, remaining numeric, capacity numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_rem  numeric;
  v_cap  numeric;
  v_frac numeric;
  v_level text;
BEGIN
  SELECT s.remaining, s.capacity, s.fraction INTO v_rem, v_cap, v_frac
  FROM mail_budget_status() s;

  -- Below 1 whole message: nothing can be sent, full stop.
  -- Below 15%: still sending, but someone should be looking at the plan.
  v_level := CASE
    WHEN v_rem < 1   THEN 'exhausted'
    WHEN v_frac<0.15 THEN 'low'
    ELSE NULL
  END;

  IF v_level IS NOT NULL THEN
    BEGIN
      INSERT INTO mail_capacity_alerts (threshold, remaining, capacity)
      VALUES (v_level, v_rem, v_cap);

      -- Everyone who can actually do something about it: a super_admin can
      -- both approve the stranded applicant and upgrade the plan.
      INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
      SELECT p.id,
             CASE WHEN v_level = 'exhausted'
                  THEN 'Email sending has stopped — approvals need you'
                  ELSE 'Email quota running low' END,
             CASE WHEN v_level = 'exhausted'
                  THEN 'The mail provider''s daily allowance is spent, so new '
                    || 'sign-ups cannot receive a verification code. They are '
                    || 'being staged for manual approval instead — please review '
                    || 'them. Raising the plan restores automatic sending.'
                  ELSE 'Only ' || round(v_rem)::text || ' of ' || round(v_cap)::text
                    || ' emails remain for today. New sign-ups will switch to '
                    || 'manual approval when it runs out.' END,
             'system',
             '/admin/users'
      FROM profiles p WHERE p.role = 'super_admin';
    EXCEPTION WHEN unique_violation THEN
      -- Already raised this hour. Not an error: exactly the intended behaviour.
      NULL;
    END;
  END IF;

  RETURN QUERY SELECT (v_rem >= 1), v_rem, v_cap;
END;
$$;

REVOKE ALL ON FUNCTION public.mail_check_and_alert() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mail_check_and_alert() TO service_role;
