-- Work was delegable. Decisions were not.
--
-- APPLIED 2026-08-16.
--
-- Every approval in the app resolved to one policy:
-- `get_my_profile_role() = 'super_admin'`. Approving a CR, approving a signup,
-- reading feedback, changing a role. An officer who joins to run a department
-- had two options: be made super_admin, which hands them the entire system, or
-- wait for the owner. The delegation tier shipped the day before distributes
-- WORK; it does not distribute DECISIONS, and decisions are what an absent
-- super_admin actually blocks.
--
-- These are ordinary rows in `permissions`, so they are granted, revoked,
-- audited and delegated by machinery that already exists. No new tier, no new
-- concept for anyone to learn.
insert into permissions (resource, action, scope) values
  ('cr',       'approve', 'all'),   -- decide CR requests
  ('users',    'approve', 'all'),   -- approve a pending signup
  ('roles',    'assign',  'all'),   -- change another user's role, bounded below
  ('feedback', 'triage',  'all')    -- read and answer everyone's feedback
on conflict (resource, action, scope) do nothing;

-- THE CEILING, and a hole that predates it.
--
-- roles:assign is the one grant here that could escalate, so it is bounded in
-- the trigger rather than in the UI. A holder may set only the four roles that
-- confer no authority over other people, and never on their own row.
--
-- While writing that, the existing rule turned out to be wider than anyone had
-- said out loud: the trigger allowed **'admin'** to change roles WITHOUT LIMIT.
-- Any admin could promote anybody -- including a second account of their own --
-- straight to super_admin. Admin is now bounded by the same list. Only a
-- super_admin can mint privilege at or above the admin tier.
--
-- is_verified is split out and treated separately: approving a signup is not a
-- role change, and gating it behind roles:assign would have meant handing out
-- role assignment to get an approval queue.
create or replace function public.protect_profile_privileged_columns()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_role text;
  -- Deliberately excludes admin, dept_admin and super_admin.
  c_assignable constant text[] := array['student', 'teacher', 'staff', 'exam_controller'];
begin
  if NEW.role      is distinct from OLD.role
     or NEW.role_id    is distinct from OLD.role_id
     or NEW.is_verified is distinct from OLD.is_verified
  then
    -- No JWT on the request = server-side context: the signup trigger's own
    -- upsert, an edge function on the service role, a migration. Those are the
    -- paths that legitimately assign a role, and none of them is a user acting
    -- on themselves.
    if auth.uid() is null then
      return NEW;
    end if;

    v_role := get_my_profile_role();

    -- Unbounded, and the only unbounded case.
    if v_role = 'super_admin' then
      return NEW;
    end if;

    -- is_verified alone is the signup approval queue, not a role change.
    if NEW.role is not distinct from OLD.role
       and NEW.role_id is not distinct from OLD.role_id
       and NEW.is_verified is distinct from OLD.is_verified
    then
      if v_role = 'admin' or caller_can('users', 'approve', auth.uid()) then
        return NEW;
      end if;
      raise exception 'Not authorized to approve or unapprove an account.';
    end if;

    if v_role = 'admin' or caller_can('roles', 'assign', auth.uid()) then
      if NEW.id = auth.uid() then
        raise exception 'You cannot change your own role.';
      end if;
      if NEW.role is distinct from OLD.role and not (NEW.role = any (c_assignable)) then
        raise exception 'You may only assign these roles: %. Assigning "%" is a super-admin decision.',
          array_to_string(c_assignable, ', '), NEW.role;
      end if;
      -- Taking authority away is as consequential as granting it: without
      -- this, a roles:assign holder could demote an admin to student and then
      -- promote them back to anything on the assignable list.
      if OLD.role is distinct from NEW.role and not (OLD.role = any (c_assignable)) then
        raise exception 'Only a super-admin can change the role of a "%".', OLD.role;
      end if;
      return NEW;
    end if;

    raise exception 'Not authorized to change role, role_id, or is_verified.';
  end if;

  return NEW;
end;
$function$;

-- A trigger function needs no EXECUTE grant; it runs under the table owner.
-- Same lesson as 20260726135859 and 20260815234149.
revoke all on function public.protect_profile_privileged_columns() from public, anon, authenticated;

-- VERIFIED after applying, as a real holder of roles:assign via
-- set_config on request.jwt.claims:
--
--   update profiles set role='super_admin'  -> ERROR: You may only assign
--     these roles: student, teacher, staff, exam_controller.
--   update profiles set role='teacher'      -> allowed
--
-- Both subjects were restored afterwards.
