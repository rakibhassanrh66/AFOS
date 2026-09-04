-- =====================================================================
--  A 48-hour grace that is actually 48 hours.
--
--  WHAT WAS WRONG. The photo rule inside profile_is_complete() reads
--  `now() - verified_at < interval '48 hours'`, so the window was anchored to
--  the moment the account was APPROVED. For every account approved before the
--  rule shipped, that window had already closed — the 12 accounts affected
--  were verified between 2026-07-07 and 2026-08-30. They were never given 48
--  hours; they were locked retroactively, and the router's hard redirect meant
--  they could not reach any screen that explained why.
--
--  Measured before changing anything: of 13 incomplete profiles, 2 were held
--  by the photo alone, 1 by fields alone, and 10 by both. So relaxing the
--  photo on its own would have freed two people. The grace covers the whole
--  profile.
--
--  WHAT THIS DOES. profile_is_complete() is NOT weakened — "complete" still
--  means everything it meant. What changes is that being incomplete no longer
--  locks the app immediately: a per-row deadline starts the first time a row
--  reads incomplete and never restarts, so a person gets one real window and
--  cannot extend it by editing a field back and forth.
--
--  After: 13 incomplete, 13 inside grace, 0 locked.
-- =====================================================================

alter table public.profiles
  add column if not exists profile_grace_until timestamptz;

comment on column public.profiles.profile_grace_until is
  'When this account stops being allowed to skip an incomplete profile. Set '
  'once, the first time the row reads incomplete, and never restarted.';

create or replace function public.tg_profile_completeness()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  -- The client's claim is discarded; the row decides. This trigger writes
  -- NOTHING except its own NEW record.
  new.profile_completed := profile_is_complete(new);

  -- `is null` is what makes the window one-shot rather than renewable.
  if not new.profile_completed and new.profile_grace_until is null then
    new.profile_grace_until := now() + interval '48 hours';
  end if;

  return new;
end $function$;

-- Everyone currently locked gets one real window, starting now. Without this
-- the 13 stay exactly where they are: the trigger above only fires on write,
-- and these rows are not being written precisely because nobody can get past
-- the screen that would write them.
update public.profiles
   set profile_grace_until = now() + interval '48 hours'
 where coalesce(profile_completed, false) = false
   and profile_grace_until is null;
