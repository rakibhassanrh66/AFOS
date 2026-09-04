-- "You have a advisor".
--
-- The noun was interpolated into a fixed article, which works for
-- "supervisor" and not for "advisor". Caught by reading the title the trigger
-- actually produced rather than the code that produces it — the accept path
-- was verified end to end and the string came back wrong in the result.
create or replace function public.notify_teacher_link_decided()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_teacher text;
  v_noun    text := case when new.kind = 'fydp' then 'supervisor' else 'advisor' end;
  v_article text := case when new.kind = 'fydp' then 'a' else 'an' end;
begin
  if old.status <> 'pending' or new.status not in ('active', 'declined') then
    return new;
  end if;

  select coalesce(full_name, 'The teacher') into v_teacher
    from profiles where id = new.teacher_id;

  insert into user_notifications (user_id, title, body, category, deep_link_route)
  values (
    new.student_id,
    case when new.status = 'active'
         then 'You have ' || v_article || ' ' || v_noun
         else 'Your ' || v_noun || ' request was declined' end,
    case when new.status = 'active'
         then v_teacher || ' accepted. You can message them from Mentorship, '
              || 'and they can see the contact details on your profile.'
         else v_teacher || ' declined'
              || coalesce('. Reason: ' || nullif(btrim(new.decline_reason), ''), '.')
              || ' You can name a different teacher.' end,
    'mentorship', '/mentorship');
  return new;
end
$function$;
