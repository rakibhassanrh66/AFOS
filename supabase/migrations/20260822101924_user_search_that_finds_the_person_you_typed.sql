-- Required by profiles_search_trgm_idx below. It was already installed on the
-- live project, which is exactly why it was easy to leave out -- a fresh
-- replay (a Supabase preview branch, a local `db reset`) has no such luck.
create extension if not exists pg_trgm;

-- Admin user search matched only: university_id PREFIX, email PREFIX, and
-- full_name substring. Measured against live data, every one of these
-- returned nothing:
--   teacher initial 'MSK'          -> 0 found, 1 exists
--   mid-fragment of a student ID   -> 0 found, 1 exists
--   a phone number                 -> 0 found, 1 exists
--   batch '68'                     -> 0 found, 2 exist
--   email fragment 'diu.edu.bd'    -> 1 found, 12 exist
-- An admin typing the ID printed on a student's card got "No users found",
-- because the ID was matched from its FIRST character only.
--
-- One haystack, used by BOTH the row query and the facet counts, so the
-- count on a chip can never describe a different population than the rows
-- below it. It is also what the index is built on -- if the two expressions
-- drift apart the index is silently not used, so they are the same function
-- call in all three places rather than three hand-copied concatenations.
create or replace function profile_search_text(
  p_full_name text, p_email text, p_university_id text, p_phone text,
  p_teacher_initial text, p_batch text, p_section text
) returns text language sql immutable parallel safe as $$
  select lower(concat_ws(' ',
    coalesce(p_full_name, ''), coalesce(p_email, ''),
    coalesce(p_university_id, ''), coalesce(p_phone, ''),
    coalesce(p_teacher_initial, ''), coalesce(p_batch, ''),
    coalesce(p_section, '')))
$$;

-- Substring search over 7 columns is a sequential scan without this. There
-- are 14 profiles today and the owner expects thousands, so the index goes
-- in now rather than after it becomes a support ticket.
create index if not exists profiles_search_trgm_idx on profiles using gin (
  profile_search_text(full_name, email, university_id, phone,
                      teacher_initial, batch, section) gin_trgm_ops
);

create or replace function public.admin_search_users(
  p_role text default null, p_batch text default null,
  p_section text default null, p_department_id uuid default null,
  p_semester integer default null, p_verified boolean default null,
  p_q text default null, p_limit integer default 50,
  p_cursor_created_at timestamptz default null, p_cursor_id uuid default null
) returns table(
  id uuid, full_name text, email text, phone text, role text,
  university_id text, department text, batch text, section text,
  semester integer, teacher_initial text, gender text, emergency_contact text,
  avatar_url text, is_verified boolean, identity_source text,
  created_at timestamptz
) language plpgsql stable security definer set search_path to 'public','pg_temp'
as $function$
declare
  v_q text := nullif(btrim(coalesce(p_q, '')), '');
  v_esc text;
  v_limit int := greatest(1, least(coalesce(p_limit, 50), 200));
begin
  if not can_browse_users() then
    raise exception 'Not authorized to browse users' using errcode = '42501';
  end if;

  -- A typed '%' is a character somebody is searching for, not a wildcard
  -- meaning "everyone".
  v_esc := lower(replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_'));

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
       or profile_search_text(p.full_name, p.email, p.university_id, p.phone,
                              p.teacher_initial, p.batch, p.section)
          like '%' || v_esc || '%' escape '\'
     )
     and (
       p_cursor_created_at is null
       or (p.created_at, p.id) < (p_cursor_created_at, p_cursor_id)
     )
   order by p.created_at desc, p.id desc
   limit v_limit;
end;
$function$;

create or replace function public.admin_user_facets(
  p_role text default null, p_batch text default null,
  p_section text default null, p_department_id uuid default null,
  p_semester integer default null, p_verified boolean default null,
  p_q text default null
) returns jsonb
language plpgsql stable security definer set search_path to 'public','pg_temp'
as $function$
declare
  v_q text := nullif(btrim(coalesce(p_q, '')), '');
  v_esc text;
  v_result jsonb;
begin
  if not can_browse_users() then
    raise exception 'Not authorized to browse users' using errcode = '42501';
  end if;

  v_esc := lower(replace(replace(replace(v_q, '\', '\\'), '%', '\%'), '_', '\_'));

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
         or profile_search_text(p.full_name, p.email, p.university_id, p.phone,
                                p.teacher_initial, p.batch, p.section)
            like '%' || v_esc || '%' escape '\'
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
$function$;

revoke all on function profile_search_text(text,text,text,text,text,text,text) from anon;
