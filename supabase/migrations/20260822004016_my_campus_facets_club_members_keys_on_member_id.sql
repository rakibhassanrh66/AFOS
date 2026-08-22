-- club_members keys on member_id, not profile_id. Caught by calling the
-- function as a real student rather than by reading its definition back --
-- plpgsql does not resolve column names until the body actually runs, so the
-- previous migration created cleanly and would have failed for every user on
-- first load.
--
-- The figures a dashboard shows the person looking at it.
--
-- WHY. Until now only super_admin/admin/dept_admin got a console at all; the
-- other four roles landed on a grid of launcher tiles with no information on
-- it. This is the per-user half: the caller's own week, their own clubs, their
-- own unread count. The campus-wide half (campus_activity_facets) is the same
-- for everybody and is already separate.
--
-- SECURITY INVOKER, and it reads auth.uid() rather than taking a user id, so
-- there is no parameter anyone could point at somebody else. Every table it
-- touches is filtered by RLS for the caller on top of that.
create or replace function public.my_campus_facets()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  me   record;
  slots int := 0;
  labs  int := 0;
  byday jsonb := '[]'::jsonb;
begin
  select p.id, p.role, p.batch, p.section, p.department, p.semester
    into me
  from profiles p
  where p.id = auth.uid();

  if me.id is null then
    return jsonb_build_object('role', null);
  end if;

  if nullif(me.batch, '') is not null then
    select count(*),
           count(*) filter (where s.is_lab)
      into slots, labs
    from schedule_slots s
    where coalesce(s.is_cancelled, false) = false
      and s.batch = me.batch
      and (nullif(me.section, '') is null or s.section = me.section);

    select coalesce(jsonb_agg(jsonb_build_object('d', d, 'n', n) order by d), '[]'::jsonb)
      into byday
    from (
      select s.day_of_week as d, count(*) as n
      from schedule_slots s
      where coalesce(s.is_cancelled, false) = false
        and s.batch = me.batch
        and (nullif(me.section, '') is null or s.section = me.section)
        and s.day_of_week is not null
      group by 1
    ) g;
  end if;

  return jsonb_build_object(
    'role',        me.role,
    'batch',       nullif(me.batch, ''),
    'section',     nullif(me.section, ''),
    'myslots',     slots,
    'mylabs',      labs,
    'byDay',       byday,
    'clubs',       (select count(*) from club_members  cm where cm.member_id = me.id),
    'enrollments', (select count(*) from enrollments    e where e.student_id  = me.id),
    'unread',      (select count(*) from user_notifications n
                     where n.user_id = me.id and coalesce(n.is_read, false) = false)
  );
end;
$$;

comment on function public.my_campus_facets() is
  'Per-user dashboard figures for the caller. INVOKER, reads auth.uid(), takes no user id.';

grant execute on function public.my_campus_facets() to authenticated;
