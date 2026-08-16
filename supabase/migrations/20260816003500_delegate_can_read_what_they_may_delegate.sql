-- A manager could grant and revoke, but could not SEE.
--
-- APPLIED 2026-08-16.
--
-- The three delegation policies were written as a set and one of the three was
-- missed. INSERT and DELETE each got a delegate rule. SELECT did not:
--
--   read_own_or_super_admin_user_permissions:
--     (user_id = auth.uid()) OR (get_my_profile_role() = 'super_admin')
--
-- A manager is neither the subject nor a super_admin, so reading another
-- user's grants returned ZERO ROWS -- silently, because RLS filters rather
-- than errors. Consequences, worst last:
--
--   1. The permission sheet showed every checkbox UNTICKED for a subject who
--      already held areas. A manager had no way to see what they had already
--      given anyone.
--   2. Revoking was impossible. manage_users_screen computes revocations as
--      granted - selected, and `granted` was always empty.
--   3. Ticking a box the subject already held produced an INSERT that violates
--      user_permissions_pkey (user_id, permission_id) -- the save failed with a
--      duplicate-key error naming a constraint, for a box that looked unticked.
--
-- So delegation was only ever half-usable, and the half that worked was the
-- half that hands out MORE access.
--
-- THE RULE. A delegate may read a user_permissions row when the permission on
-- it is one they themselves hold -- the same test that already decides whether
-- they may grant or revoke it (caller_holds_permission). Visibility and
-- authority become the same set, which is what makes widening this safe:
--   * it exposes nothing they could not already change;
--   * it exposes nothing outside their own remit -- a manager holding only
--     routine:upload learns nothing about who manages the library;
--   * it is deliberately NOT "a delegate sees everything", because
--     permissions:delegate is itself grantable, and that reading would let a
--     narrow manager enumerate the entire authority graph.
--
-- Existing policies are untouched. Postgres ORs permissive policies for the
-- same command, so this can only ever add rows a delegate may see.
create policy delegate_read_what_they_may_delegate
  on public.user_permissions
  for select
  to authenticated
  using (
    caller_can('permissions', 'delegate', (select auth.uid()))
    and caller_holds_permission(permission_id)
  );

-- VERIFIED after applying, as a real delegate (role `staff`, holding
-- routine:upload + permissions:delegate) via set_config on request.jwt.claims:
--
--   alim_is_a_manager            | t
--   may_see_routine_upload_rows  | t   <- the area he holds
--   may_see_library_rows         | f   <- an area he does not
--
-- i.e. the widening is bounded by his own grants, not by his manager status.
