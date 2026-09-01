-- Warn at the 99th mail, not at some fraction — and warn everyone who can act.
--
-- Two corrections to 20260902070000, both from the owner's own spec:
--
--  1. THRESHOLDS. The first version warned at 15% remaining and again at zero.
--     What was actually asked for is a warning at the 99th send — the moment
--     ONE message is left — because that is the last instant at which anything
--     can be done before the 101st applicant is turned away. 15% is still kept
--     as an earlier, gentler heads-up, since 15 remaining is when a plan
--     upgrade can still be arranged calmly rather than at midnight.
--
--       low        <= 15 left   "arrange an upgrade"
--       last_one   == 1 left    "the next sign-up will NOT get a code"
--       exhausted  <  1 left    manual approval is now the only path
--
--  2. AUDIENCE. It notified `role = 'super_admin'` only — one account. But the
--     permission model already answers "who can act on a stranded applicant":
--     it is whoever holds `users:approve`, whether that came from their role or
--     from an individual grant a super_admin delegated. Hardcoding the role
--     would silently exclude exactly the person deliberately assigned to watch
--     approvals, which is the case this feature exists for.

CREATE OR REPLACE FUNCTION public.mail_check_and_alert()
RETURNS TABLE (can_send boolean, remaining numeric, capacity numeric)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_rem   numeric;
  v_cap   numeric;
  v_frac  numeric;
  v_level text;
  v_title text;
  v_body  text;
BEGIN
  SELECT s.remaining, s.capacity, s.fraction INTO v_rem, v_cap, v_frac
  FROM mail_budget_status() s;

  -- Ordered most-severe first: at 0 left both 'exhausted' and 'low' are true,
  -- and the one that matters is the one that stops sending.
  v_level := CASE
    WHEN v_rem < 1              THEN 'exhausted'
    WHEN v_rem < 2              THEN 'last_one'
    WHEN v_frac < 0.15          THEN 'low'
    ELSE NULL
  END;

  IF v_level IS NOT NULL THEN
    SELECT
      CASE v_level
        WHEN 'exhausted' THEN 'Email sending has stopped — approvals need you'
        WHEN 'last_one'  THEN 'One email left today — the next sign-up gets none'
        ELSE                  'Email quota running low'
      END,
      CASE v_level
        WHEN 'exhausted' THEN
          'Today''s email allowance is spent, so new sign-ups cannot receive a '
          || 'verification code. They are being staged for manual approval '
          || 'instead — please review them. Raising the mail plan restores '
          || 'automatic sending immediately.'
        WHEN 'last_one' THEN
          'Only 1 of ' || round(v_cap)::text || ' emails remains for today. '
          || 'The next person who signs up will not get a code and will be sent '
          || 'to manual approval. Raise the mail plan now to avoid that.'
        ELSE
          round(v_rem)::text || ' of ' || round(v_cap)::text || ' emails remain '
          || 'for today. New sign-ups switch to manual approval when it runs out.'
      END
    INTO v_title, v_body;

    BEGIN
      INSERT INTO mail_capacity_alerts (threshold, remaining, capacity)
      VALUES (v_level, v_rem, v_cap);

      -- Everyone who can actually clear a stranded applicant: super_admins,
      -- plus any account holding users:approve by role or by direct grant.
      -- DISTINCT because a super_admin usually holds it both ways.
      INSERT INTO user_notifications (user_id, title, body, category, deep_link_route)
      SELECT DISTINCT p.id, v_title, v_body, 'system', '/admin/users'
      FROM profiles p
      WHERE p.role = 'super_admin'
         OR EXISTS (
              SELECT 1 FROM user_permissions up
                JOIN permissions perm ON perm.id = up.permission_id
               WHERE up.user_id = p.id
                 AND perm.resource = 'users' AND perm.action = 'approve')
         OR EXISTS (
              SELECT 1 FROM roles r
                JOIN role_permissions rp ON rp.role_id = r.id
                JOIN permissions perm ON perm.id = rp.permission_id
               WHERE r.name = p.role
                 AND perm.resource = 'users' AND perm.action = 'approve');
    EXCEPTION WHEN unique_violation THEN
      -- Already raised this level this hour. Intended: a registration burst
      -- must produce one clear signal, not one push per applicant.
      NULL;
    END;
  END IF;

  RETURN QUERY SELECT (v_rem >= 1), v_rem, v_cap;
END;
$$;

REVOKE ALL ON FUNCTION public.mail_check_and_alert() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.mail_check_and_alert() TO service_role;

ALTER TABLE mail_capacity_alerts DROP CONSTRAINT IF EXISTS mail_capacity_alerts_threshold_check;
ALTER TABLE mail_capacity_alerts
  ADD CONSTRAINT mail_capacity_alerts_threshold_check
  CHECK (threshold IN ('low','last_one','exhausted'));
