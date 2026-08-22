-- Who may run an import at all. One definition, used by every function here.
create or replace function can_manage_uploads()
returns boolean
language sql
stable
security definer
set search_path = public
as $fn$
  select exists (
    select 1 from profiles p
    where p.id = (select auth.uid()) and p.is_verified
      and (p.role = any (array['admin','dept_admin','super_admin','exam_controller'])
           or caller_can('routine','upload')
           or caller_can('transport','upload')
           or caller_can('exam_seat','upload')
           or caller_can('notice','publish'))
  );
$fn$;

-- Opened BEFORE the import runs, so the rows can carry the id as they are
-- written. A batch that is never finalised stays 'pending' and shows in the
-- history as an import that did not complete -- which is information, not a
-- defect to hide.
create or replace function record_upload_batch(
  p_kind        text,
  p_source_file text default null,
  p_department  text default null,
  p_term_id     uuid default null,
  p_note        text default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  new_id uuid;
begin
  if not can_manage_uploads() then
    raise exception 'Not permitted to upload' using errcode = '42501';
  end if;

  insert into upload_batches (kind, source_file, department, term_id, uploaded_by, note)
  values (p_kind, nullif(btrim(p_source_file), ''), nullif(btrim(p_department), ''),
          p_term_id, (select auth.uid()), nullif(btrim(p_note), ''))
  returning id into new_id;

  return new_id;
end;
$fn$;

-- Closed after the rows are in. row_count is COUNTED from the stamped rows
-- rather than believed from the caller: the client's idea of how many rows it
-- sent is not evidence of how many survived RLS and constraints.
create or replace function finalize_upload_batch(
  p_id      uuid,
  p_summary jsonb default '{}'::jsonb
) returns upload_batches
language plpgsql
security definer
set search_path = public
as $fn$
declare
  b upload_batches;
  n integer;
begin
  if not can_manage_uploads() then
    raise exception 'Not permitted to upload' using errcode = '42501';
  end if;

  select
      (select count(*) from exam_room_allocations where upload_batch_id = p_id)
    + (select count(*) from exams                 where upload_batch_id = p_id)
    + (select count(*) from schedule_slots        where upload_batch_id = p_id)
    + (select count(*) from notices               where upload_batch_id = p_id)
    + (select count(*) from transport_routes      where upload_batch_id = p_id)
    + (select count(*) from transport_stops       where upload_batch_id = p_id)
  into n;

  update upload_batches
     set row_count = n,
         summary   = coalesce(p_summary, '{}'::jsonb),
         status    = 'applied'
   where id = p_id
  returning * into b;

  if b.id is null then
    raise exception 'No such upload batch';
  end if;
  return b;
end;
$fn$;

-- Everything one batch wrote, for the backup PDF. Returned as jsonb so one
-- call covers all six tables and the client does not need read access to each.
create or replace function upload_batch_contents(p_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
declare
  b upload_batches;
begin
  if not can_manage_uploads() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  select * into b from upload_batches where id = p_id;
  if b.id is null then
    raise exception 'No such upload batch';
  end if;

  return jsonb_build_object(
    'batch', to_jsonb(b),
    'uploader', (select p.full_name from profiles p where p.id = b.uploaded_by),
    'exam_room_allocations', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.exam_date, x.course_code, x.section, x.room_no)
      from exam_room_allocations x where x.upload_batch_id = p_id), '[]'::jsonb),
    'exams', coalesce((
      select jsonb_agg(to_jsonb(x) order by x.exam_date, x.subject_code)
      from exams x where x.upload_batch_id = p_id), '[]'::jsonb),
    'schedule_slots', coalesce((
      select jsonb_agg(to_jsonb(x)) from schedule_slots x where x.upload_batch_id = p_id), '[]'::jsonb),
    'notices', coalesce((
      select jsonb_agg(to_jsonb(x)) from notices x where x.upload_batch_id = p_id), '[]'::jsonb),
    'transport_routes', coalesce((
      select jsonb_agg(to_jsonb(x)) from transport_routes x where x.upload_batch_id = p_id), '[]'::jsonb),
    'transport_stops', coalesce((
      select jsonb_agg(to_jsonb(x)) from transport_stops x where x.upload_batch_id = p_id), '[]'::jsonb)
  );
end;
$fn$;

create or replace function mark_upload_backup_generated(p_id uuid, p_path text)
returns upload_batches
language plpgsql
security definer
set search_path = public
as $fn$
declare
  b upload_batches;
begin
  if not can_manage_uploads() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  update upload_batches
     set backup_path = p_path, backup_generated_at = now()
   where id = p_id
  returning * into b;

  if b.id is null then
    raise exception 'No such upload batch';
  end if;
  return b;
end;
$fn$;

-- Deletes exactly the rows this batch wrote, and refuses until a backup has
-- been generated.
--
-- The interlock is deliberately a SAFETY one, not a security one: the server
-- can only know that a backup was produced and stored, never that a person
-- downloaded it. It exists to stop the ordinary accident -- freeing storage
-- and discovering afterwards that the term's seat plan is gone.
create or replace function revert_upload_batch(p_id uuid)
returns upload_batches
language plpgsql
security definer
set search_path = public
as $fn$
declare
  b upload_batches;
  removed integer := 0;
  n integer;
begin
  if not can_manage_uploads() then
    raise exception 'Not permitted to remove an upload' using errcode = '42501';
  end if;

  select * into b from upload_batches where id = p_id for update;
  if b.id is null then
    raise exception 'No such upload batch';
  end if;
  if b.status = 'reverted' then
    raise exception 'That upload has already been removed';
  end if;
  if b.backup_generated_at is null then
    raise exception 'Download the backup before removing this upload';
  end if;

  delete from exam_room_allocations where upload_batch_id = p_id;
  get diagnostics n = row_count; removed := removed + n;
  delete from exams                 where upload_batch_id = p_id;
  get diagnostics n = row_count; removed := removed + n;
  delete from schedule_slots        where upload_batch_id = p_id;
  get diagnostics n = row_count; removed := removed + n;
  delete from notices               where upload_batch_id = p_id;
  get diagnostics n = row_count; removed := removed + n;
  -- Stops before routes: a stop points at its route.
  delete from transport_stops       where upload_batch_id = p_id;
  get diagnostics n = row_count; removed := removed + n;
  delete from transport_routes      where upload_batch_id = p_id;
  get diagnostics n = row_count; removed := removed + n;

  update upload_batches
     set status = 'reverted',
         reverted_at = now(),
         reverted_by = (select auth.uid()),
         summary = summary || jsonb_build_object('rowsRemoved', removed)
   where id = p_id
  returning * into b;

  return b;
end;
$fn$;

-- The history list, with the uploader's name resolved (the client has no read
-- access to other people's profiles).
create or replace function list_upload_batches(p_limit integer default 50)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $fn$
begin
  if not can_manage_uploads() then
    raise exception 'Not permitted' using errcode = '42501';
  end if;

  return coalesce((
    select jsonb_agg(row order by (row->>'uploaded_at') desc)
    from (
      select to_jsonb(b) || jsonb_build_object(
               'uploader', coalesce(p.full_name, p.email, 'Unknown'),
               'reverter', rp.full_name
             ) as row
      from upload_batches b
      left join profiles p  on p.id  = b.uploaded_by
      left join profiles rp on rp.id = b.reverted_by
      order by b.uploaded_at desc
      limit greatest(1, least(coalesce(p_limit, 50), 200))
    ) s
  ), '[]'::jsonb);
end;
$fn$;

revoke all on function can_manage_uploads()            from anon;
revoke all on function record_upload_batch(text,text,text,uuid,text) from anon;
revoke all on function finalize_upload_batch(uuid,jsonb)  from anon;
revoke all on function upload_batch_contents(uuid)        from anon;
revoke all on function mark_upload_backup_generated(uuid,text) from anon;
revoke all on function revert_upload_batch(uuid)          from anon;
revoke all on function list_upload_batches(integer)       from anon;
