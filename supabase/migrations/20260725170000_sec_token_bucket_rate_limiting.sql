-- =====================================================================
--  AFOS — Server-side token-bucket rate limiting.
--
--  WHY IN THE DATABASE. This app has no backend of its own: clients talk
--  straight to PostgREST. Anything enforced in Dart is advisory, because a
--  session token plus curl bypasses it entirely. A trigger on the target
--  table is the only place a limit actually holds.
--
--  WHAT IS *NOT* HERE, DELIBERATELY. Login / signup / password-reset rate
--  limits are NOT reimplemented: GoTrue already rate-limits those per-IP
--  server-side, and its settings are configurable in the Supabase dashboard
--  (Authentication > Rate Limits). Rebuilding that here would sit *behind*
--  the thing doing the limiting and could only ever be weaker. Per-IP limits
--  in general are not expressible at this layer — PostgREST does not pass
--  the caller IP to Postgres — so buckets here are keyed per ACCOUNT, and
--  per-IP protection stays with GoTrue and the platform edge. Edge Functions
--  DO see the caller IP and can call consume_rate_limit() with it as the key.
--
--  Thresholds live in a table, not in code, so they can be tuned without a
--  deploy — the "make all thresholds configurable, not hardcoded" rule.
-- =====================================================================

-- ---------------------------------------------------------------
-- Policies: one row per named bucket. Tunable at runtime.
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rate_limit_policies (
  bucket            text PRIMARY KEY,
  capacity          numeric NOT NULL CHECK (capacity > 0),
  refill_per_minute numeric NOT NULL CHECK (refill_per_minute > 0),
  enabled           boolean NOT NULL DEFAULT true,
  description       text,
  updated_at        timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE rate_limit_policies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_manage_rate_limits" ON rate_limit_policies;
CREATE POLICY "admin_manage_rate_limits" ON rate_limit_policies
  FOR ALL USING (get_my_profile_role() = 'super_admin')
  WITH CHECK (get_my_profile_role() = 'super_admin');

-- ---------------------------------------------------------------
-- Buckets: live token counts. No RLS policies -> no direct access;
-- only the SECURITY DEFINER function below ever touches it.
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rate_limit_buckets (
  bucket     text NOT NULL,
  key        text NOT NULL,
  tokens     numeric NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (bucket, key)
);

ALTER TABLE rate_limit_buckets ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON rate_limit_buckets FROM public, anon, authenticated;

INSERT INTO rate_limit_policies (bucket, capacity, refill_per_minute, description) VALUES
  ('course_message',     20, 10,  'Messages per user in a course group'),
  ('enrollment_request', 10,  2,  'Course join requests per student'),
  ('course_offering',     8,  1,  'Offerings a teacher can submit'),
  ('sos_alert',           1,  0.2,'SOS alerts per user (~1 per 5 min)'),
  ('notification_send',  30, 10,  'Notification fan-outs per user')
ON CONFLICT (bucket) DO NOTHING;


-- ---------------------------------------------------------------
-- consume_rate_limit(bucket, key, cost) -> allowed?
-- ---------------------------------------------------------------
-- Classic token bucket: a bucket refills continuously at
-- refill_per_minute up to capacity, and each call costs `cost` tokens.
-- Capacity is therefore the burst allowance and refill is the sustained
-- rate, which is what makes this kinder than a hard lockout: a user who
-- trips it is throttled, and recovers on their own after a short wait
-- rather than being locked out for a fixed penalty window.
--
-- The refill/deduct is expressed as ONE `insert .. on conflict do update
-- .. where` so it is atomic under concurrency: two simultaneous calls
-- serialise on the row lock, and the second sees the first's deduction.
-- A read-then-write version would let both pass on an empty bucket.
--
-- Fails OPEN when no policy row exists: a missing configuration row must
-- not take a feature offline. Denials are the configured state, not the
-- accidental one.
CREATE OR REPLACE FUNCTION public.consume_rate_limit(
  p_bucket text,
  p_key    text DEFAULT NULL,
  p_cost   numeric DEFAULT 1
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_key      text := COALESCE(p_key, auth.uid()::text);
  v_capacity numeric;
  v_refill   numeric;
  v_enabled  boolean;
  v_ok       boolean;
BEGIN
  IF v_key IS NULL THEN
    -- No account and no explicit key: nothing to attribute usage to.
    RETURN false;
  END IF;

  SELECT capacity, refill_per_minute, enabled
    INTO v_capacity, v_refill, v_enabled
  FROM rate_limit_policies WHERE bucket = p_bucket;

  IF v_capacity IS NULL OR NOT v_enabled THEN
    RETURN true;
  END IF;

  INSERT INTO rate_limit_buckets AS b (bucket, key, tokens, updated_at)
  VALUES (p_bucket, v_key, v_capacity - p_cost, now())
  ON CONFLICT (bucket, key) DO UPDATE
    SET tokens = LEAST(
          v_capacity,
          b.tokens + (EXTRACT(epoch FROM (now() - b.updated_at)) / 60.0) * v_refill
        ) - p_cost,
        updated_at = now()
    WHERE LEAST(
          v_capacity,
          b.tokens + (EXTRACT(epoch FROM (now() - b.updated_at)) / 60.0) * v_refill
        ) >= p_cost
  RETURNING true INTO v_ok;

  -- No row returned => the WHERE above rejected the update => empty bucket.
  -- Note updated_at is intentionally NOT bumped on a denial, so a caller
  -- hammering the endpoint cannot keep resetting their own refill clock.
  RETURN COALESCE(v_ok, false);
END;
$$;

REVOKE ALL ON FUNCTION public.consume_rate_limit(text, text, numeric) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.consume_rate_limit(text, text, numeric) TO authenticated;


-- ---------------------------------------------------------------
-- Enforcement triggers
-- ---------------------------------------------------------------
-- Attached to the tables themselves rather than checked client-side, so
-- the limit holds for a direct PostgREST call too.
CREATE OR REPLACE FUNCTION public.enforce_rate_limit_course_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NOT consume_rate_limit('course_message') THEN
    RAISE EXCEPTION 'You are sending messages too quickly — wait a moment and try again.'
      USING errcode = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rate_limit_course_message ON course_messages;
CREATE TRIGGER trg_rate_limit_course_message
  BEFORE INSERT ON course_messages
  FOR EACH ROW EXECUTE FUNCTION public.enforce_rate_limit_course_message();

CREATE OR REPLACE FUNCTION public.enforce_rate_limit_enrollment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NOT consume_rate_limit('enrollment_request') THEN
    RAISE EXCEPTION 'Too many join requests in a short time — please wait a moment.'
      USING errcode = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rate_limit_enrollment ON enrollments;
CREATE TRIGGER trg_rate_limit_enrollment
  BEFORE INSERT ON enrollments
  FOR EACH ROW EXECUTE FUNCTION public.enforce_rate_limit_enrollment();

CREATE OR REPLACE FUNCTION public.enforce_rate_limit_offering()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NOT consume_rate_limit('course_offering') THEN
    RAISE EXCEPTION 'Too many offerings submitted in a short time — please wait a moment.'
      USING errcode = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rate_limit_offering ON course_offerings;
CREATE TRIGGER trg_rate_limit_offering
  BEFORE INSERT ON course_offerings
  FOR EACH ROW EXECUTE FUNCTION public.enforce_rate_limit_offering();

-- Trigger functions are never called as RPCs (see 20260725141000).
REVOKE ALL ON FUNCTION public.enforce_rate_limit_course_message() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_rate_limit_enrollment()     FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.enforce_rate_limit_offering()       FROM public, anon, authenticated;

-- Buckets for users who stopped hammering are dead weight; a full bucket
-- is indistinguishable from no row at all, so they can be dropped freely.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'prune-rate-limit-buckets') THEN
    PERFORM cron.unschedule('prune-rate-limit-buckets');
  END IF;
END $$;

SELECT cron.schedule('prune-rate-limit-buckets', '17 * * * *',
  $$DELETE FROM rate_limit_buckets WHERE updated_at < now() - interval '1 day'$$);

NOTIFY pgrst, 'reload schema';
