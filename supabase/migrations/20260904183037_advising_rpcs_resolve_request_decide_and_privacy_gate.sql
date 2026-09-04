-- =====================================================================
--  Advising RPCs: resolution, the request/decide pair, and THE privacy gate.
--
--  Everything the client needs is behind a function, so the rules live on the
--  server. A student never handles a teacher_id; a teacher never selects a
--  student's columns directly.
--
--  Verified behaviourally against the live database before this file was
--  written (transaction rolled back afterwards, 0 rows left):
--    A  student creates a pending link                          -> true
--    B  teacher reads profile while PENDING -> refused "This request has
--       not been accepted yet."
--    C  student sets status='active' itself -> refused "Only the teacher
--       named on this request can answer it."
--    D  advisor scope   -> emergency_contact present, address present
--    E  fydp scope      -> emergency_contact NULL, address NULL, advisor named
--    F  second advisor request                                  -> refused
-- =====================================================================

-- Resolution reads TEACHER PROFILES only, never schedule_slots. That table
-- holds 221 distinct initials scraped free-text out of the routine PDF, tied
-- to no profile, and matching on it is what produced the cross-faculty "MSK"
-- bug. profiles.teacher_initial is unique, which is what makes this safe.
--
-- The `btrim(p_initial) <> ''` clause is not decoration: without it an empty
-- initial matches every teacher whose own initial is null or blank, and 2 of
-- 4 teacher profiles are exactly that today.
create or replace function public.resolve_teacher_initial(p_initial text)
returns table (
  teacher_id      uuid,
  full_name       text,
  teacher_initial text,
  designation     text,
  department      text,
  avatar_url      text,
  email           text,
  phone           text,
  on_leave        boolean
)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select p.id, p.full_name, p.teacher_initial, t.designation, p.department,
         p.avatar_url, p.email, p.phone,
         exists (select 1 from teacher_leave tl
                  where tl.teacher_id = p.id
                    and current_date between tl.starts_on and tl.ends_on)
    from profiles p
    left join teachers t on t.profile_id = p.id
   where p.role = 'teacher'
     and upper(btrim(coalesce(p.teacher_initial, ''))) = upper(btrim(coalesce(p_initial, '')))
     and btrim(coalesce(p_initial, '')) <> ''
   limit 1;
$function$;

-- THE privacy gate. Both kinds come through here, so the two column sets
-- cannot drift apart the way two separate screens would.
--   advisor -> contact, emergency contact and address.
--   fydp    -> academic and contact only; family/address NULLed, and the
--              student's advisor named so a supervisor knows who to escalate
--              to without inheriting the advisor's access.
-- A PENDING link returns nothing at all: requesting somebody must not be a
-- way to read them.
create or replace function public.student_profile_for_link(p_link_id uuid)
returns table (
  student_id         uuid,
  full_name          text,
  university_id      text,
  batch              text,
  section            text,
  semester           integer,
  cgpa               numeric,
  phone              text,
  email              text,
  avatar_url         text,
  gender             text,
  emergency_contact  text,
  permanent_division text,
  permanent_district text,
  permanent_upazila  text,
  advisor_name       text,
  advisor_initial    text
)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_link  teacher_links%rowtype;
  v_me    uuid := auth.uid();
begin
  select * into v_link from teacher_links where id = p_link_id;
  if not found then
    return;
  end if;

  if not can_browse_users()
     and v_me is distinct from v_link.teacher_id then
    raise exception 'That is not your student.' using errcode = '42501';
  end if;

  if v_link.status <> 'active' then
    raise exception 'This request has not been accepted yet.'
      using errcode = '42501';
  end if;

  return query
  select p.id, p.full_name, p.university_id, p.batch, p.section, p.semester,
         s.cgpa, p.phone, p.email, p.avatar_url, p.gender,
         case when v_link.kind = 'advisor' then p.emergency_contact end,
         case when v_link.kind = 'advisor' then p.permanent_division end,
         case when v_link.kind = 'advisor' then p.permanent_district end,
         case when v_link.kind = 'advisor' then p.permanent_upazila end,
         case when v_link.kind = 'fydp' then ap.full_name end,
         case when v_link.kind = 'fydp' then ap.teacher_initial end
    from profiles p
    left join students s on s.profile_id = p.id
    left join teacher_links al
           on al.student_id = p.id and al.kind = 'advisor' and al.status = 'active'
    left join profiles ap on ap.id = al.teacher_id
   where p.id = v_link.student_id;
end
$function$;

-- The student names a teacher by initial and never handles a teacher_id.
create or replace function public.request_teacher_link(p_initial text, p_kind text)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me      uuid := auth.uid();
  v_teacher uuid;
  v_sem     integer;
  v_id      uuid;
begin
  if v_me is null then
    raise exception 'Sign in first.' using errcode = '42501';
  end if;
  if p_kind not in ('advisor', 'fydp') then
    raise exception 'Unknown kind: %', p_kind;
  end if;

  select r.teacher_id into v_teacher from resolve_teacher_initial(p_initial) r;
  if v_teacher is null then
    raise exception 'No teacher is registered under the initial "%". Check it with your department, or search by name instead.',
      btrim(coalesce(p_initial, ''));
  end if;
  if v_teacher = v_me then
    raise exception 'That is your own initial.';
  end if;

  -- A final-year project belongs to the final two years. Enforced only when
  -- the semester is actually known: 4 of 12 profiles carry no admission year
  -- and a derived value must not be the last word on eligibility.
  if p_kind = 'fydp' then
    select s.current_semester_no into v_sem from students s where s.profile_id = v_me;
    if v_sem is not null and v_sem < 7 then
      raise exception 'A final year project supervisor is for 3rd and 4th year students. You are in semester %.', v_sem;
    end if;
  end if;

  insert into teacher_links (student_id, teacher_id, kind, status)
  values (v_me, v_teacher, p_kind, 'pending')
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception 'You already have a % request open. Withdraw it before naming someone else.',
      case p_kind when 'fydp' then 'supervisor' else 'advisor' end;
end
$function$;

create or replace function public.decide_teacher_link(
  p_link_id uuid, p_accept boolean, p_reason text default null)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  update teacher_links
     set status = case when p_accept then 'active' else 'declined' end,
         decline_reason = case when p_accept then null else nullif(btrim(coalesce(p_reason, '')), '') end
   where id = p_link_id
     and status = 'pending';

  if not found then
    raise exception 'That request is no longer open.';
  end if;
end
$function$;

revoke all on function public.resolve_teacher_initial(text) from public;
revoke all on function public.student_profile_for_link(uuid) from public;
revoke all on function public.request_teacher_link(text, text) from public;
revoke all on function public.decide_teacher_link(uuid, boolean, text) from public;

grant execute on function public.resolve_teacher_initial(text) to authenticated;
grant execute on function public.student_profile_for_link(uuid) to authenticated;
grant execute on function public.request_teacher_link(text, text) to authenticated;
grant execute on function public.decide_teacher_link(uuid, boolean, text) to authenticated;
