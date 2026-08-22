-- 004_manage_users_segmentation.sql
--
-- APPLIED 2026-08-16. Kept as the reviewed proposal it was; the authoritative
-- copy is supabase/migrations/20260816190500_manage_users_segmentation.sql and
-- any further change belongs in a NEW migration, never in this file.
--
-- Originally: PROPOSED — NOT APPLIED.
--
-- WHY
-- ---
-- manage_users_screen.dart:223 does this:
--
--   from('profiles').select('id, full_name, email, ... , created_at')
--     .order('created_at', ascending: false)          -- no .limit()
--
-- and then filters and searches CLIENT-SIDE in Dart (_filtered, line 319).
-- Every profile in the university is downloaded on every screen open, and
-- again on every realtime profiles change (the subscription at line 200 calls
-- _load on ANY insert/update/delete). At 12 users that is invisible. At 25,000
-- it is tens of megabytes per admin per session, an unbounded ListView
-- (banned outright by CLAUDE.md), and a search box that cannot find anyone the
-- client did not already download.
--
-- These two functions move the work to the database:
--   admin_user_facets  — the counts that drive the drill-down UI
--   admin_search_users — one page of rows, keyset-paginated
--
-- KNOWN GAP, DELIBERATELY NOT FAKED. The requested drill-down included intake
-- term (Spring / Summer / Fall). No such column exists: students has
-- batch_label, section, current_semester_no and batch_id; batches has
-- name + a start_year that is NULL on all three rows; semesters models the
-- ACADEMIC term, not a student's intake. Faceting on a term today would mean
-- inventing the data. The honest fix is one column —
--   alter table students add column intake_term text
--     check (intake_term in ('spring','summer','fall'));
-- plus a backfill from the university roster — which is proposed separately
-- rather than smuggled in here.

-- ---------------------------------------------------------------------------
-- Indexes. Without these both functions are sequential scans and this change
-- makes things WORSE, not better, at scale.
-- ---------------------------------------------------------------------------
create extension if not exists pg_trgm;

create index if not exists profiles_role_verified_idx on profiles (role, is_verified);
create index if not exists profiles_batch_idx         on profiles (batch)  where batch is not null;
create index if not exists profiles_section_idx       on profiles (section) where section is not null;
create index if not exists profiles_department_id_idx on profiles (department_id);
create index if not exists profiles_created_keyset_idx on profiles (created_at desc, id desc);

-- The express lane. An admin who knows the ID types it and lands on the record
-- without touching a single facet — the 90% case.
create index if not exists profiles_university_id_idx on profiles (upper(university_id));
create index if not exists profiles_email_lower_idx   on profiles (lower(email));

-- Fuzzy name search. ILIKE '%x%' cannot use a btree index; trigram can.
create index if not exists profiles_full_name_trgm_idx on profiles using gin (full_name gin_trgm_ops);

-- ---------------------------------------------------------------------------
-- Shared authorisation guard
-- ---------------------------------------------------------------------------
create or replace function public.can_browse_users()
returns boolean
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
  select exists (
      select 1 from profiles
       where id = auth.uid() and role in ('super_admin', 'admin', 'dept_admin')
    ) or has_permission('users', 'approve', 'all');
$$;

-- ---------------------------------------------------------------------------
-- Facet counts
-- ---------------------------------------------------------------------------
-- Returns only the facets that make sense at the current level: batches and
-- sections for students, designations for teachers, offices for staff. The UI
-- renders whatever comes back, so adding a facet later needs no client change.
create or replace function public.admin_user_facets(
  p_role          text    default null,
  p_batch         text    default null,
  p_section       text    default null,
  p_department_id uuid    default null,
  p_semester      int     default null,
  p_verified      boolean default null,
  p_q             text    default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_q text := nullif(btrim(coalesce(p_q, '')), '');
  v_result jsonb;
begin
  if not can_browse_users() then
    raise exception 'Not authorized to browse users' using errcode = '42501';
  end if;

  with base as (
    select p.*
      from profiles p
     where (p_role          is null or p.role          = p_role)
       and (p_batch         is null or p.batch         = p_batch)
       and (p_section       is null or p.section       = p_section)
       and (p_department_id is null or p.department_id = p_department_id)
       and (p_semester      is null or p.semester      = p_semester)
       and (p_verified      is null or p.is_verified   = p_verified)
       and (
         v_q is null
         or upper(p.university_id) like upper(v_q) || '%'
         or lower(p.email)         like lower(v_q) || '%'
         or p.full_name ilike '%' || v_q || '%'
       )
  )
  select jsonb_build_object(
    'total',   (select count(*) from base),
    'pending', (select count(*) from base where is_verified is not true),

    -- Role counts deliberately ignore p_role: the role chips must keep showing
    -- every option and its size even once one is selected, or the admin cannot
    -- see where else to go.
    'roles', coalesce((
      select jsonb_agg(x order by x->>'value')
        from (
          select jsonb_build_object('value', p.role, 'count', count(*)) as x
            from profiles p
           where (p_verified is null or p.is_verified = p_verified)
           group by p.role
        ) s
    ), '[]'::jsonb),

    'batches', case when p_role = 'student' then coalesce((
      select jsonb_agg(x order by x->>'value' desc)
        from (
          select jsonb_build_object('value', b.batch, 'count', count(*)) as x
            from base b where b.batch is not null group by b.batch
        ) s
    ), '[]'::jsonb) else '[]'::jsonb end,

    'sections', case when p_role = 'student' then coalesce((
      select jsonb_agg(x order by x->>'value')
        from (
          select jsonb_build_object('value', b.section, 'count', count(*)) as x
            from base b where b.section is not null group by b.section
        ) s
    ), '[]'::jsonb) else '[]'::jsonb end,

    'semesters', case when p_role = 'student' then coalesce((
      select jsonb_agg(x order by (x->>'value')::int)
        from (
          select jsonb_build_object('value', b.semester, 'count', count(*)) as x
            from base b where b.semester is not null group by b.semester
        ) s
    ), '[]'::jsonb) else '[]'::jsonb end,

    'departments', coalesce((
      select jsonb_agg(x order by x->>'label')
        from (
          select jsonb_build_object(
                   'value', b.department_id,
                   'label', coalesce(d.code, d.name, b.department),
                   'count', count(*)
                 ) as x
            from base b
            left join departments d on d.id = b.department_id
           where b.department_id is not null
           group by b.department_id, d.code, d.name, b.department
        ) s
    ), '[]'::jsonb),

    'designations', case when p_role in ('teacher','staff') then coalesce((
      select jsonb_agg(x order by x->>'value')
        from (
          select jsonb_build_object('value', dg, 'count', count(*)) as x
            from (
              select coalesce(t.designation, st.designation) as dg
                from base b
                left join teachers t on t.profile_id = b.id
                left join staff    st on st.profile_id = b.id
            ) j
           where dg is not null
           group by dg
        ) s
    ), '[]'::jsonb) else '[]'::jsonb end,

    'offices', case when p_role = 'staff' then coalesce((
      select jsonb_agg(x order by x->>'value')
        from (
          select jsonb_build_object('value', st.office, 'count', count(*)) as x
            from base b join staff st on st.profile_id = b.id
           where st.office is not null
           group by st.office
        ) s
    ), '[]'::jsonb) else '[]'::jsonb end
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.admin_user_facets(text,text,text,uuid,int,boolean,text) from public, anon;
grant execute on function public.admin_user_facets(text,text,text,uuid,int,boolean,text) to authenticated;

-- ---------------------------------------------------------------------------
-- One page of rows
-- ---------------------------------------------------------------------------
-- Keyset, not OFFSET. OFFSET re-walks every skipped row, so page 40 of a batch
-- listing costs forty times page 1. (created_at desc, id desc) is unique and
-- matches profiles_created_keyset_idx, so every page costs the same.
create or replace function public.admin_search_users(
  p_role          text    default null,
  p_batch         text    default null,
  p_section       text    default null,
  p_department_id uuid    default null,
  p_semester      int     default null,
  p_verified      boolean default null,
  p_q             text    default null,
  p_limit         int     default 50,
  p_cursor_created_at timestamptz default null,
  p_cursor_id     uuid    default null
)
returns table (
  id uuid, full_name text, email text, phone text, role text,
  university_id text, department text, batch text, section text,
  semester int, teacher_initial text, gender text, emergency_contact text,
  avatar_url text, is_verified boolean, identity_source text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare
  v_q text := nullif(btrim(coalesce(p_q, '')), '');
  v_limit int := greatest(1, least(coalesce(p_limit, 50), 200));
begin
  if not can_browse_users() then
    raise exception 'Not authorized to browse users' using errcode = '42501';
  end if;

  return query
  select p.id, p.full_name, p.email, p.phone, p.role,
         p.university_id, p.department, p.batch, p.section,
         p.semester, p.teacher_initial, p.gender, p.emergency_contact,
         p.avatar_url, p.is_verified, p.identity_source,
         p.created_at
    from profiles p
   where (p_role          is null or p.role          = p_role)
     and (p_batch         is null or p.batch         = p_batch)
     and (p_section       is null or p.section       = p_section)
     and (p_department_id is null or p.department_id = p_department_id)
     and (p_semester      is null or p.semester      = p_semester)
     and (p_verified      is null or p.is_verified   = p_verified)
     and (
       v_q is null
       or upper(p.university_id) like upper(v_q) || '%'
       or lower(p.email)         like lower(v_q) || '%'
       or p.full_name ilike '%' || v_q || '%'
     )
     -- Row-value comparison, so the planner can use the composite index
     -- directly instead of decomposing this into an OR.
     and (
       p_cursor_created_at is null
       or (p.created_at, p.id) < (p_cursor_created_at, p_cursor_id)
     )
   order by p.created_at desc, p.id desc
   limit v_limit;
end;
$$;

revoke all on function public.admin_search_users(text,text,text,uuid,int,boolean,text,int,timestamptz,uuid) from public, anon;
grant execute on function public.admin_search_users(text,text,text,uuid,int,boolean,text,int,timestamptz,uuid) to authenticated;
