-- An examination period, as the routine PDF header actually states it:
-- "Final Examination Routine, Summer 2026". None of that was stored anywhere.
-- `exams.exam_type` held the bare string 'mid' for all 38 rows and there was no
-- season, no year, and no window -- so the app could not answer "which exams
-- are these", let alone "is the exam period over yet".
create table if not exists public.exam_terms (
  id           uuid primary key default gen_random_uuid(),
  exam_type    text not null check (exam_type in ('mid','final','retake','improvement')),
  season       text not null check (season in ('spring','summer','fall')),
  year         int  not null check (year between 2000 and 2100),
  department   text,
  -- The first and last exam date in the routine. This is what decides when the
  -- dashboard countdown starts blinking and, more importantly, when it STOPS:
  -- a finished exam period must disappear for students rather than sit there
  -- advertising a date that has passed.
  starts_on    date,
  ends_on      date,
  source_file  text,
  uploaded_by  uuid references public.profiles(id) on delete set null,
  uploaded_at  timestamptz not null default now(),
  -- Parsed but not yet released. An import lands unpublished so a human can
  -- look at it before every student's dashboard starts announcing it.
  published    boolean not null default false
);

-- One live term per type+season+year+department. COALESCE because a
-- university-wide routine has no department, and NULL never equals NULL in a
-- unique index -- which would silently allow duplicate university-wide terms.
create unique index if not exists exam_terms_identity
  on public.exam_terms (exam_type, season, year, coalesce(department, ''));

alter table public.exams
  add column if not exists term_id    uuid references public.exam_terms(id) on delete cascade,
  add column if not exists slot_label text;

create index if not exists exams_term_idx  on public.exams (term_id);
create index if not exists exams_batch_idx on public.exams (batch, exam_date);

alter table public.exam_room_allocations
  add column if not exists term_id uuid references public.exam_terms(id) on delete cascade;

create index if not exists exam_alloc_term_idx on public.exam_room_allocations (term_id);
-- The join a student's "where do I sit" question actually runs.
create index if not exists exam_alloc_lookup_idx
  on public.exam_room_allocations (exam_date, slot_label, batch, section);
-- ...and the teacher's "where is my duty" question.
create index if not exists exam_alloc_teacher_idx
  on public.exam_room_allocations (teacher_initial, exam_date);

alter table public.exam_terms enable row level security;

-- Readable by any signed-in user: a student must be able to see that a final
-- exam period exists. Publication is what gates whether the UI shows it, and
-- that is a column, not a policy -- an unpublished term is still visible to
-- the admin screens that have to review it.
drop policy if exists auth_read_exam_terms on public.exam_terms;
create policy auth_read_exam_terms on public.exam_terms
  for select to authenticated using (true);

-- Same authority set as exam_room_allocations already uses, so uploading a
-- routine and uploading a seat plan need the same standing.
drop policy if exists admin_write_exam_terms on public.exam_terms;
create policy admin_write_exam_terms on public.exam_terms
  for all to authenticated
  using (
    exists (select 1 from public.profiles p
             where p.id = (select auth.uid()) and p.is_verified
               and (p.role = any (array['admin','dept_admin','super_admin','exam_controller'])
                    or caller_can('routine','upload')
                    or caller_can('exam_seat','upload')))
  );

-- THE POLICY exams NEVER HAD. It carried `auth_read_exams` (select true) and
-- no write policy whatsoever, so with RLS on, every insert from the app was
-- refused -- silently, because RLS filters rather than errors. The 38 rows in
-- there were written by something bypassing RLS. A routine upload screen could
-- not have worked no matter how good the parser was.
drop policy if exists admin_write_exams on public.exams;
create policy admin_write_exams on public.exams
  for all to authenticated
  using (
    exists (select 1 from public.profiles p
             where p.id = (select auth.uid()) and p.is_verified
               and (p.role = any (array['admin','dept_admin','super_admin','exam_controller'])
                    or caller_can('routine','upload')
                    or caller_can('exam_seat','upload')))
  );

comment on table public.exam_terms is
  'One examination period (type + season + year + department), parsed from the routine PDF header.';
