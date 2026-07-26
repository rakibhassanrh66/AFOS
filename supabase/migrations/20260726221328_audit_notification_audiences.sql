-- Standing assertion that a notification's in-app audience and its push
-- audience cannot drift apart.
--
-- WHY THIS CHECK EXISTS. Every notification in this app is written twice: a
-- trigger inserts the durable user_notifications row, and the client sends the
-- OneSignal banner, because a trigger cannot reach OneSignal (pg_net is not
-- installed and the REST key lives in the edge function's environment). Two
-- implementations of one rule is precisely the shape that rots, and it already
-- did, twice, undetected:
--
--   * offering submitted -- the trigger scoped dept_admin to the offering's
--     department; the client pushed to EVERY dept_admin in the university.
--   * results submitted -- the trigger included a scoped dept_admin; the
--     client omitted dept_admin from the push entirely.
--
-- Neither was visible on this project because it has no dept_admin, so a test
-- that counted recipients passed while the rule was wrong. Counting is not
-- enough; the two sides have to be the SAME definition.
--
-- The rule enforced here is structural rather than behavioural, which is what
-- makes it cheap and reliable: a trigger that writes user_notifications must
-- not carry its own hardcoded role membership test. If it needs a role-based
-- audience it must call one of the shared audience functions, which the client
-- also calls over RPC -- so both sides resolve through one definition and
-- cannot disagree.
--
-- Single-recipient triggers (tell this student, tell this teacher) are fine and
-- are not flagged: they have no role list to drift.
--
-- Proven to actually catch it: reintroducing a hardcoded role list into
-- notify_offering_submitted made this return 2 rows; restoring the shared
-- audience returned it to 0. Run in CI by
-- .github/scripts/check_notification_audiences.py.

CREATE OR REPLACE FUNCTION audit_notification_audiences()
RETURNS TABLE(function_name text, problem text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
  WITH notif_triggers AS (
    SELECT DISTINCT p.proname::text AS fname, pg_get_functiondef(p.oid) AS def
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace AND n.nspname = 'public'
    JOIN pg_trigger t ON t.tgfoid = p.oid AND NOT t.tgisinternal
    WHERE pg_get_functiondef(p.oid) ILIKE '%insert into user_notifications%'
  )
  SELECT fname,
         'writes user_notifications using its own hardcoded role list; use a '
         'shared audience function (offering_reviewer_audience / '
         'offering_section_audience) so the push resolves the same set'
  FROM notif_triggers
  WHERE def ~* 'role\s+IN\s*\('
     OR def ~* 'role\s*=\s*ANY'

  UNION ALL

  SELECT fname,
         'must call offering_reviewer_audience() so the client push targets the '
         'identical set of reviewers'
  FROM notif_triggers
  WHERE fname IN ('notify_offering_submitted', 'notify_results_submitted')
    AND def NOT ILIKE '%offering_reviewer_audience%'

  UNION ALL

  SELECT fname,
         'must call offering_section_audience() so the client push targets the '
         'identical batch/section'
  FROM notif_triggers
  WHERE fname = 'notify_offering_approved'
    AND def NOT ILIKE '%offering_section_audience%';
$fn$;

REVOKE ALL ON FUNCTION audit_notification_audiences() FROM public, anon;
GRANT EXECUTE ON FUNCTION audit_notification_audiences() TO authenticated, service_role;
