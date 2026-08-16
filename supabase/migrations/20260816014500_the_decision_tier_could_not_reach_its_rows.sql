-- The decision tier could not SEE or WRITE the rows it decides about.
--
-- APPLIED 2026-08-16, immediately after 20260816011000 shipped the tier.
--
-- protect_profile_privileged_columns was taught to permit a users:approve or
-- roles:assign holder. The ROW POLICIES were not:
--
--   admin_manage_all_profiles (UPDATE): admin, super_admin
--   admin_read_all (SELECT):            admin, teacher, dept_admin, super_admin
--
-- A staff member holding either grant matched neither. So the pending queue
-- rendered EMPTY for them, and every write affected ZERO ROWS -- silently,
-- because RLS filters rather than errors. The button did nothing and said
-- nothing.
--
-- This is the THIRD time this exact shape has appeared in two days:
--   * delegate_read_what_they_may_delegate  (20260816003500)
--   * cr_approver_reads_requests            (20260816011500)
--   * this one
--
-- Each time: a capability was added at the trigger or RPC layer, and the row
-- policy that lets the caller reach the row was not added with it. Worth
-- naming as a pattern -- when a permission gains WRITE authority, check the
-- READ path in the same change, because the failure mode is silence.
create policy decision_holders_read_profiles on public.profiles
  for select to authenticated
  using (caller_can('users','approve',(select auth.uid()))
         or caller_can('roles','assign',(select auth.uid())));

-- Deliberately NO broad UPDATE policy to match the SELECT.
--
-- A general profiles UPDATE for these holders would let a roles:assign holder
-- edit anyone's name, email or phone -- far more than "set their role", and
-- nothing in the trigger would stop it, because the trigger only guards role,
-- role_id and is_verified. These two functions do exactly one column each.
--
-- They grant REACH, not PERMISSION: protect_profile_privileged_columns still
-- runs on the update inside them and still enforces the assignable-role
-- ceiling, the self-edit ban, and the rule that only a super_admin may change
-- the role of someone who is not on that list.
create or replace function public.set_user_role(p_user_id uuid, p_role text)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_role_id uuid;
begin
  if not (get_my_profile_role() = 'super_admin'
          or caller_can('roles','assign', auth.uid())) then
    raise exception 'Not authorized to change roles.' using errcode = '42501';
  end if;
  select id into v_role_id from roles where name = p_role;
  if v_role_id is null then
    raise exception 'No such role: %', p_role;
  end if;
  -- Keeping role_id in sync with role is part of the job: the permission joins
  -- read role_id, get_my_profile_role() reads role, and the client used to set
  -- both by hand -- which is two chances to get it half right.
  update profiles set role = p_role, role_id = v_role_id where id = p_user_id;
end;
$function$;

create or replace function public.set_user_verified(p_user_id uuid, p_verified boolean)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if not (get_my_profile_role() in ('super_admin','admin')
          or caller_can('users','approve', auth.uid())) then
    raise exception 'Not authorized to approve accounts.' using errcode = '42501';
  end if;
  update profiles set is_verified = p_verified where id = p_user_id;
end;
$function$;

revoke all on function public.set_user_role(uuid, text) from public, anon;
revoke all on function public.set_user_verified(uuid, boolean) from public, anon;
grant execute on function public.set_user_role(uuid, text) to authenticated;
grant execute on function public.set_user_verified(uuid, boolean) to authenticated;

-- Note on what did NOT change: rejecting a pending signup DELETES the account
-- (auth row, storage, every owned row, via the delete-user edge function). It
-- is the most destructive action in the app wearing a mild label, so it stays
-- super_admin's even though approving does not. manage_users_screen hides the
-- Reject button entirely for a users:approve holder rather than disabling it.
--
-- VERIFIED after applying, as a real roles:assign holder via set_config on
-- request.jwt.claims:
--
--   set_user_role(<student>, 'super_admin')
--     -> ERROR: You may only assign these roles: student, teacher, staff,
--        exam_controller.   (raised by the TRIGGER, through the RPC)
--   set_user_role(<student>, 'teacher')
--     -> allowed, and role_id came back non-null
--
-- The subject was restored to 'student' and the temporary grant removed.
