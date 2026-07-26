-- Live location layer for the SOS system's "who is actually near me right
-- now" campus-zone recipient resolution. Best-effort/opt-out, not a hard
-- gate like profile_completed -- location permission is OS-level and both
-- platforms prohibit hard-blocking app functionality on a declined
-- sensitive permission. A user who disables sharing (or never grants the
-- permission) still gets full app access and can still send their own SOS
-- (a fresh one-shot GPS capture at trigger time, independent of this
-- ambient layer) -- they just won't be included in anyone else's proximity
-- match and won't have others matched against them.
-- latitude/longitude are nullable: the Settings toggle (sharing_enabled)
-- can be flipped before any GPS ping has ever succeeded (permission still
-- pending, fresh install, indoors with no fix yet) -- that upsert must not
-- be blocked by a NOT NULL constraint on coordinates that don't exist yet.
-- Recipient resolution in trigger-sos-alert filters out null-coordinate
-- rows itself.
create table user_locations (
  user_id uuid primary key references profiles(id) on delete cascade,
  latitude double precision,
  longitude double precision,
  accuracy_m double precision,
  sharing_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

alter table user_locations enable row level security;

create policy own_manage_user_locations on user_locations
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Needed for manage_sos_screen.dart's oversight view and is not otherwise
-- used to resolve SOS recipients client-side -- the trigger-sos-alert edge
-- function runs with the service-role key and bypasses RLS entirely.
create policy admin_read_user_locations on user_locations
  for select using (get_my_profile_role() in ('admin','super_admin','staff'));
