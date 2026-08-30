-- my_submit_avatar()/admin_approve_avatar()/admin_reject_avatar() (20260830164152)
-- are SECURITY DEFINER, but that bypasses RLS, not a BEFORE UPDATE TRIGGER --
-- a trigger fires no matter how the UPDATE was issued. Nothing stopped a
-- client from skipping those RPCs entirely and calling
--   supabase.from('profiles').update({'avatar_url': 'evil.jpg'})
-- directly, which the existing self-edit RLS policy already permits (it
-- governs ROWS, not columns) -- a straight bypass of admin review.
--
-- This project already closed the identical hole for role/role_id/
-- is_verified in protect_profile_privileged_columns() (20260704010000, since
-- evolved). Extending the same trigger to the avatar-review columns, rather
-- than adding a second trigger, keeps one place that answers "what can a
-- self-edit never touch".

create or replace function public.protect_profile_privileged_columns()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_role text;
  c_assignable constant text[] := array['student', 'teacher', 'staff', 'exam_controller'];
begin
  if NEW.role      is distinct from OLD.role
     or NEW.role_id    is distinct from OLD.role_id
     or NEW.is_verified is distinct from OLD.is_verified
  then
    if auth.uid() is null then
      return NEW;
    end if;

    v_role := get_my_profile_role();

    if v_role = 'super_admin' then
      return NEW;
    end if;

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
      if OLD.role is distinct from NEW.role and not (OLD.role = any (c_assignable)) then
        raise exception 'Only a super-admin can change the role of a "%".', OLD.role;
      end if;
      return NEW;
    end if;

    raise exception 'Not authorized to change role, role_id, or is_verified.';
  end if;

  -- Avatar review state. can_browse_users() (the same population the review
  -- RPCs already require) may change any of it. A self-edit may:
  --   * set avatar_review_status only to 'none' or 'pending' -- never grant
  --     itself 'approved' by writing straight to the table;
  --   * clear its own avatar_url or avatar_review_reason to null (removing
  --     an already-approved photo, or the client-side reset a resubmission
  --     does) but never set either to a new non-null value;
  --   * never touch avatar_reviewed_by, avatar_reviewed_at, or verified_at.
  if auth.uid() is not null and not can_browse_users() then
    if (NEW.avatar_url is distinct from OLD.avatar_url and NEW.avatar_url is not null)
       or (NEW.avatar_review_reason is distinct from OLD.avatar_review_reason
           and NEW.avatar_review_reason is not null)
       or NEW.avatar_reviewed_by is distinct from OLD.avatar_reviewed_by
       or NEW.avatar_reviewed_at is distinct from OLD.avatar_reviewed_at
       or NEW.verified_at is distinct from OLD.verified_at
       or (NEW.avatar_review_status is distinct from OLD.avatar_review_status
           and NEW.avatar_review_status not in ('none', 'pending'))
    then
      raise exception 'Not authorized to change avatar review state.';
    end if;
  end if;

  return NEW;
end;
$function$;
