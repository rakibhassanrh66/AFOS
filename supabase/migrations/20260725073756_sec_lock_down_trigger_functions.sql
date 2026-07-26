-- =====================================================================
--  AFOS — Trigger functions should not be callable as RPCs.
--
--  Every function in `public` that RETURNS trigger currently carries the
--  Postgres default `PUBLIC EXECUTE` plus explicit anon/authenticated
--  grants, which means each is reachable at /rest/v1/rpc/<name>. That is
--  what the database linter flags as
--  anon_security_definer_function_executable, and it covers 14 functions
--  including handle_new_user, protect_profile_privileged_columns,
--  enforce_email_domain and two added by this session's curriculum work
--  (set_offering_default_term, sync_profile_batch_section).
--
--  Calling them over REST does not actually achieve much -- a trigger
--  function invoked outside a trigger has no NEW/OLD record and errors out
--  -- so this is hardening rather than an open hole. But it is free: a
--  trigger is fired by the trigger mechanism, which does NOT consult
--  EXECUTE privilege on the function (that is checked once, at CREATE
--  TRIGGER time), so revoking cannot break any trigger.
--
--  Generated from pg_proc rather than hand-listed, matching the approach
--  20260724183115/20260724183320 used for the RLS and FK-index sweeps --
--  so functions added later are covered by re-running this, and nothing
--  is missed by a typo.
--
--  Also pins search_path on the three trigger functions still missing it
--  (calculate_grade, prevent_published_marks_edit, update_updated_at_column).
--  These are not SECURITY DEFINER so the risk is lower than the cases
--  20260703060000/20260713190000 fixed, but an unpinned search_path in a
--  trigger is still resolved against the *caller's* path.
-- =====================================================================

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND pg_get_function_result(p.oid) = 'trigger'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM public, anon, authenticated', r.sig);
  END LOOP;
END $$;

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND pg_get_function_result(p.oid) = 'trigger'
      AND (p.proconfig IS NULL
           OR NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%'))
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', r.sig);
  END LOOP;
END $$;
