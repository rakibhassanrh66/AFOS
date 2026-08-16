-- What happened under me, in one list. And the IT-staff loop.
--
-- APPLIED 2026-08-16.
--
-- permission_audit has recorded every grant and revoke by trigger since
-- 20260815225127, is append-only, and has no UPDATE or DELETE policy for
-- anyone. It has also never been visible: zero references in lib/. An audit
-- log nobody can read is a log nobody is keeping.
--
-- With decisions now delegated (see 20260816011000), "who did what under me"
-- stops being a curiosity and becomes the thing that makes delegation safe to
-- do at all. This unions the three decision trails that exist:
--
--   permission  -- grants and revokes            (permission_audit)
--   cr          -- CR requests decided, by whom  (cr_requests.reviewed_by)
--   handover    -- items returned, verified or not (lost_found_posts)
--
-- SECURITY DEFINER because it reads across three tables whose own policies are
-- correctly narrower. The gate is the first statement, not the row policies --
-- so this function is the ONLY thing standing between a caller and those rows,
-- and it is written to fail closed.
create or replace function public.authority_activity_log(p_limit int default 200)
returns table (
  kind text, occurred_at timestamptz,
  actor_id uuid, actor_name text,
  subject_id uuid, subject_name text,
  detail text, verified boolean
)
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $function$
begin
  if not (get_my_profile_role() = 'super_admin'
          or caller_can('audit', 'read', auth.uid())) then
    raise exception 'Not authorized to read the activity log.' using errcode = '42501';
  end if;

  return query
  with rows as (
    select 'permission'::text as kind, a.occurred_at, a.actor_id, a.subject_id,
           (a.event || ' ' || a.resource || ':' || a.action)::text as detail,
           null::boolean as verified
      from permission_audit a
    union all
    select 'cr', r.reviewed_at, r.reviewed_by, r.student_id,
           ('CR request ' || r.status || ' for ' || r.batch_label || ' / ' || r.section)::text,
           null::boolean
      from cr_requests r where r.reviewed_at is not null
    union all
    select 'handover', p.returned_at, p.poster_id, p.returned_to,
           (case when p.handover_verified then 'Handover verified by VR-ID scan: '
                 else 'Closed WITHOUT a scan: ' end || coalesce(p.title, 'item'))::text,
           p.handover_verified
      from lost_found_posts p where p.returned_at is not null
  )
  select x.kind, x.occurred_at, x.actor_id, ap.full_name,
         x.subject_id, sp.full_name, x.detail, x.verified
    from rows x
    left join profiles ap on ap.id = x.actor_id
    left join profiles sp on sp.id = x.subject_id
   order by x.occurred_at desc nulls last
   limit greatest(1, least(coalesce(p_limit, 200), 500));
end;
$function$;

revoke all on function public.authority_activity_log(int) from public, anon;
grant execute on function public.authority_activity_log(int) to authenticated;

-- ------------------------------------------------------------------ feedback
-- Today only the author or a super_admin can read a report
-- (own_read_feedback, super_admin_manage_feedback), so "what are people asking
-- for" has no reader unless the owner personally looks. feedback:triage is the
-- collect-and-note loop: read everything, set where it stands, write a reply
-- the author sees.
-- Deliberately NO new status column: manage_feedback_screen already drives
-- `status` (new / reviewed / actioned), and a parallel triage_status would be
-- a second source of truth for the same question -- which is how two statuses
-- end up disagreeing. The REPLY is the part that was genuinely missing: a
-- report could be marked actioned without the person who sent it ever being
-- told anything.
alter table public.feedback add column if not exists triage_note text;
alter table public.feedback add column if not exists triaged_by uuid
  references public.profiles(id) on delete set null;
alter table public.feedback add column if not exists triaged_at timestamptz;

create policy feedback_triage_read on public.feedback
  for select to authenticated
  using (caller_can('feedback','triage',(select auth.uid())));

create policy feedback_triage_update on public.feedback
  for update to authenticated
  using (caller_can('feedback','triage',(select auth.uid())))
  with check (caller_can('feedback','triage',(select auth.uid())));

-- VERIFIED after applying:
--   * as super_admin, authority_activity_log(500) returned 9 rows;
--   * as a plain student (role='student') via set_config on
--     request.jwt.claims -> ERROR: Not authorized to read the activity log.
