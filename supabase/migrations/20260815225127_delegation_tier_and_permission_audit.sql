-- =====================================================================
--  A delegation tier below super_admin, and an audit trail for both.
--
--  APPLIED 2026-08-15. Filename matches the remote ledger version read back
--  from supabase_migrations.schema_migrations after applying, not local wall
--  clock -- see CLAUDE.md.
--
--  WHY. Until now only a super_admin could grant an admin area, so every
--  delegation had to go through one person. This adds a "senior manager" who
--  can distribute work themselves.
--
--  THE SAFETY PROPERTY, and it is the whole design: a delegate may grant ONLY
--  permissions they themselves currently hold. They therefore cannot raise
--  anyone above their own level, including themselves. This table was involved
--  in an earlier privilege escalation (a NULL role_id self-promoting to
--  super_admin), so the rule is deliberately one sentence long and enforced in
--  the database rather than in the client.
--
--  VERIFIED under RLS with BEGIN/ROLLBACK per role:
--    delegate grants an area he HOLDS to another   -> allowed
--    delegate grants an area he does NOT hold      -> 42501 refused
--    delegate grants to HIMSELF                    -> 42501 refused
--    plain student grants anything                 -> 42501 refused
--    audit readable by student/teacher/delegate    -> 0 rows
--    audit readable by super_admin                 -> visible
-- =====================================================================

insert into permissions (resource, action, scope)
values ('permissions', 'delegate', 'global'),
       ('audit', 'read', 'global')
on conflict do nothing;

-- Does the CALLER personally hold this permission right now? SECURITY DEFINER
-- so it can read user_permissions rows other than the caller's own without a
-- policy that would expose them.
create or replace function public.caller_holds_permission(p_permission_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from user_permissions
    where user_id = (select auth.uid())
      and permission_id = p_permission_id
  );
$$;

revoke all on function public.caller_holds_permission(uuid) from public, anon;
grant execute on function public.caller_holds_permission(uuid) to authenticated;

-- super_admin's existing ALL policy is untouched; these are additional
-- permissive policies for the delegate tier.
drop policy if exists delegate_grant_only_what_they_hold on user_permissions;
create policy delegate_grant_only_what_they_hold
  on user_permissions for insert to authenticated
  with check (
    caller_can('permissions', 'delegate', (select auth.uid()))
    and caller_holds_permission(permission_id)
    -- A delegate cannot grant to THEMSELVES. Holding the delegate capability
    -- plus one area would otherwise let them re-grant that area to their own
    -- account; harmless today, but it is the shape of an escalation and costs
    -- nothing to forbid.
    and user_id <> (select auth.uid())
  );

drop policy if exists delegate_revoke_only_what_they_hold on user_permissions;
create policy delegate_revoke_only_what_they_hold
  on user_permissions for delete to authenticated
  using (
    caller_can('permissions', 'delegate', (select auth.uid()))
    and caller_holds_permission(permission_id)
    and user_id <> (select auth.uid())
  );

-- The audit trail. user_permissions already carries granted_by/granted_at, so
-- a grant is half-recorded; a REVOKE is a DELETE and leaves nothing at all.
-- With delegation opening beyond super_admin, "who gave this person routine
-- upload, and who took it away" has to have an answer.
create table if not exists public.permission_audit (
  id            bigint generated always as identity primary key,
  actor_id      uuid references profiles(id) on delete set null,
  subject_id    uuid references profiles(id) on delete set null,
  permission_id uuid,
  resource      text not null,
  action        text not null,
  event         text not null check (event in ('granted', 'revoked')),
  occurred_at   timestamptz not null default now()
);

create index if not exists permission_audit_subject_idx
  on public.permission_audit (subject_id, occurred_at desc);

comment on table public.permission_audit is
  'Append-only record of every permission grant and revoke. Written by a '
  'trigger on user_permissions so no client can bypass it. Readable only by '
  'super_admin and holders of audit:read.';

-- resource/action are denormalised so the log still reads correctly if a
-- permission row is later renamed or removed.
create or replace function public.log_permission_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_resource text;
  v_action   text;
  v_perm     uuid;
begin
  v_perm := coalesce(new.permission_id, old.permission_id);
  select p.resource, p.action into v_resource, v_action
    from permissions p where p.id = v_perm;

  insert into permission_audit (actor_id, subject_id, permission_id, resource, action, event)
  values (
    (select auth.uid()),
    coalesce(new.user_id, old.user_id),
    v_perm,
    coalesce(v_resource, '(deleted)'),
    coalesce(v_action, '(deleted)'),
    case when tg_op = 'INSERT' then 'granted' else 'revoked' end
  );
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_log_permission_change on user_permissions;
create trigger trg_log_permission_change
  after insert or delete on user_permissions
  for each row execute function public.log_permission_change();

-- Readable by super_admin or audit:read, and by nobody else -- including the
-- subject. No UPDATE or DELETE policy exists for anyone, because a log that
-- can be edited is not a log.
alter table public.permission_audit enable row level security;

drop policy if exists read_permission_audit on public.permission_audit;
create policy read_permission_audit
  on public.permission_audit for select to authenticated
  using (
    get_my_profile_role() = 'super_admin'
    or caller_can('audit', 'read', (select auth.uid()))
  );
