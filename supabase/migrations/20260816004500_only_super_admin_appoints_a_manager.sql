-- The manager tier could clone itself sideways.
--
-- APPLIED 2026-08-16.
--
-- `permissions:delegate` is stored in the same table as every working area, so
-- the rule "a delegate may pass on anything they hold" applied to it too. A
-- manager held permissions:delegate, therefore a manager could GRANT
-- permissions:delegate -- appointing further managers, who could appoint
-- further managers, without limit.
--
-- Nothing about that breaks the "cannot grant what you don't hold" invariant:
-- no one gains an area they lack, and no one rises above the person who
-- appointed them. What it breaks is the shape of the org. The design is that a
-- super_admin appoints managers and managers distribute WORK; a tier that can
-- recruit into itself has no one accountable for its size, and the only trace
-- is a permission_audit row nobody is watching. Authority to do a job and
-- authority to hand out that job to others are different powers, and only the
-- second one compounds.
--
-- So permissions:delegate is carved out of both delegate policies. Appointing
-- and dismissing a manager is super_admin's alone -- super_admin_manage_user_permissions
-- is a separate ALL policy and is untouched, so they keep doing both.
--
-- This strictly NARROWS what a delegate may write. It cannot open anything.
alter policy delegate_grant_only_what_they_hold
  on public.user_permissions
  with check (
    caller_can('permissions', 'delegate', (select auth.uid()))
    and caller_holds_permission(permission_id)
    and (user_id <> (select auth.uid()))
    and permission_id <> (select id from permissions
                           where resource = 'permissions' and action = 'delegate')
  );

-- Revoking gets the same carve-out, and for a sharper reason than symmetry: a
-- manager who could revoke permissions:delegate could strip a PEER of their
-- management access. Not an escalation, but sabotage, and it needs no more
-- authority than being appointed once.
alter policy delegate_revoke_only_what_they_hold
  on public.user_permissions
  using (
    caller_can('permissions', 'delegate', (select auth.uid()))
    and caller_holds_permission(permission_id)
    and (user_id <> (select auth.uid()))
    and permission_id <> (select id from permissions
                           where resource = 'permissions' and action = 'delegate')
  );

-- And the read added in 20260816003500 gets it too, so all three agree: a
-- manager sees, grants and revokes exactly the working areas they hold.
--
-- Without this, a manager could still LIST every other manager -- holding
-- permissions:delegate makes caller_holds_permission() true for it, so those
-- rows were visible. Being unable to enumerate the tier from inside it is the
-- point; a manager who cannot appoint one has no reason to need the roster.
alter policy delegate_read_what_they_may_delegate
  on public.user_permissions
  using (
    caller_can('permissions', 'delegate', (select auth.uid()))
    and caller_holds_permission(permission_id)
    and permission_id <> (select id from permissions
                           where resource = 'permissions' and action = 'delegate')
  );

-- The UI agrees rather than being quietly stricter: manage_users_screen drops
-- the "Permissions: delegate" checkbox from a non-super_admin's catalogue, and
-- hides the Management filter and the Managers count from them, because a
-- count of rows they cannot read would render as a confident 0.
