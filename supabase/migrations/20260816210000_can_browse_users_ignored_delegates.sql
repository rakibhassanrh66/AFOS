-- can_browse_users() locked out the exact tier it was written for.
--
-- I wrote it as:
--
--   ... role in ('super_admin','admin','dept_admin')
--       or has_permission('users','approve','all')
--
-- and has_permission() reads ONLY role_permissions:
--
--   SELECT 1 FROM role_permissions rp
--     JOIN permissions p ON rp.permission_id = p.id
--     JOIN profiles pr ON pr.role_id = rp.role_id
--    WHERE pr.id = auth.uid() ...
--
-- AFOS's delegation tier does not live in role_permissions. It lives in
-- user_permissions — a grant to an individual, which is what
-- PermissionSession reads on the client and what manage_users_screen shows.
--
-- So a staff member granted users:approve saw the Manage Users screen (the
-- client check passes, reading user_permissions) and got 42501 from every RPC
-- behind it. Verified live: with the grant present,
-- has_permission('users','approve','all') returned false and
-- can_browse_users() returned false with it.
--
-- This is the FOURTH time in this project's log that a capability was added at
-- the RPC layer without the read path that lets the holder reach the rows —
-- after delegate_read_what_they_may_delegate, cr_approver_reads_requests, and
-- the decision-tier SELECT policy. The failure mode is always silence, because
-- the client-side check and the server-side check disagree and only one of
-- them is visible.
--
-- WHY MY OWN TESTS MISSED IT: I exercised the RPCs as super_admin, which
-- satisfies the role branch and never touches the grant branch at all. The bug
-- only appears for someone whose ONLY route is the grant.
--
-- has_permission() itself is left alone deliberately. Changing what it means
-- would silently alter every other caller's authorisation, which is not a
-- side effect to take on while fixing one function.

create or replace function public.can_browse_users()
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select
    -- Roles that carry the capability inherently.
    exists (
      select 1 from profiles
       where id = auth.uid()
         and role in ('super_admin', 'admin', 'dept_admin')
    )
    -- A role that has been given it through role_permissions.
    or has_permission('users', 'approve', 'all')
    -- A PERSON who has been given it directly. This is the branch that was
    -- missing, and the one the whole delegation tier depends on.
    or exists (
      select 1
        from user_permissions up
        join permissions p on p.id = up.permission_id
       where up.user_id = auth.uid()
         and p.resource = 'users'
         and p.action   = 'approve'
    );
$$;

revoke all on function public.can_browse_users() from public, anon;
grant execute on function public.can_browse_users() to authenticated;
