-- =====================================================================
--  AFOS — Standing check against SECURITY DEFINER ACL drift.
--
--  WHY THIS EXISTS. "SECURITY DEFINER function is executable by anon" has
--  now regressed three times: 20260721194633 fixed a batch, 20260721200547
--  fixed the ones that came back plus a fail-open guard, and
--  20260725071319 caught list_my_permissions/approve_course_join, which had
--  shipped days earlier with no REVOKE at all. The pattern is structural,
--  not careless: CREATE FUNCTION grants EXECUTE to PUBLIC by default, so a
--  new definer RPC is exposed to anon unless the author remembers to revoke
--  it. Review has repeatedly failed to catch that; a check will not.
--
--  This exposes the check as an RPC so CI can call it over PostgREST with
--  the service-role key it already holds, without needing raw SQL access.
--  Consumed by .github/scripts/check_definer_acls.py from the db_security
--  job in .github/workflows/main.yml.
-- =====================================================================

-- Event-trigger functions cannot be invoked directly (Postgres rejects
-- calling a function returning event_trigger), so this grant was inert --
-- but it made the audit below non-empty on day one, and an audit with a
-- known-noise entry is an audit people learn to ignore. Same reasoning as
-- 20260725141000 applied to row-trigger functions.
REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM public, anon, authenticated;

CREATE TABLE IF NOT EXISTS definer_acl_allowlist (
  function_signature text PRIMARY KEY,
  reason             text NOT NULL,
  added_at           timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE definer_acl_allowlist ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON definer_acl_allowlist FROM public, anon, authenticated;

INSERT INTO definer_acl_allowlist (function_signature, reason) VALUES
  ('get_my_profile_role()',
   'Referenced by RLS policies on many tables, which are evaluated for anon '
   'queries too -- revoking anon EXECUTE would make those policies error '
   'instead of simply returning no rows. Returns only the CALLER''S own role '
   '(NULL for anon), so it discloses nothing about anyone else.')
ON CONFLICT (function_signature) DO NOTHING;

-- Returns one row per SECURITY DEFINER function in `public` that anon can
-- execute and that is not explicitly allowlisted. Empty result = healthy.
CREATE OR REPLACE FUNCTION public.audit_definer_acls()
RETURNS TABLE (function_signature text, relies_on_default_public_grant boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $$
  SELECT sig, proacl IS NULL
  FROM (
    SELECT p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
           p.proacl,
           p.oid
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
  ) f
  WHERE sig NOT IN (SELECT function_signature FROM definer_acl_allowlist)
  ORDER BY sig;
$$;

REVOKE ALL ON FUNCTION public.audit_definer_acls() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_definer_acls() TO service_role;

NOTIFY pgrst, 'reload schema';
