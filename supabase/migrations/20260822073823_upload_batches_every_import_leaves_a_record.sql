-- One record per import made through the app, whatever kind it is.
--
-- `routine_uploads` already existed but described only routines, held one row,
-- and recorded nothing about WHAT was written -- so it could not answer "who
-- put these 1767 rows here" or "remove exactly what that upload added".
create table if not exists upload_batches (
  id uuid primary key default gen_random_uuid(),
  kind text not null check (kind in
    ('class_routine','exam_routine','exam_seat_plan','transport','notice')),
  source_file text,
  department text,
  term_id uuid references exam_terms(id) on delete set null,
  row_count integer not null default 0,
  -- Whatever the uploader should see later: dates covered, courses, sections.
  summary jsonb not null default '{}'::jsonb,
  uploaded_by uuid references profiles(id) on delete set null,
  uploaded_at timestamptz not null default now(),
  status text not null default 'pending'
    check (status in ('pending','applied','reverted')),
  -- The backup PDF taken before a revert. Named honestly: the server can know
  -- a backup was GENERATED, never that a human downloaded it.
  backup_path text,
  backup_generated_at timestamptz,
  reverted_at timestamptz,
  reverted_by uuid references profiles(id) on delete set null,
  note text
);

create index if not exists upload_batches_recent_idx
  on upload_batches (uploaded_at desc);
create index if not exists upload_batches_kind_idx
  on upload_batches (kind, uploaded_at desc);

-- Every row an import writes carries the batch that wrote it, so a revert
-- deletes EXACTLY what that upload added rather than re-deriving it from a
-- date range and hoping. Nullable throughout: everything already in these
-- tables predates the idea and must stay.
alter table exam_room_allocations
  add column if not exists upload_batch_id uuid references upload_batches(id) on delete set null;
alter table exams
  add column if not exists upload_batch_id uuid references upload_batches(id) on delete set null;
alter table schedule_slots
  add column if not exists upload_batch_id uuid references upload_batches(id) on delete set null;
alter table notices
  add column if not exists upload_batch_id uuid references upload_batches(id) on delete set null;
alter table transport_routes
  add column if not exists upload_batch_id uuid references upload_batches(id) on delete set null;
alter table transport_stops
  add column if not exists upload_batch_id uuid references upload_batches(id) on delete set null;

create index if not exists exam_room_allocations_batch_idx on exam_room_allocations (upload_batch_id);
create index if not exists exams_batch_idx on exams (upload_batch_id);
create index if not exists schedule_slots_batch_idx on schedule_slots (upload_batch_id);
create index if not exists notices_batch_idx on notices (upload_batch_id);
create index if not exists transport_routes_batch_idx on transport_routes (upload_batch_id);
create index if not exists transport_stops_batch_idx on transport_stops (upload_batch_id);

alter table upload_batches enable row level security;

-- READ for anyone who may upload anything, so the history is visible to the
-- people whose work it records.
drop policy if exists uploaders_read_upload_batches on upload_batches;
create policy uploaders_read_upload_batches on upload_batches
  for select to authenticated
  using (
    exists (
      select 1 from profiles p
      where p.id = (select auth.uid()) and p.is_verified
        and (p.role = any (array['admin','dept_admin','super_admin','exam_controller'])
             or caller_can('routine','upload')
             or caller_can('transport','upload')
             or caller_can('exam_seat','upload')
             or caller_can('notice','publish'))
    )
  );

-- NO write policy, deliberately. Every write goes through the SECURITY DEFINER
-- functions in the next migration, which gate and stamp uploaded_by themselves.
-- This is the opposite of the `exams` mistake -- there a write policy was
-- MISSING by accident and RLS filtered every insert in silence. Here the
-- absence is the design, and the client has a function to call.
comment on table upload_batches is
  'One row per import through the app. Written only via record_upload_batch / '
  'finalize_upload_batch / revert_upload_batch; there is no direct write policy.';
