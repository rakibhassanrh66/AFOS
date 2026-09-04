-- =====================================================================
--  Advising and FYDP supervision — the pairing, the thread, availability.
--
--  ONE mechanism, two kinds. An advisor pairing and a final-year-project
--  supervision are the same row with a different `kind`, so there is one
--  lifecycle, one thread table, one privacy gate and one set of policies
--  rather than two that drift.
--
--  Assignment is CLAIM AND ACCEPT: the student names a teacher by initial,
--  the teacher answers. There are deliberately NO roll-number ranges —
--  university_id carries six different shapes in this database (16-digit,
--  NNN-NN-NNNN, 13-, 15-, 14- and 8-digit), and batch 63 alone holds two of
--  them, so any numeric range would silently omit students with no error
--  anywhere. Nothing here parses an ID.
-- =====================================================================

-- ---------------------------------------------------------------- pairing
create table if not exists public.teacher_links (
  id            uuid primary key default gen_random_uuid(),
  student_id    uuid not null references public.profiles(id) on delete cascade,
  teacher_id    uuid not null references public.profiles(id) on delete cascade,
  kind          text not null check (kind in ('advisor', 'fydp')),
  status        text not null default 'pending'
                  check (status in ('pending', 'active', 'declined', 'ended')),
  requested_at  timestamptz not null default now(),
  decided_at    timestamptz,
  decline_reason text,
  ended_at      timestamptz,
  ended_by      uuid references public.profiles(id),
  constraint teacher_links_not_self check (student_id <> teacher_id)
);

-- A student may hold only ONE live link per kind. Partial, so a declined or
-- ended row never blocks a fresh request — which is the difference between
-- "try a different teacher" and "permanently stuck after one decline".
create unique index if not exists teacher_links_one_live_per_kind
  on public.teacher_links (student_id, kind)
  where status in ('pending', 'active');

-- The teacher's own queue is the hot read: "everything waiting on me".
create index if not exists teacher_links_teacher_status_idx
  on public.teacher_links (teacher_id, status);
create index if not exists teacher_links_student_idx
  on public.teacher_links (student_id);

alter table public.teacher_links enable row level security;

drop policy if exists teacher_links_student_reads_own on public.teacher_links;
create policy teacher_links_student_reads_own on public.teacher_links
  for select to authenticated
  using (student_id = (select auth.uid()));

drop policy if exists teacher_links_teacher_reads_own on public.teacher_links;
create policy teacher_links_teacher_reads_own on public.teacher_links
  for select to authenticated
  using (teacher_id = (select auth.uid()));

drop policy if exists teacher_links_admin_reads_all on public.teacher_links;
create policy teacher_links_admin_reads_all on public.teacher_links
  for select to authenticated
  using (can_browse_users());

drop policy if exists teacher_links_student_requests on public.teacher_links;
create policy teacher_links_student_requests on public.teacher_links
  for insert to authenticated
  with check (student_id = (select auth.uid()) or can_browse_users());

-- The row-level transition rules live in the trigger below, not here: a
-- policy can say WHO may write, but "pending may become active only at the
-- teacher's hand" is about the shape of the change, and expressing that in
-- USING/WITH CHECK produces something nobody can read six months later.
drop policy if exists teacher_links_parties_update on public.teacher_links;
create policy teacher_links_parties_update on public.teacher_links
  for update to authenticated
  using (student_id = (select auth.uid())
         or teacher_id = (select auth.uid())
         or can_browse_users());

-- ------------------------------------------------------ transition guard
create or replace function public.tg_teacher_links_guard()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_me    uuid := auth.uid();
  v_admin boolean := can_browse_users();
begin
  if TG_OP = 'INSERT' then
    if not v_admin then
      if new.student_id is distinct from v_me then
        raise exception 'You can only request a teacher for your own account.'
          using errcode = '42501';
      end if;
      if new.status <> 'pending' then
        raise exception 'A new request starts as pending.'
          using errcode = '42501';
      end if;
    end if;

    if not exists (select 1 from profiles p
                    where p.id = new.teacher_id and p.role = 'teacher') then
      raise exception 'That initial does not belong to a teacher.';
    end if;
    if not exists (select 1 from profiles p
                    where p.id = new.student_id and p.role = 'student') then
      raise exception 'Only a student account can be advised.';
    end if;
    return new;
  end if;

  -- The pairing itself is immutable. Re-pointing a live link at a different
  -- student would silently move one person's profile access to another.
  if new.student_id is distinct from old.student_id
     or new.teacher_id is distinct from old.teacher_id
     or new.kind is distinct from old.kind then
    raise exception 'A link cannot be re-pointed. End it and make a new one.'
      using errcode = '42501';
  end if;

  if v_admin then
    return new;
  end if;

  if old.status = new.status then
    return new;
  end if;

  -- pending -> active | declined : the named teacher answers.
  if old.status = 'pending' and new.status in ('active', 'declined') then
    if v_me is distinct from old.teacher_id then
      raise exception 'Only the teacher named on this request can answer it.'
        using errcode = '42501';
    end if;
    new.decided_at := now();
    return new;
  end if;

  -- pending -> ended : the student withdraws before an answer.
  if old.status = 'pending' and new.status = 'ended' then
    if v_me is distinct from old.student_id then
      raise exception 'Only the student who asked can withdraw the request.'
        using errcode = '42501';
    end if;
    new.ended_at := now();
    new.ended_by := v_me;
    return new;
  end if;

  -- active -> ended : either party may release it.
  if old.status = 'active' and new.status = 'ended' then
    if v_me is distinct from old.student_id and v_me is distinct from old.teacher_id then
      raise exception 'Only the student or the teacher can end this.'
        using errcode = '42501';
    end if;
    new.ended_at := now();
    new.ended_by := v_me;
    return new;
  end if;

  raise exception 'A % link cannot go from % to %.', old.kind, old.status, new.status
    using errcode = '42501';
end
$function$;

drop trigger if exists trg_teacher_links_guard on public.teacher_links;
create trigger trg_teacher_links_guard
  before insert or update on public.teacher_links
  for each row execute function public.tg_teacher_links_guard();

-- ----------------------------------------------------------------- thread
create table if not exists public.teacher_link_messages (
  id         bigserial primary key,
  link_id    uuid not null references public.teacher_links(id) on delete cascade,
  sender_id  uuid not null references public.profiles(id) on delete cascade,
  body       text not null check (length(btrim(body)) between 1 and 4000),
  created_at timestamptz not null default now(),
  read_at    timestamptz
);

create index if not exists teacher_link_messages_link_idx
  on public.teacher_link_messages (link_id, created_at);

alter table public.teacher_link_messages enable row level security;

-- Only the two parties of an ACTIVE link. A pending request grants no thread,
-- which is the same rule that stops it granting a profile.
drop policy if exists teacher_link_messages_parties_read on public.teacher_link_messages;
create policy teacher_link_messages_parties_read on public.teacher_link_messages
  for select to authenticated
  using (exists (select 1 from public.teacher_links l
                  where l.id = teacher_link_messages.link_id
                    and l.status = 'active'
                    and (select auth.uid()) in (l.student_id, l.teacher_id)));

drop policy if exists teacher_link_messages_parties_write on public.teacher_link_messages;
create policy teacher_link_messages_parties_write on public.teacher_link_messages
  for insert to authenticated
  with check (sender_id = (select auth.uid())
              and exists (select 1 from public.teacher_links l
                           where l.id = teacher_link_messages.link_id
                             and l.status = 'active'
                             and (select auth.uid()) in (l.student_id, l.teacher_id)));

-- ----------------------------------------------------------- availability
create table if not exists public.teacher_office_hours (
  id          uuid primary key default gen_random_uuid(),
  teacher_id  uuid not null references public.profiles(id) on delete cascade,
  day_of_week int not null check (day_of_week between 0 and 6),
  start_time  time not null,
  end_time    time not null,
  note        text,
  constraint teacher_office_hours_ordered check (end_time > start_time)
);
create index if not exists teacher_office_hours_teacher_idx
  on public.teacher_office_hours (teacher_id, day_of_week);

create table if not exists public.teacher_leave (
  id         uuid primary key default gen_random_uuid(),
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  starts_on  date not null,
  ends_on    date not null,
  reason     text,
  constraint teacher_leave_ordered check (ends_on >= starts_on)
);
create index if not exists teacher_leave_teacher_idx
  on public.teacher_leave (teacher_id, starts_on);

alter table public.teacher_office_hours enable row level security;
alter table public.teacher_leave enable row level security;

-- When a teacher is available is not private — a student choosing an advisor
-- needs it before any link exists, which is the whole point of showing it on
-- the resolved card.
drop policy if exists teacher_office_hours_read on public.teacher_office_hours;
create policy teacher_office_hours_read on public.teacher_office_hours
  for select to authenticated using (true);

drop policy if exists teacher_office_hours_owner_writes on public.teacher_office_hours;
create policy teacher_office_hours_owner_writes on public.teacher_office_hours
  for all to authenticated
  using (teacher_id = (select auth.uid()) or can_browse_users())
  with check (teacher_id = (select auth.uid()) or can_browse_users());

drop policy if exists teacher_leave_read on public.teacher_leave;
create policy teacher_leave_read on public.teacher_leave
  for select to authenticated using (true);

drop policy if exists teacher_leave_owner_writes on public.teacher_leave;
create policy teacher_leave_owner_writes on public.teacher_leave
  for all to authenticated
  using (teacher_id = (select auth.uid()) or can_browse_users())
  with check (teacher_id = (select auth.uid()) or can_browse_users());
