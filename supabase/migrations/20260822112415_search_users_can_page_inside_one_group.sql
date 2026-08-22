-- admin_user_groups() returns the counts; this returns the rows for ONE of
-- those groups. Four new filters, all defaulted to null, so every existing
-- call site keeps working unchanged (PostgREST passes named arguments).
-- DROP first: CREATE OR REPLACE cannot add parameters, it would create a
-- second overload and every call would then be ambiguous.
--
-- The RETURN SHAPE IS UNCHANGED -- same 17 columns in the same order. The
-- screen reads these by name and must not have to adapt.
drop function if exists public.admin_search_users(text, text, text, uuid, integer, boolean, text, integer, timestamptz, uuid);

create or replace function public.admin_search_users(
  p_role text default null, p_batch text default null,
  p_section text default null, p_department_id uuid default null,
  p_semester integer default null, p_verified boolean default null,
  p_q text default null, p_limit integer default 50,
  p_cursor_created_at timestamptz default null, p_cursor_id uuid default null,
  -- group keys, matching admin_user_groups(). 'unset' means "the group of
  -- people who have no value here", which is a real group somebody has to
  -- work through, not an absence of filter.
  p_admission_season text default null, p_admission_year text default null,
  p_joined_year text default null, p_staff_category text default null
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
    left join staff s on s.profile_id = p.id
   where (p_role          is null or p.role          = p_role)
     and (p_batch         is null or p.batch         = p_batch)
     and (p_section       is null or upper(p.section) = upper(p_section))
     and (p_department_id is null or p.department_id = p_department_id)
     and (p_semester      is null or p.semester      = p_semester)
     and (p_verified      is null or p.is_verified   = p_verified)
     and (p_admission_season is null
          or (p_admission_season = 'unset' and p.admission_season is null)
          or p.admission_season = p_admission_season)
     and (p_admission_year is null
          or (p_admission_year = 'unset' and p.admission_year is null)
          or p.admission_year::text = p_admission_year)
     and (p_joined_year is null
          or (p_joined_year = 'unset' and p.joined_on is null)
          or extract(year from p.joined_on)::text = p_joined_year)
     and (p_staff_category is null
          or (p_staff_category = 'unset' and nullif(btrim(coalesce(s.category,'')),'') is null)
          or s.category = p_staff_category)
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

revoke all on function public.admin_search_users(text,text,text,uuid,integer,boolean,text,integer,timestamptz,uuid,text,text,text,text) from public, anon;
grant execute on function public.admin_search_users(text,text,text,uuid,integer,boolean,text,integer,timestamptz,uuid,text,text,text,text) to authenticated;
