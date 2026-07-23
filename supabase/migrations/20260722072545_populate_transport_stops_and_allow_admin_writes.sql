-- Transport stops: make the table actually usable.
--
-- `TransportImportService.write()` has never written to `transport_stops` at
-- all -- it only stores the ordered stop list as a `stops` jsonb column on
-- `transport_routes`. So every one of the 183 existing rows came from the old
-- legacy import, and after that batch was retired (migration 20260721210417)
-- ZERO stop rows belonged to an active route. `fetchStops()` therefore returned
-- an empty list for every route in the app, which is why the Map tab could
-- never draw a polyline or place a single stop pin.
--
-- Three separate defects had to be fixed before the data could even be stored:

-- 1. RLS allowed reads but NOT writes. `transport_stops` has RLS enabled and
--    exactly one policy (`auth_read_stops`), so an admin uploading a routine
--    would have been blocked from inserting stops even once the code was fixed.
--    Mirror `admin_write_routes` on `transport_routes` verbatim so the same
--    people who can upload a schedule can write its stops.
drop policy if exists admin_write_stops on public.transport_stops;
create policy admin_write_stops on public.transport_stops
  for all to authenticated
  using (
    exists (
      select 1 from public.profiles
      where profiles.id = auth.uid()
        and profiles.is_verified
        and (profiles.role = any (array['admin','teacher','dept_admin','super_admin'])
             or caller_can('transport', 'upload'))
    )
  );

-- 2. No unique key, so a re-import could only ever duplicate rows. (route_id,
--    stop_order) is the natural key: one stop per position per route.
create unique index if not exists transport_stops_route_order_uniq
  on public.transport_stops (route_id, stop_order);

-- 3. The FK had no ON DELETE CASCADE. `write()` prunes stale routes with a
--    plain `delete from transport_routes where id = ...`; with stop rows
--    present that delete would start failing on a foreign-key violation. This
--    was harmless only because the table was never populated -- fixing the
--    importer without this would have broken every future upload.
alter table public.transport_stops
  drop constraint if exists transport_stops_route_id_fkey;
alter table public.transport_stops
  add constraint transport_stops_route_id_fkey
  foreign key (route_id) references public.transport_routes(id) on delete cascade;

-- Backfill the 21 active routes from the ordered `stops` jsonb that the
-- importer already writes. `with ordinality` preserves the running order, which
-- is what makes a polyline meaningful. Latitude/longitude stay NULL: no
-- coordinate data exists yet, and inventing one would put a bus stop in the
-- wrong place on a map, which is worse than drawing no line at all.
insert into public.transport_stops (route_id, stop_name, stop_order)
select tr.id, btrim(e.value->>'name'), e.ordinality::int
from public.transport_routes tr,
     lateral jsonb_array_elements(tr.stops) with ordinality e(value, ordinality)
where tr.is_active
  and coalesce(btrim(e.value->>'name'), '') <> ''
on conflict (route_id, stop_order) do update
  set stop_name = excluded.stop_name;
