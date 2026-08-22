-- A facet split itself in two because of letter case.
--
-- Found by exercising admin_user_facets against real data: the teacher
-- designation facet returned
--
--   lecturer (1)      Lecturer (2)
--
-- as two separate chips. They are one designation. An admin filtering by
-- "Lecturer" would silently miss a third of the lecturers, and the counts
-- add up to something that matches no real group. The same hazard applies to
-- staff offices, which are free text typed by whoever created the account.
--
-- Grouping is now case-insensitive. The LABEL shown is mode() — the most
-- common real spelling in the data — rather than initcap(), because
-- initcap('CSE Exam Controler') would render 'Cse Exam Controler' and make
-- correct data look like a typo. Sections are upper-cased for the same reason:
-- handle_new_user() normalises them on the signup path, but nothing guarantees
-- that for rows written by any other route.
--
-- Only the facet labels change. admin_search_users still filters on the stored
-- value, so a chip's value must remain a real stored value — which mode()
-- guarantees and initcap() would not.

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
       and (p_section       is null or upper(p.section) = upper(p_section))
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

    -- Upper-cased: 'a' and 'A' are the same section.
    'sections', case when p_role = 'student' then coalesce((
      select jsonb_agg(x order by x->>'value')
        from (
          select jsonb_build_object('value', upper(b.section), 'count', count(*)) as x
            from base b where b.section is not null group by upper(b.section)
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

    -- Grouped on lower(), labelled with the commonest real spelling.
    'designations', case when p_role in ('teacher','staff') then coalesce((
      select jsonb_agg(x order by x->>'value')
        from (
          select jsonb_build_object(
                   'value', mode() within group (order by dg),
                   'count', count(*)
                 ) as x
            from (
              select coalesce(t.designation, st.designation) as dg
                from base b
                left join teachers t  on t.profile_id  = b.id
                left join staff    st on st.profile_id = b.id
            ) j
           where dg is not null and btrim(dg) <> ''
           group by lower(btrim(dg))
        ) s
    ), '[]'::jsonb) else '[]'::jsonb end,

    'offices', case when p_role = 'staff' then coalesce((
      select jsonb_agg(x order by x->>'value')
        from (
          select jsonb_build_object(
                   'value', mode() within group (order by st.office),
                   'count', count(*)
                 ) as x
            from base b join staff st on st.profile_id = b.id
           where st.office is not null and btrim(st.office) <> ''
           group by lower(btrim(st.office))
        ) s
    ), '[]'::jsonb) else '[]'::jsonb end
  ) into v_result;

  return v_result;
end;
$$;

revoke all on function public.admin_user_facets(text,text,text,uuid,int,boolean,text) from public, anon;
grant execute on function public.admin_user_facets(text,text,text,uuid,int,boolean,text) to authenticated;

-- The search side must agree with the facet side, or clicking a section chip
-- returns nothing for the rows that differ only in case.
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
     and (p_section       is null or upper(p.section) = upper(p_section))
     and (p_department_id is null or p.department_id = p_department_id)
     and (p_semester      is null or p.semester      = p_semester)
     and (p_verified      is null or p.is_verified   = p_verified)
     and (
       v_q is null
       or upper(p.university_id) like upper(v_q) || '%'
       or lower(p.email)         like lower(v_q) || '%'
       or p.full_name ilike '%' || v_q || '%'
     )
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
