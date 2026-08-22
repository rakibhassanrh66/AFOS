-- The exam schedule, for whoever is asking.
--
-- STUDENT: their own batch's exams, each resolved to the room they sit in.
-- TEACHER: the rooms they are on duty in. Those are different questions
-- against different tables -- the routine says WHEN a batch sits, the seat
-- plan says WHERE and WHO INVIGILATES -- and until now nothing joined them.
--
-- FAN-OUT IS DELIBERATE, and confirmed by the owner. A routine row carries a
-- batch and no section ("Batch-65") while the seat plan is per section
-- ("65_A"), so one routine row legitimately covers every section of that
-- batch; the student's own section is what narrows it back down. Verified
-- live: CSE123/Batch-70 fans out to sections A-F, ~51 seats each, with rooms
-- correctly shared between adjacent sections (G1-004 in both A and B).
--
-- INVOKER, and it reads auth.uid() -- there is no parameter to aim at anyone
-- else.
create or replace function public.my_exam_schedule()
returns jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  me    record;
  term  record;
  mine  jsonb := '[]'::jsonb;
  duty  jsonb := '[]'::jsonb;
  ini   text;
begin
  select p.id, p.role, p.batch, p.section
    into me
  from profiles p
  where p.id = auth.uid();

  if me.id is null then
    return jsonb_build_object('role', null);
  end if;

  -- The term on show: a live one first (today inside its window), otherwise
  -- the soonest upcoming, otherwise the most recent. Unpublished terms never
  -- appear -- an import is reviewed before a student's dashboard announces it.
  select *
    into term
  from exam_terms
  where published
  order by (starts_on <= current_date and ends_on >= current_date) desc,
           (starts_on >= current_date) desc,
           starts_on asc nulls last
  limit 1;

  if term.id is null then
    return jsonb_build_object('role', me.role, 'term', null,
                              'exams', mine, 'duties', duty);
  end if;

  if nullif(me.batch, '') is not null then
    select coalesce(jsonb_agg(x order by (x->>'date')::date, x->>'slot'), '[]'::jsonb)
      into mine
    from (
      select jsonb_build_object(
        'date',  e.exam_date,
        'slot',  e.slot_label,
        'start', e.start_time,
        'end',   e.end_time,
        'code',  e.subject_code,
        'title', e.subject,
        'batch', e.batch,
        'rooms', (
          select coalesce(jsonb_agg(distinct a.room_no), '[]'::jsonb)
          from exam_room_allocations a
          where a.exam_date   = e.exam_date
            and a.course_code = e.subject_code
            and a.batch       = e.batch
            and (nullif(me.section, '') is null or a.section = me.section)
            and (a.slot_label is null or e.slot_label is null
                 or a.slot_label = e.slot_label)
        )
      ) as x
      from exams e
      where e.term_id = term.id
        and e.batch = me.batch
    ) s;
  end if;

  select t.teacher_initial into ini
  from teachers t
  where t.profile_id = me.id;

  if nullif(ini, '') is not null then
    -- Matched on the term's DATE WINDOW rather than term_id: the 1632
    -- allocations already in the table predate term_id and would all be
    -- invisible if this insisted on the foreign key.
    select coalesce(jsonb_agg(x order by (x->>'date')::date, x->>'slot'), '[]'::jsonb)
      into duty
    from (
      select jsonb_build_object(
        'date',    a.exam_date,
        'slot',    a.slot_label,
        'code',    a.course_code,
        'title',   a.course_title,
        'batch',   a.batch,
        'section', a.section,
        'room',    a.room_no,
        'seats',   a.seats
      ) as x
      from exam_room_allocations a
      where a.teacher_initial = ini
        and (term.starts_on is null or a.exam_date >= term.starts_on)
        and (term.ends_on   is null or a.exam_date <= term.ends_on)
    ) d;
  end if;

  return jsonb_build_object(
    'role',    me.role,
    'batch',   nullif(me.batch, ''),
    'section', nullif(me.section, ''),
    'initial', ini,
    'term', jsonb_build_object(
      'id', term.id, 'type', term.exam_type, 'season', term.season,
      'year', term.year, 'department', term.department,
      'startsOn', term.starts_on, 'endsOn', term.ends_on,
      -- What the dashboard indicator needs to decide whether to appear at all.
      -- A finished exam period must disappear for students rather than sit
      -- there advertising a date that has passed.
      'isOver', (term.ends_on is not null and term.ends_on < current_date),
      'isLive', (term.starts_on is not null and term.ends_on is not null
                 and current_date between term.starts_on and term.ends_on)
    ),
    'exams',  mine,
    'duties', duty
  );
end;
$$;

comment on function public.my_exam_schedule() is
  'The caller''s own exam schedule (student) or invigilation duties (teacher), for the live published term.';

revoke all on function public.my_exam_schedule() from public, anon;
grant execute on function public.my_exam_schedule() to authenticated;

-- Lets an administrator record the initial the seat plan calls a teacher by,
-- for the cases the name-match backfill cannot resolve -- which is currently
-- all of them, because every teacher account in this project is a test one.
create or replace function public.set_teacher_initial(
  p_profile_id uuid,
  p_initial    text
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Gated INTERNALLY and raises, matching every other privileged RPC here.
  if not exists (
    select 1 from profiles p
    where p.id = (select auth.uid()) and p.is_verified
      and (p.role = any (array['admin','dept_admin','super_admin','exam_controller'])
           or caller_can('routine','upload')
           or caller_can('exam_seat','upload'))
  ) then
    raise exception 'Not permitted to set a teacher initial'
      using errcode = '42501';
  end if;

  update teachers
     set teacher_initial = nullif(btrim(p_initial), '')
   where profile_id = p_profile_id;

  if not found then
    raise exception 'No teacher record for that profile';
  end if;
end;
$$;

revoke all on function public.set_teacher_initial(uuid, text) from public, anon;
grant execute on function public.set_teacher_initial(uuid, text) to authenticated;
