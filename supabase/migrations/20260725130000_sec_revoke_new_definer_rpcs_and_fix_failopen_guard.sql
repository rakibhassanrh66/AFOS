-- =====================================================================
--  AFOS — Close the SECURITY DEFINER ACL regression introduced after SEC-1.
--
--  20260721194633 and 20260721200547 audited every definer RPC and revoked
--  EXECUTE from PUBLIC (correctly starting at PUBLIC rather than `anon`,
--  since a PUBLIC grant reaches anon regardless). Its closing note asked
--  that new definer functions not be widened back without redoing that
--  audit -- but two functions created three days later were never revoked:
--
--    list_my_permissions(uuid)  -- 20260724135546
--    approve_course_join(uuid)  -- 20260724143839
--
--  Both currently carry `=X/postgres` (PUBLIC) and an explicit `anon=X`,
--  i.e. they are callable by an unauthenticated client via /rest/v1/rpc/.
--
--  approve_course_join is saved by its own `auth.uid() is null` raise, so
--  the revoke below is defence in depth. list_my_permissions is NOT:
--
--      if p_user_id <> auth.uid() and get_my_profile_role() <> 'super_admin'
--
--  For an anon caller auth.uid() is NULL, so `p_user_id <> NULL` evaluates
--  to NULL, `NULL and ...` is NULL, and the IF does not fire -- the guard
--  is skipped entirely. This is the exact three-valued-logic fail-open that
--  20260721200547:70-76 was written to repair on the club RPCs; it simply
--  reappeared in a function written afterwards. It happens not to leak
--  today only because the body then filters on `pr.id = NULL`, which
--  matches nothing -- correct behaviour by accident, not by construction.
--
--  Fixed here by testing auth.uid() explicitly first and using IS DISTINCT
--  FROM (null-safe) for the comparison, so the guard fires on every path.
--  Also pins pg_temp alongside public in search_path, matching the more
--  defensive form used by the rest of the definer functions.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.list_my_permissions(p_user_id uuid DEFAULT auth.uid())
RETURNS TABLE(resource text, action text, scope text)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  -- Explicit null test first: without it every comparison below collapses
  -- to NULL for an anon caller and the authorization check is skipped.
  if auth.uid() is null then
    raise exception 'Not authorized' using errcode = '42501';
  end if;
  -- IS DISTINCT FROM, not <>: null-safe, so an explicitly-passed NULL
  -- p_user_id is treated as "not me" and rejected rather than slipping
  -- through as an unknown.
  if p_user_id is distinct from auth.uid()
     and coalesce(get_my_profile_role(), '') <> 'super_admin' then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  return query
  select distinct p.resource, p.action, p.scope
  from permissions p
  where exists (
    select 1 from role_permissions rp
    join profiles pr on pr.role_id = rp.role_id
    where pr.id = p_user_id and rp.permission_id = p.id
  ) or exists (
    select 1 from user_permissions up
    where up.user_id = p_user_id and up.permission_id = p.id
  );
end;
$function$;

-- Revoke from PUBLIC first (that grant is what actually reaches anon), then
-- from anon explicitly since both functions also carry a direct anon grant.
-- authenticated keeps EXECUTE: both are legitimately called by the app.
REVOKE ALL ON FUNCTION public.list_my_permissions(uuid) FROM public, anon;
REVOKE ALL ON FUNCTION public.approve_course_join(uuid) FROM public, anon;

GRANT EXECUTE ON FUNCTION public.list_my_permissions(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.approve_course_join(uuid) TO authenticated;
