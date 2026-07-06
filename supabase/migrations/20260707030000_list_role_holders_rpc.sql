-- Real gap found: every student/teacher SUBMISSION flow (hall application,
-- hall complaint, CR request, conference room request) never notified the
-- admin-tier roles who need to act on it — admins only found out by
-- manually checking the app. Client code notifying "everyone with role X"
-- can't use send-notification's broadcast mode (that's restricted to
-- admin/super_admin/dept_admin/teacher callers, not students), so this
-- narrow RPC resolves recipient ids for the (still 20-recipient-capped,
-- properly-authorized) direct sendToUsers path instead. Revealing which
-- profile ids hold a given role isn't sensitive on its own — the actual
-- notification send is still gated by send-notification's own auth.
CREATE OR REPLACE FUNCTION public.list_role_holders(p_roles text[])
RETURNS TABLE(profile_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY SELECT p.id FROM profiles p WHERE p.role = ANY(p_roles);
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_role_holders(text[]) TO authenticated;
