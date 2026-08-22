-- profile_completed was a boolean the CLIENT set: complete_profile_screen.dart
-- line 271 writes `'profile_completed': true` regardless of what is in the row.
-- Measured consequence: 14 of 14 accounts flagged complete, while 7 had no
-- phone, 11 had no emergency contact, and 7 had no address. Completeness was
-- an opinion held by the client, not a fact about the row.
--
-- It is now computed by the server on every write. The router gate that
-- already exists (app_router.dart:106-111) then does the forcing for free.
--
-- NOTE: the trigger definitions here are superseded a few minutes later by
-- 20260822105602_completeness_triggers_that_do_not_chase_each_other.sql --
-- this version put the outward mirror in the BEFORE trigger and deadlocked.
-- Kept as applied, because the ledger records what actually ran.

create or replace function profile_is_complete(p profiles)
returns boolean language sql stable set search_path to 'public' as $$
  select
    -- Everyone owes a way to be reached and an address. btrim, because a
    -- blank string is not a filled field -- `department = ''` defeated
    -- `?? 'default'` in this project once already.
    nullif(btrim(coalesce(p.full_name, '')), '')            is not null
    and nullif(btrim(coalesce(p.phone, '')), '')            is not null
    and nullif(btrim(coalesce(p.gender, '')), '')           is not null
    and nullif(btrim(coalesce(p.emergency_contact, '')), '') is not null
    and nullif(btrim(coalesce(p.permanent_division, '')), '') is not null
    and nullif(btrim(coalesce(p.permanent_district, '')), '') is not null
    and nullif(btrim(coalesce(p.permanent_upazila, '')), '')  is not null
    -- permanent_thana is deliberately NOT required: it applies only to
    -- city-corporation addresses, and requiring it would wedge every rural
    -- address permanently.
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
        -- admin / super_admin carry no academic identity. An ABSENT role is a
        -- different thing and must not read as complete.
        nullif(btrim(coalesce(p.role, '')), '') is not null
    end
$$;

create or replace function tg_profile_completeness()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  new.profile_completed := profile_is_complete(new);
  if tg_op = 'INSERT' then
    if new.joined_on is not null then
      update teachers t set joining_date = new.joined_on
       where t.profile_id = new.id and t.joining_date is distinct from new.joined_on;
      update staff s set joining_date = new.joined_on
       where s.profile_id = new.id and s.joining_date is distinct from new.joined_on;
    end if;
  elsif new.joined_on is distinct from old.joined_on then
    update teachers t set joining_date = new.joined_on
     where t.profile_id = new.id and t.joining_date is distinct from new.joined_on;
    update staff s set joining_date = new.joined_on
     where s.profile_id = new.id and s.joining_date is distinct from new.joined_on;
  end if;
  return new;
end $$;

drop trigger if exists trg_profile_completeness on profiles;
create trigger trg_profile_completeness
  before insert or update on profiles
  for each row execute function tg_profile_completeness();

-- A teacher's designation lives in `teachers`, not `profiles`, and
-- complete_profile_screen.dart writes profiles FIRST (line 260) and teachers
-- second (line 292). Without this, the completeness verdict would be reached
-- before the designation existed and a teacher could never become complete.
create or replace function tg_role_row_touches_profile()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  update profiles set updated_at = now()
   where id = new.profile_id
     and profile_completed is distinct from profile_is_complete(profiles.*);
  return new;
end $$;

drop trigger if exists trg_teachers_touch_profile on teachers;
create trigger trg_teachers_touch_profile
  after insert or update on teachers
  for each row execute function tg_role_row_touches_profile();

drop trigger if exists trg_staff_touch_profile on staff;
create trigger trg_staff_touch_profile
  after insert or update on staff
  for each row execute function tg_role_row_touches_profile();
