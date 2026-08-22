-- The directory was one flat page of everybody, filtered by chips. The owner
-- asked for a PLACE per kind of person, each grouped the way that kind is
-- actually organised:
--   student  -> intake term (Fall/Summer/Spring + year) -> batch
--   teacher  -> department -> year joined
--   staff    -> sector (staff.category) -> year joined
--
-- Counts come from the database, never from what happened to be downloaded --
-- a group header that says 40 while 50 rows are loaded is worse than no
-- header. Rows for an expanded group are fetched by admin_search_users with
-- the same group keys, so the count and the rows cannot describe different
-- populations.
--
-- Groups with no value are returned as "Not set" rather than dropped. As of
-- today 12 of 14 people have no intake term, because the mandatory-profile
-- work only just started collecting it -- hiding them would hide exactly the
-- people who still need chasing.

create or replace function admin_user_groups(
  p_role text default null,
  p_q text default null,
  p_verified boolean default null,
  p_department_id uuid default null
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
    select p.*,
           coalesce(t.designation, s.designation) as designation,
           s.category as staff_category,
           d.code as dept_code,
           d.name as dept_name
      from profiles p
      left join teachers t    on t.profile_id = p.id
      left join staff s       on s.profile_id = p.id
      left join departments d on d.id = p.department_id
     where (p_role          is null or p.role          = p_role)
       and (p_verified      is null or p.is_verified   = p_verified)
       and (p_department_id is null or p.department_id = p_department_id)
       and (
         v_q is null
         or profile_search_text(p.full_name, p.email, p.university_id, p.phone,
                                p.teacher_initial, p.batch, p.section)
            like '%' || v_esc || '%' escape '\'
       )
  ),
  keyed as (
    select
      case p_role
        when 'student' then
          case when b.admission_year is null or b.admission_season is null
               then 'unset'
               else b.admission_year::text || '|' || b.admission_season end
        when 'teacher' then coalesce(b.department_id::text, 'unset')
        when 'staff'   then coalesce(nullif(btrim(b.staff_category), ''), 'unset')
        else coalesce(b.role, 'unset')
      end as l1key,
      case p_role
        when 'student' then
          case when b.admission_year is null or b.admission_season is null
               then 'Intake not set'
               else initcap(b.admission_season) || ' ' || b.admission_year::text end
        when 'teacher' then coalesce(b.dept_code, b.dept_name, b.department, 'No department')
        when 'staff'   then coalesce(nullif(btrim(b.staff_category), ''), 'No sector set')
        else coalesce(b.role, 'unknown')
      end as l1label,
      case p_role
        when 'student' then coalesce(nullif(btrim(b.batch), ''), 'unset')
        else coalesce(extract(year from b.joined_on)::text, 'unset')
      end as l2key,
      case p_role
        when 'student' then
          case when nullif(btrim(b.batch), '') is null then 'Batch not set'
               else 'Batch ' || btrim(b.batch) end
        else
          case when b.joined_on is null then 'Join year not set'
               else 'Joined ' || extract(year from b.joined_on)::text end
      end as l2label,
      -- Sort key so 2026 sits above 2023 and "not set" sinks to the bottom
      -- instead of sorting as the string 'unset'.
      case p_role
        when 'student' then coalesce(b.admission_year, -1)
        else coalesce(extract(year from b.joined_on)::int, -1)
      end as l1sort
    from base b
  )
  select coalesce(jsonb_agg(x order by (x->>'l1sort')::int desc,
                                       x->>'l1label',
                                       x->>'l2label'), '[]'::jsonb)
    into v_result
    from (
      select jsonb_build_object(
               'l1key',   k.l1key,
               'l1label', k.l1label,
               'l1sort',  max(k.l1sort),
               'l2key',   k.l2key,
               'l2label', k.l2label,
               'count',   count(*)
             ) as x
        from keyed k
       group by k.l1key, k.l1label, k.l2key, k.l2label
    ) s;

  return v_result;
end;
$function$;

revoke all on function admin_user_groups(text, text, boolean, uuid) from public, anon;
grant execute on function admin_user_groups(text, text, boolean, uuid) to authenticated;
