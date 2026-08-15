-- The audit trigger was callable by anyone, including anon.
--
-- APPLIED 2026-08-15. CI caught this, which is the whole reason that check
-- exists (.github/scripts/check_definer_acls.py):
--
--   SECURITY DEFINER functions are executable by `anon`:
--     log_permission_change() - explicitly granted
--
-- WHY IT MATTERS MORE THAN THE USUAL CASE. `log_permission_change` is the
-- trigger that writes permission_audit, and it is SECURITY DEFINER precisely so
-- it can write a table nobody may write directly. Left executable, an anonymous
-- caller could invoke it and FORGE audit rows -- entries claiming a permission
-- was granted or revoked when it never was. An audit log anyone can write to is
-- worse than no audit log, because it is believed.
--
-- A trigger function needs no EXECUTE grant at all: it runs as part of the
-- trigger, under the table owner, not as the caller. The grant was pure surface
-- area, inherited from CREATE FUNCTION's default of granting EXECUTE to PUBLIC.
--
-- Same reasoning and the same fix as 20260726135859_revoke_execute_on_trigger_functions.
-- This function was created after it and did not inherit the lesson, which is
-- an argument for the CI check over remembering.
revoke all on function public.log_permission_change() from public, anon, authenticated;

-- handle_claim_accepted was rewritten in the same batch. Already locked down,
-- but asserted rather than assumed: `create or replace` resets ACLs to the
-- default, and the default is exactly what caused the failure above.
revoke all on function public.handle_claim_accepted() from public, anon, authenticated;

-- VERIFIED after applying:
--   * the only SECURITY DEFINER function anon may execute is
--     get_my_profile_role(), which is in definer_acl_allowlist with a reason;
--   * the trigger still fires -- a grant and a revoke both still land in
--     permission_audit, confirmed inside BEGIN/ROLLBACK. A lockdown that
--     breaks the feature it protects is not a fix.
