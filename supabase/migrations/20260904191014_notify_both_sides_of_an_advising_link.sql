-- =====================================================================
--  Nobody was told anything.
--
--  A student named a teacher and the teacher had no idea until they happened
--  to open the screen; a teacher accepted and the student had no idea at all.
--  The pairing worked and the people in it could not see it working.
--
--  These are TRIGGERS rather than app-side sends, deliberately. The four
--  triggers dropped in 20260904092910 were dropped because the app was ALSO
--  sending those and every recipient got two. Nothing in the advising client
--  sends a notification, so here the trigger is the only sender.
--
--  Category 'mentorship' rather than a new one: advising is rendered inside
--  Mentorship, the category already carries its own icon in the notification
--  centre, and inventing 'advising' would give it the anonymous bell that
--  v2.10.7 existed to remove.
--
--  Verified behaviourally, then rolled back with 0 rows and 0 notifications
--  left:  teacher told on request; student told on accept; student told on
--  decline WITH the reason; the message recipient told and the sender not;
--  and a withdrawal (pending -> ended) stays silent.
-- =====================================================================

-- 1. A student asks. The teacher needs to know something is waiting.
create or replace function public.notify_teacher_link_requested()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_student text;
  v_id      text;
begin
  select coalesce(full_name, 'A student'), coalesce(university_id, '')
    into v_student, v_id
    from profiles where id = new.student_id;

  insert into user_notifications (user_id, title, body, category, deep_link_route)
  values (
    new.teacher_id,
    case when new.kind = 'fydp'
         then 'A final year project request'
         else 'An advising request' end,
    v_student || case when v_id <> '' then ' (' || v_id || ')' else '' end ||
      case when new.kind = 'fydp'
           then ' has asked you to supervise their final year project.'
           else ' has asked you to be their academic advisor.' end ||
      ' Review them in Mentorship, under My Students.',
    'mentorship', '/mentorship');
  return new;
end
$function$;

drop trigger if exists trg_notify_teacher_link_requested on public.teacher_links;
create trigger trg_notify_teacher_link_requested
  after insert on public.teacher_links
  for each row when (new.status = 'pending')
  execute function public.notify_teacher_link_requested();

-- 2. The teacher answers. The student has been waiting on exactly this.
--    (The article bug in the accept title is fixed in the next migration.)
create or replace function public.notify_teacher_link_decided()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_teacher text;
  v_noun    text := case when new.kind = 'fydp' then 'supervisor' else 'advisor' end;
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
         then 'You have a ' || v_noun
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

drop trigger if exists trg_notify_teacher_link_decided on public.teacher_links;
create trigger trg_notify_teacher_link_decided
  after update of status on public.teacher_links
  for each row execute function public.notify_teacher_link_decided();

-- 3. A message arrives. Told to whichever of the two did not send it.
create or replace function public.notify_teacher_link_message()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_link      teacher_links%rowtype;
  v_recipient uuid;
  v_sender    text;
begin
  select * into v_link from teacher_links where id = new.link_id;
  if not found or v_link.status <> 'active' then
    return new;
  end if;

  v_recipient := case when new.sender_id = v_link.student_id
                      then v_link.teacher_id else v_link.student_id end;

  select coalesce(full_name, 'Someone') into v_sender
    from profiles where id = new.sender_id;

  insert into user_notifications (user_id, title, body, category, deep_link_route)
  values (
    v_recipient,
    'Message from ' || v_sender,
    -- Truncated rather than sent whole: a notification is a nudge, and the
    -- message itself is one tap away behind the same policy that guards it.
    left(btrim(new.body), 140) ||
      case when length(btrim(new.body)) > 140 then '…' else '' end,
    'mentorship', '/mentorship');
  return new;
end
$function$;

drop trigger if exists trg_notify_teacher_link_message on public.teacher_link_messages;
create trigger trg_notify_teacher_link_message
  after insert on public.teacher_link_messages
  for each row execute function public.notify_teacher_link_message();

revoke all on function public.notify_teacher_link_requested() from public, anon, authenticated;
revoke all on function public.notify_teacher_link_decided() from public, anon, authenticated;
revoke all on function public.notify_teacher_link_message() from public, anon, authenticated;
