-- Any student could make themselves Class Representative.
--
-- APPLIED 2026-08-16. Found while adding cr:approve, not reported.
--
-- Two policies met badly:
--   own_student_update:              a student may UPDATE their own students row
--   protect_student_admin_columns:   guarded `status` and `cgpa` only
--
-- `is_cr` lives on that row and was guarded by nothing. One PATCH to
-- /rest/v1/students?profile_id=eq.<self> with {"is_cr": true} skipped the
-- approval queue entirely and granted empty_room_requests insert rights (the
-- one RLS policy that reads is_cr) plus the CR badge in course-group chat.
-- The queue in Manage Users was decorative: the answer never had to come from
-- it. Same shape as the NULL role_id escalation -- a privileged column reachable
-- through an ordinary self-service write path.
--
-- There was also no uniqueness anywhere, so a section could hold any number of
-- CRs, which is the opposite of what "class representative" means.
create or replace function public.protect_student_admin_columns()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
BEGIN
  IF (NEW.status IS DISTINCT FROM OLD.status OR NEW.cgpa IS DISTINCT FROM OLD.cgpa)
     AND NOT has_permission('students', 'all', 'all')
  THEN
    RAISE EXCEPTION 'Not authorized to change status or cgpa.';
  END IF;

  -- auth.uid() IS NULL is the server-side path (service role, migration, the
  -- approve_cr_request RPC's own definer context is NOT this -- it keeps the
  -- caller's uid, which is why cr:approve is checked explicitly).
  IF (NEW.is_cr IS DISTINCT FROM OLD.is_cr OR NEW.cr_since IS DISTINCT FROM OLD.cr_since)
     AND auth.uid() IS NOT NULL
     AND NOT has_permission('students', 'all', 'all')
     AND NOT caller_can('cr', 'approve', auth.uid())
  THEN
    RAISE EXCEPTION 'Class Representative is assigned by approval, not set directly.';
  END IF;

  RETURN NEW;
END;
$function$;

revoke all on function public.protect_student_admin_columns() from public, anon, authenticated;

-- One CR per section, enforced where it cannot be argued with. Partial, so
-- the thousands of non-CR students do not participate in the index at all.
create unique index if not exists students_one_cr_per_section
  on public.students (department_id, batch_label, section)
  where is_cr;

-- Approving is one transaction, not two unguarded client writes.
--
-- manage_users_screen did: UPDATE students SET is_cr -- then -- UPDATE
-- cr_requests SET status. If the second failed, a CR existed whose request was
-- still pending; nothing demoted the previous CR, so the new unique index
-- would have started rejecting the FIRST write with a constraint name. The
-- replacement is the visible behaviour: a new CR replaces the old one.
create or replace function public.approve_cr_request(p_request_id uuid)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_previous uuid;
begin
  select * into r from cr_requests where id = p_request_id;
  if r.id is null then
    raise exception 'That request no longer exists.';
  end if;
  if r.status <> 'pending' then
    raise exception 'That request was already %.', r.status;
  end if;

  if not (get_my_profile_role() = 'super_admin'
          or caller_can('cr', 'approve', auth.uid())) then
    raise exception 'Not authorized to approve Class Representative requests.'
      using errcode = '42501';
  end if;

  select profile_id into v_previous from students
   where department_id = r.department_id
     and batch_label   = r.batch_label
     and section       = r.section
     and is_cr
     and profile_id <> r.student_id
   limit 1;

  if v_previous is not null then
    update students set is_cr = false, cr_since = null where profile_id = v_previous;
  end if;

  update students set is_cr = true, cr_since = now() where profile_id = r.student_id;

  update cr_requests
     set status = 'approved', reviewed_by = auth.uid(), reviewed_at = now()
   where id = p_request_id;

  -- Everyone else waiting in the same section is answered rather than left
  -- pending forever: the seat is taken, and there is only one.
  update cr_requests
     set status = 'superseded', reviewed_by = auth.uid(), reviewed_at = now(),
         rejection_reason = 'Another student was appointed CR for this section.'
   where department_id = r.department_id
     and batch_label   = r.batch_label
     and section       = r.section
     and status = 'pending'
     and id <> p_request_id;
end;
$function$;

create or replace function public.reject_cr_request(p_request_id uuid, p_reason text default null)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record;
begin
  select * into r from cr_requests where id = p_request_id;
  if r.id is null then
    raise exception 'That request no longer exists.';
  end if;
  if r.status <> 'pending' then
    raise exception 'That request was already %.', r.status;
  end if;
  if not (get_my_profile_role() = 'super_admin'
          or caller_can('cr', 'approve', auth.uid())) then
    raise exception 'Not authorized to decide Class Representative requests.'
      using errcode = '42501';
  end if;

  update cr_requests
     set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(),
         rejection_reason = nullif(btrim(coalesce(p_reason, '')), '')
   where id = p_request_id;
end;
$function$;

revoke all on function public.approve_cr_request(uuid) from public, anon;
revoke all on function public.reject_cr_request(uuid, text) from public, anon;
grant execute on function public.approve_cr_request(uuid) to authenticated;
grant execute on function public.reject_cr_request(uuid, text) to authenticated;

-- A cr:approve holder could call the RPC but could not SEE the queue --
-- own_cr_request_read is student-only. Exactly the gap the delegate SELECT
-- policy had the day before; worth noticing that it recurred immediately.
create policy cr_approver_reads_requests
  on public.cr_requests for select to authenticated
  using (caller_can('cr', 'approve', (select auth.uid())));

-- And the student rows behind the queue, to render a name and a section.
create policy cr_approver_reads_students
  on public.students for select to authenticated
  using (caller_can('cr', 'approve', (select auth.uid())));

-- VERIFIED after applying, as a real plain student (role='student') via
-- set_config on request.jwt.claims:
--
--   update students set is_cr = true where profile_id = <self>
--     -> ERROR: Class Representative is assigned by approval, not set directly.
--
-- and the row was confirmed still is_cr = false afterwards.
