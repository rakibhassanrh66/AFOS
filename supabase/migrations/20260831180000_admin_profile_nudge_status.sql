-- "Who have I already chased about their incomplete profile, and when?"
--
-- The Profile Inspection screen lists verified accounts still failing
-- profile_is_complete() and offers a "Notify to finish profile" button. It had
-- no way to show whether that button had ALREADY been pressed for someone, so
-- an admin working the list could notify the same person repeatedly and had no
-- way to tell who had never been contacted at all.
--
-- WHY THIS IS A FUNCTION AND NOT A CLIENT QUERY. `user_notifications` has
-- exactly one SELECT policy -- `own_notifs`, auth.uid() = user_id -- so a
-- client reading that table for OTHER people gets zero rows, silently. Not an
-- error: an empty result, which would have rendered as "nobody has ever been
-- notified" on every card, forever. Widening that policy was rejected as the
-- fix: notification BODIES across the whole app are private, and this question
-- needs none of them. This returns only "was the profile nudge sent to this id,
-- and when" -- no title, no body, no other category.
--
-- WHY THE NOTIFICATION LOG IS THE SOURCE OF TRUTH, rather than a new
-- profiles.nudged_at column: a column is a second copy of a fact that already
-- exists, and it drifts the first time a notification is sent by any path that
-- forgets to update it. The log cannot drift from itself.
--
-- Matched on deep_link_route rather than the title. The route is the semantic
-- identity of this nudge ("go finish your profile") and survives the copy being
-- reworded; the title is kept as an OR so rows sent before the deep link was
-- attached still count.
create or replace function public.admin_profile_nudge_status(p_user_ids uuid[])
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_result jsonb;
begin
  -- Same gate as admin_user_groups(): the capability to browse users at all.
  if not can_browse_users() then
    raise exception 'Not authorized to browse users' using errcode = '42501';
  end if;

  select coalesce(jsonb_object_agg(t.uid, t.last_notified_at), '{}'::jsonb)
    into v_result
    from (
      select n.user_id::text as uid,
             max(n.received_at) as last_notified_at
        from user_notifications n
       where n.user_id = any(p_user_ids)
         and (n.deep_link_route = '/complete-profile'
              or n.title = 'Your AFOS profile needs attention')
       group by n.user_id
    ) t;

  return v_result;
end;
$$;

revoke all on function public.admin_profile_nudge_status(uuid[]) from public;
grant execute on function public.admin_profile_nudge_status(uuid[]) to authenticated;
