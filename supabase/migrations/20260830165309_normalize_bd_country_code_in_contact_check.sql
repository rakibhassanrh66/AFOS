-- 20260830164152's emergency-contact-vs-phone check compared full digit
-- strings. Found while writing the Dart mirror's test: '+880 1712-345678'
-- and '01712345678' are the SAME Bangladeshi mobile number (a leading 0 is
-- the local-dialling equivalent of the +880 country code) but strip to
-- '8801712345678' (13 digits) vs '01712345678' (11 digits) -- never equal,
-- so someone could dodge the check by adding a country code to their own
-- number. Comparing the LAST 10 digits instead (the subscriber number, which
-- both formats share) closes that.

create or replace function profile_is_complete(p profiles)
returns boolean language sql stable set search_path to 'public' as $$
  select
    nullif(btrim(coalesce(p.full_name, '')), '')            is not null
    and nullif(btrim(coalesce(p.phone, '')), '')            is not null
    and nullif(btrim(coalesce(p.gender, '')), '')           is not null
    and nullif(btrim(coalesce(p.emergency_contact, '')), '') is not null
    and nullif(btrim(coalesce(p.permanent_division, '')), '') is not null
    and nullif(btrim(coalesce(p.permanent_district, '')), '') is not null
    and nullif(btrim(coalesce(p.permanent_upazila, '')), '')  is not null
    and (
      nullif(right(regexp_replace(coalesce(p.emergency_contact, ''), '\D', '', 'g'), 10), '')
      is distinct from
      nullif(right(regexp_replace(coalesce(p.phone, ''), '\D', '', 'g'), 10), '')
    )
    and (
      p.verified_at is null
      or now() - p.verified_at < interval '48 hours'
      or p.avatar_review_status in ('pending', 'approved')
    )
    and case p.role
      when 'student' then
        p.department_id is not null
        and nullif(btrim(coalesce(p.batch, '')), '')   is not null
        and nullif(btrim(coalesce(p.section, '')), '') is not null
        and p.semester         is not null
        and p.admission_season is not null
        and p.admission_year   is not null
        and p.joined_on        is not null
      when 'teacher' then
        p.department_id is not null and p.joined_on is not null
        and exists (select 1 from teachers t
                     where t.profile_id = p.id
                       and nullif(btrim(coalesce(t.designation, '')), '') is not null)
      when 'staff' then
        p.joined_on is not null
        and exists (select 1 from staff s
                     where s.profile_id = p.id
                       and nullif(btrim(coalesce(s.designation, '')), '') is not null)
      else
        nullif(btrim(coalesce(p.role, '')), '') is not null
    end
$$;
