-- First cut put BOTH jobs in one BEFORE trigger on profiles: compute
-- completeness, and mirror joined_on into teachers/staff. That mirror fired
-- the teachers trigger, which wrote back to the very profiles row still being
-- updated, and Postgres refused outright:
--
--   27000: tuple to be updated was already modified by an operation
--          triggered by the current command
--   HINT: Consider using an AFTER trigger instead of a BEFORE trigger to
--         propagate changes to other rows.
--
-- Found by running it, not by reading it. Split in two, per that hint:
-- BEFORE computes the row's own column and touches nothing else; AFTER
-- propagates outward. The re-entrancy flag is belt and braces -- it stops the
-- outward mirror from being mistaken for a designation edit and bouncing back.

create or replace function tg_profile_completeness()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  -- The client's claim is discarded; the row decides. This trigger writes
  -- NOTHING except its own NEW record.
  new.profile_completed := profile_is_complete(new);
  return new;
end $$;

create or replace function tg_profile_mirror_join_date()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  if tg_op = 'UPDATE' and new.joined_on is not distinct from old.joined_on then
    return null;
  end if;
  if new.joined_on is null then
    return null;
  end if;

  -- Announce that the next teachers/staff write is OUR mirror, so the paired
  -- trigger below does not treat it as a designation edit and come back.
  perform set_config('afos.mirroring_join_date', '1', true);
  update teachers t set joining_date = new.joined_on
   where t.profile_id = new.id and t.joining_date is distinct from new.joined_on;
  update staff s set joining_date = new.joined_on
   where s.profile_id = new.id and s.joining_date is distinct from new.joined_on;
  perform set_config('afos.mirroring_join_date', '', true);
  return null;
end $$;

create or replace function tg_role_row_touches_profile()
returns trigger language plpgsql set search_path to 'public' as $$
begin
  -- Our own mirror, coming back around. Ignore it.
  if coalesce(current_setting('afos.mirroring_join_date', true), '') = '1' then
    return new;
  end if;

  -- A teacher's designation lives HERE, not on profiles, and
  -- complete_profile_screen.dart writes profiles first (line 260) and teachers
  -- second (line 292). Without this touch the verdict would be reached before
  -- the designation existed and a teacher could never become complete.
  update profiles set updated_at = now()
   where id = new.profile_id
     and profile_completed is distinct from profile_is_complete(profiles.*);
  return new;
end $$;

drop trigger if exists trg_profile_completeness on profiles;
create trigger trg_profile_completeness
  before insert or update on profiles
  for each row execute function tg_profile_completeness();

drop trigger if exists trg_profile_mirror_join_date on profiles;
create trigger trg_profile_mirror_join_date
  after insert or update on profiles
  for each row execute function tg_profile_mirror_join_date();
