-- Extends the ALREADY-EXISTING caller_can(resource, action) delegation
-- mechanism (already live on transport_routes, schedule_slots,
-- exam_room_allocations, notices) to the remaining admin-gated tables whose
-- resource:action pair already exists in the `permissions` catalog, so a
-- super_admin can delegate a specific area of admin work to a non-admin user
-- (e.g. "hall:manage" without making them a full admin) and have it actually
-- take effect at the database layer, not just in a UI that shows a checkbox.

-- 1. `permissions`/`role_permissions` had RLS enabled with ZERO policies,
--    which under Postgres RLS defaults to fully locked -- not even
--    super_admin could read them from the client. These are catalog/rule
--    tables (resource:action labels, not sensitive data), so public read is
--    correct here, matching the existing public_read_roles policy on `roles`.
create policy public_read_permissions on permissions for select using (true);
create policy public_read_role_permissions on role_permissions for select using (true);

-- 2. Extend caller_can into the remaining tables.
alter policy admin_write_halls on halls
  using (exists (select 1 from profiles where profiles.id = auth.uid()
    and (profiles.role = any (array['admin','super_admin']) or caller_can('hall','manage'))));

alter policy admin_hall_all on hall_applications
  using (exists (select 1 from profiles where profiles.id = auth.uid()
    and (profiles.role = any (array['admin','staff','super_admin']) or caller_can('hall','manage'))));

alter policy admin_manage_sos_alerts on sos_alerts
  using (get_my_profile_role() = any (array['admin','super_admin','staff']) or caller_can('sos','manage'))
  with check (get_my_profile_role() = any (array['admin','super_admin','staff']) or caller_can('sos','manage'));

alter policy admin_manage_books on books
  using (get_my_profile_role() = any (array['admin','staff','dept_admin','super_admin']) or caller_can('library','manage'))
  with check (get_my_profile_role() = any (array['admin','staff','dept_admin','super_admin']) or caller_can('library','manage'));

alter policy admin_manage_borrowed_books on borrowed_books
  using (get_my_profile_role() = any (array['admin','staff','dept_admin','super_admin']) or caller_can('library','manage'))
  with check (get_my_profile_role() = any (array['admin','staff','dept_admin','super_admin']) or caller_can('library','manage'));

alter policy super_admin_manage_conference_requests on conference_room_requests
  using (get_my_profile_role() = 'super_admin' or caller_can('conference','manage'))
  with check (get_my_profile_role() = 'super_admin' or caller_can('conference','manage'));

-- 3. list_my_permissions(): the client-side counterpart to caller_can -- a
--    single round trip returning every (resource, action) pair the caller
--    currently has, whether from their ROLE's role_permissions or a personal
--    user_permissions grant. This is what the Flutter app loads once per
--    session (mirroring RoleSession's own pattern) to decide which admin
--    screens/router routes a delegated (non-admin-role) user can reach --
--    without this, a granted permission would work at the RLS layer but the
--    app's own router would still redirect the user away before they ever
--    got a chance to use it.
--
--    p_user_id defaults to the caller's own id; passing a DIFFERENT id is
--    restricted to super_admin (matching user_permissions' own read policy),
--    so this can't be used to enumerate an arbitrary other user's grants.
create or replace function list_my_permissions(p_user_id uuid default auth.uid())
returns table(resource text, action text, scope text)
language plpgsql
security definer
set search_path = public
stable
as $$
begin
  if p_user_id <> auth.uid() and get_my_profile_role() <> 'super_admin' then
    raise exception 'Not authorized';
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
$$;

grant execute on function list_my_permissions(uuid) to authenticated;
