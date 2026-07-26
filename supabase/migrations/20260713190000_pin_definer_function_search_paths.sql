-- Security hardening: the last two SECURITY DEFINER functions without a
-- pinned search_path (live-audited via pg_proc.proconfig — every other
-- definer function already pins it).
--
-- enforce_email_domain is not just hardening but a latent-bug fix: it fires
-- on auth.users under supabase_auth_admin, whose restricted search_path
-- cannot resolve the unqualified auth_email_domain_allowlist reference —
-- the exact mechanism that broke handle_new_user() originally. DIU-domain
-- signups short-circuit before that lookup (which is why signups appear to
-- work), but any allowlisted non-DIU signup would 500 with "relation does
-- not exist" instead of consulting the allowlist.
--
-- handle_claim_accepted currently runs only via PostgREST contexts where
-- public is on the search_path, so pinning is pure defense-in-depth there.

alter function public.enforce_email_domain() set search_path = public, pg_temp;
alter function public.handle_claim_accepted() set search_path = public, pg_temp;
