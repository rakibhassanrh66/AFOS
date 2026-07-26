-- Per-stop bus timings.
--
-- WHY A SEPARATE TABLE, not the transport_routes.stops jsonb: the importer
-- rewrites that jsonb wholesale on every re-upload (TransportImportService.write
-- upserts toRouteRow()), so any admin-entered timing stored inside it would be
-- silently wiped by the next semester's sheet. Keyed by (route_number,
-- schedule_type, stop_name) rather than route_id for the same reason — route
-- ids are recreated per semester, but route numbers and stop names are stable,
-- so timings entered once survive semester rollovers.
--
-- WHY TWO OFFSETS, not one: the source sheet's two time columns mean different
-- things. `to_dsc_trips` is "Start Time" — when the bus departs the route's
-- FIRST stop, inbound. `from_dsc_trips` is when it departs CAMPUS, outbound.
-- The inbound leg (origin -> stop) and the outbound leg (DSC -> stop) are
-- therefore different durations for the same stop, and collapsing them into a
-- single number would reintroduce exactly the kind of approximation this table
-- exists to remove.
--
-- Nothing here alters an existing table or column; transport_stops (whose
-- estimated_minutes_from_diu column was declared in 001_init.sql but never
-- written by anything) is left untouched.
create table if not exists public.transport_stop_offsets (
  id uuid primary key default gen_random_uuid(),
  route_number text not null,
  schedule_type text not null check (schedule_type in ('regular', 'shuttle', 'friday')),
  stop_name text not null,
  -- Minutes AFTER the route's start time that the bus reaches this stop
  -- (inbound, toward campus). The origin stop is 0.
  minutes_from_origin integer check (minutes_from_origin >= 0 and minutes_from_origin <= 600),
  -- Minutes AFTER departing campus that the bus reaches this stop (outbound).
  minutes_from_dsc integer check (minutes_from_dsc >= 0 and minutes_from_dsc <= 600),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  unique (route_number, schedule_type, stop_name)
);

create index if not exists transport_stop_offsets_route_idx
  on public.transport_stop_offsets (route_number, schedule_type);

alter table public.transport_stop_offsets enable row level security;

-- Everyone signed in can READ timings (that's the whole point — riders see
-- when the bus reaches their own stop).
drop policy if exists transport_stop_offsets_select on public.transport_stop_offsets;
create policy transport_stop_offsets_select on public.transport_stop_offsets
  for select to authenticated
  using (true);

-- Only admins / super-admins may WRITE them. get_my_profile_role() is the
-- existing SECURITY DEFINER role accessor used for admin gating elsewhere.
drop policy if exists transport_stop_offsets_write on public.transport_stop_offsets;
create policy transport_stop_offsets_write on public.transport_stop_offsets
  for all to authenticated
  using (public.get_my_profile_role() in ('admin', 'super_admin'))
  with check (public.get_my_profile_role() in ('admin', 'super_admin'));

-- Live propagation so a timing correction reaches riders' devices immediately.
do $$
begin
  alter publication supabase_realtime add table public.transport_stop_offsets;
exception
  when duplicate_object then null;
end $$;
