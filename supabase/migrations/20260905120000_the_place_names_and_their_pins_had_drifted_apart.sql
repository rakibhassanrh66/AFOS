-- The place names and their pins had drifted apart.
--
-- WHAT THE USER SAW. Bus routes drawn "all over the map": R9 ends 9.4 km from
-- campus in Mirpur, the campus itself is pinned in SEVEN different places
-- across the active network, and half the routes in the list draw nothing at
-- all. Stop names and stop pins disagree.
--
-- ---------------------------------------------------------------------------
-- ROOT CAUSE 1 -- coordinates were preserved BY POSITION, not by identity.
--
-- `TransportImportService._syncStops` upserts stop rows carrying only
-- (route_id, stop_name, stop_order):
--
--     upsert(stopRows, onConflict: 'route_id,stop_order')
--
-- latitude/longitude are deliberately left out of the payload so that
-- "a stop that already has lat/long keeps it". But ON CONFLICT keys on
-- (route_id, stop_order) -- a POSITION. So when a re-upload inserts, removes or
-- reorders one stop, position 4 keeps position 4's old coordinates while
-- position 4's NAME becomes a different place, and every coordinate after the
-- edit slides one seat down the row.
--
-- Proof, from the live data before this migration:
--
--     R12 stop 2  "Kamar Para"           23.787671, 90.347993
--     R9  stop 13 "Birulia Bus Stand"    23.787671, 90.347993   <- identical
--     R12 stop 3  "Dhour"                23.795130, 90.348288
--     R9  stop 14 "Daffodil Smart City"  23.795130, 90.348288   <- identical
--
-- Two unrelated places cannot share a coordinate to six decimal places. The
-- lat/lng series is a real, coherent northbound run -- it has simply been
-- stamped onto the wrong list of names.
--
-- ROOT CAUSE 2 -- the stale-route sweep is scoped to one semester.
--
-- The same method deletes routes "no longer in the file" with
-- `.eq('semester', semester)`, so importing Fall-2026 never looked at
-- Summer-2026. Both semesters are therefore is_active, `watchRoutes()` filters
-- on is_active alone, and the Transport screen lists 39 routes for a 21-route
-- network. Worse, route NUMBERS were reassigned between the two imports --
-- R13 is "Uttara Moylar Mor" in one and "Mirpur-1, Sony Cinema Hall" in the
-- other -- so picking R13 is a coin flip between two different buses.
--
-- ROOT CAUSE 3 -- nothing geocodes an import.
--
-- Geocoding happened exactly once, in 20260722082525, as a hardcoded
-- name -> coordinate table. Migration 20260814213849 closed with a DO block
-- asserting "no stop on an ACTIVE route may lack coordinates", and said
-- outright: "If a future import adds one, this migration's guarantee is what
-- should break first." A one-shot assertion inside a migration cannot fire on
-- a future import. The Fall-2026 import added 168 stops, none geocoded, and
-- nothing broke -- it just drew nothing.
--
-- ---------------------------------------------------------------------------
-- THE FIX, in three parts.
--
--  1. `transport_stop_geo` -- a PERMANENT canonical name -> coordinate
--     reference, seeded with the 76 places validated in 20260722082525 (region
--     bounds, region-centroid detection, and route-context checks) plus the
--     three resolved in 20260814213849. A place is geocoded ONCE, for the whole
--     network, not once per route row.
--
--  2. A BEFORE INSERT/UPDATE trigger on `transport_stops` that derives
--     latitude/longitude from that reference BY NAME whenever a row is inserted
--     or its stop_name changes. This is what makes root cause 1 structurally
--     impossible: a coordinate can never outlive the name it belongs to. An
--     unknown name yields NULL -- the map already renders an unplaced stop
--     honestly, and a missing pin is strictly better than a confident wrong one.
--
--     A direct UPDATE of latitude/longitude that does NOT touch stop_name is
--     left alone, so a one-off manual placement still works. The right place
--     for a lasting correction is `transport_stop_geo`, where it fixes the
--     place on every route at once.
--
--  3. Retire superseded semesters, so the live list is the current schedule.
--     Safe here because Fall-2026's route numbers are a strict SUPERSET of
--     Summer-2026's (F1-F5, R1-R10 in both; R11-R16 only in Fall): nobody
--     loses a route.
--
-- VERIFICATION IS BEHAVIOURAL, not a definition read-back: the DO block at the
-- end re-derives every active stop and fails the migration if any active route
-- has fewer than 2 placed stops, if any consecutive hop exceeds 12 km (the
-- same bound 20260722082525 validated against), if any stop named for the
-- campus lands more than 500 m from it, or if any route number is still
-- active twice.

-- ---------------------------------------------------------------------------
-- 1. Canonical place reference
-- ---------------------------------------------------------------------------

create or replace function public.transport_stop_key(p_name text)
returns text
language sql
immutable
strict
set search_path = ''
as $fn$ select lower(regexp_replace(p_name, '[^a-zA-Z0-9]', '', 'g')) $fn$;

comment on function public.transport_stop_key(text) is
  'Normalized stop identity: lower-case, alphanumerics only. Mirrors stopKey() '
  'in lib/features/transport/data/transport_display.dart so "Mirpur 10", '
  '"Mirpur-10" and "MIRPUR  10" resolve to one place on both sides.';

create table if not exists public.transport_stop_geo (
  stop_key    text primary key,
  stop_name   text not null,
  latitude    double precision not null,
  longitude   double precision not null,
  note        text,
  updated_at  timestamptz not null default now()
);

comment on table public.transport_stop_geo is
  'Canonical name -> coordinate reference for the bus network. One row per '
  'physical place, keyed on transport_stop_key(stop_name). transport_stops '
  'derives its coordinates from here via a trigger; correct a pin HERE and it '
  'is corrected on every route that stops there.';

alter table public.transport_stop_geo enable row level security;

drop policy if exists auth_read_stop_geo on public.transport_stop_geo;
create policy auth_read_stop_geo on public.transport_stop_geo
  for select to authenticated using (true);

drop policy if exists admin_write_stop_geo on public.transport_stop_geo;
create policy admin_write_stop_geo on public.transport_stop_geo
  for all to authenticated
  using (exists (select 1 from public.profiles p
                  where p.id = (select auth.uid()) and p.is_verified
                    and (p.role = any (array['admin','teacher','dept_admin','super_admin'])
                         or public.caller_can('transport','upload'))))
  with check (exists (select 1 from public.profiles p
                  where p.id = (select auth.uid()) and p.is_verified
                    and (p.role = any (array['admin','teacher','dept_admin','super_admin'])
                         or public.caller_can('transport','upload'))));

-- The 79 validated places. Every coordinate here is carried forward from
-- 20260722082525 / 20260814213849 -- none is new or guessed in this migration.
-- distinct on: two spellings in this list normalize to one key --
-- 'Mirpur 10' and 'Mirpur-10', carrying identical coordinates. That is the
-- very split spelling stopKey() exists to collapse, and without the dedupe
-- ON CONFLICT raises 21000 ("cannot affect row a second time"). Ordered by
-- stop_name so the surviving spelling is deterministic across re-runs.
insert into public.transport_stop_geo (stop_key, stop_name, latitude, longitude, note)
select distinct on (public.transport_stop_key(v.n))
       public.transport_stop_key(v.n), v.n, v.lat, v.lng,
       'validated in 20260722082525 / 20260814213849'
from (values
  ('Akran',23.8603343,90.3072067),
  ('Ashulia Bazar',23.8971149,90.3308863),
  ('Badda Suvastu tower',23.7814334,90.4170902),
  ('Baipail',23.9325782,90.2784385),
  ('Bashabo',23.7426044,90.4307836),
  ('Beribadh',23.8248157,90.3437695),
  ('Birulia',23.8477331,90.3351107),
  ('Birulia Bus Stand',23.8506812,90.3411775),
  ('Bismail',23.895606,90.270935),
  ('C&B',23.8724113,90.2731743),
  ('Chankharpul',23.7237041,90.4005067),
  ('Charabag',23.8859260,90.3108332),
  ('Commerce College',23.8070848,90.354656),
  ('Daffodil Smart City',23.8756013,90.3203018),
  ('Dhamrai Bus Stand',23.9051487,90.2200386),
  ('Dhanmondi - Sobhanbag',23.7554056,90.3765456),
  ('Dhour',23.8862902,90.3689508),
  ('Diyabari Bridge',23.8740431,90.3790494),
  ('Eastern Housing',23.8298204,90.3501258),
  ('Eastern Housing Rup Nogor',23.8205098,90.3555377),
  ('ECB Chattor',23.8225517,90.3934291),
  ('Estern Housing',23.8298204,90.3501258),
  ('Estern Mor',23.8697294,90.309887),
  ('Ghosbag',23.9206289,90.3066277),
  ('Gonosastho',23.9179674,90.2449484),
  ('Grand Zamzam Tower',23.8740618,90.3903604),
  ('Gudaraghat',23.8022189,90.3490521),
  ('gulistan',23.7228045,90.4133616),
  ('House building',23.874188,90.40073),
  ('Jamuna Future Park',23.8135411,90.4242393),
  ('JU',23.8818302,90.2624636),
  ('Kalshi More',23.8228327,90.3776604),
  ('Kamar Para',23.8892301,90.3830754),
  ('Khagan',23.874879,90.310977),
  ('Kohinur Market',23.9157000,90.2359593),
  ('kolabagan',23.7494231,90.3830754),
  ('Kolma',23.8829775,90.2882348),
  ('Konabari Bus Stop',23.7951301,90.3482875),
  ('Konabari Pukur Par',24.0112973,90.3219053),
  ('Kumkumari',23.8822709,90.3055992),
  ('Kuril Bisso Road',23.8211887,90.4195458),
  ('Majar Road Gabtoli',23.7876709,90.3479928),
  ('Malibagh Railgate (South Bus Stop)',23.7496015,90.4125881),
  ('Middle Badda',23.7798106,90.4237121),
  ('Mirpur 01 - Sony Cinema Hall',23.8003906,90.3553414),
  ('Mirpur 02',23.8336634,90.3746197),
  ('Mirpur 10',23.8028556,90.3748344),
  ('Mirpur 12',23.8280274,90.3640039),
  ('Mirpur Konabari',23.7950603,90.3482823),
  ('Mirpur-10',23.8028556,90.3748344),
  ('Mugda Medical College',23.731981,90.4301631),
  ('Nabinagar',23.912477,90.259787),
  ('Narayanganj Chasara',23.6263613,90.4992069),
  ('New Market',23.7331937,90.3837664),
  ('Nilkhet',23.7321134,90.3852486),
  ('Nobinagar',23.912477,90.259787),
  ('Norshingpur',23.930424,90.308329),
  ('Notun Bazar',23.7805462,90.4266584),
  ('Paragram',23.8787642,90.3367212),
  ('Polli Biddut',23.8964944,90.3267087),
  ('Prantik',23.8896752,90.2720048),
  ('Radio Colony',23.8578761,90.2640617),
  ('Rampura Bazar Bus Stop',23.7606706,90.4191967),
  ('Rampura Bridge',23.7680925,90.4232073),
  ('Savar',23.8479013,90.257699),
  ('Savar Bus Stand',23.8474877,90.2575424),
  ('saydabad bus stand',23.7159254,90.4258436),
  ('Shyamoli Square',23.7746596,90.365494),
  ('sign board',23.6918777,90.4814999),
  ('sonir akhra',23.7075811,90.4537748),
  ('Sony Cinema Hall',23.8003906,90.3553414),
  ('Technical Bus stand',23.7814677,90.3517409),
  ('Technical Mor',23.781384,90.351898),
  ('Tongi College Gate Bus Stand',23.889974,90.4073472),
  ('Tongi station route',23.8900689,90.4071462),
  ('Uttara - Rajlokkhi',23.8643746,90.399609),
  ('Uttara Metro rail Center',23.8596875,90.3651875),
  ('Uttara Moylar Mor',23.874052,90.3841088),
  ('Zirabo',23.9101983,90.3172039)
) as v(n, lat, lng)
order by public.transport_stop_key(v.n), v.n
on conflict (stop_key) do update
  set stop_name  = excluded.stop_name,
      latitude   = excluded.latitude,
      longitude  = excluded.longitude,
      updated_at = now();

-- ---------------------------------------------------------------------------
-- 2. A coordinate may never outlive the name it belongs to
-- ---------------------------------------------------------------------------

create or replace function public.transport_stops_resolve_geo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare g public.transport_stop_geo%rowtype;
begin
  -- Only re-derive when the row is new or its NAME changed. A deliberate
  -- UPDATE of the coordinates alone is a manual placement and is respected.
  if tg_op = 'INSERT' or new.stop_name is distinct from old.stop_name then
    select * into g from public.transport_stop_geo
      where stop_key = public.transport_stop_key(new.stop_name);
    if found then
      new.latitude  := g.latitude;
      new.longitude := g.longitude;
    else
      -- Unknown place. NULL is honest; inheriting the previous occupant's pin
      -- is exactly the bug this trigger exists to prevent.
      new.latitude  := null;
      new.longitude := null;
    end if;
  end if;
  return new;
end $fn$;

revoke all on function public.transport_stops_resolve_geo() from public;
revoke all on function public.transport_stops_resolve_geo() from anon;
revoke all on function public.transport_stops_resolve_geo() from authenticated;

drop trigger if exists trg_transport_stops_resolve_geo on public.transport_stops;
create trigger trg_transport_stops_resolve_geo
  before insert or update on public.transport_stops
  for each row execute function public.transport_stops_resolve_geo();

-- ---------------------------------------------------------------------------
-- 3. Re-derive every existing row, and retire superseded semesters
-- ---------------------------------------------------------------------------

update public.transport_stops s
   set latitude  = g.latitude,
       longitude = g.longitude
  from public.transport_stop_geo g
 where g.stop_key = public.transport_stop_key(s.stop_name)
   and (s.latitude is distinct from g.latitude
     or s.longitude is distinct from g.longitude);

-- Any stop whose name is NOT in the reference loses its pin. Every such
-- coordinate today arrived by the positional slide described above, so it is
-- pointing at some other place.
update public.transport_stops s
   set latitude = null, longitude = null
 where not exists (select 1 from public.transport_stop_geo g
                    where g.stop_key = public.transport_stop_key(s.stop_name))
   and (s.latitude is not null or s.longitude is not null);

-- Retire everything that is not the current schedule. Guarded: if no schedule
-- is marked current, change nothing rather than deactivate the whole network.
update public.transport_routes r
   set is_active = false
 where r.is_active
   and exists (select 1 from public.transport_schedule_meta where is_current)
   and r.semester is distinct from
       (select m.semester from public.transport_schedule_meta m
         where m.is_current order by m.imported_at desc limit 1);

-- ---------------------------------------------------------------------------
-- 4. Behavioural verification -- fail the migration, do not ship half a fix
-- ---------------------------------------------------------------------------
do $verify$
declare
  bad_routes   int;
  long_hops    int;
  stray_campus int;
  dup_numbers  int;
begin
  select count(*) into bad_routes from (
    select r.id from public.transport_routes r
      left join public.transport_stops s
             on s.route_id = r.id and s.latitude is not null
     where r.is_active
     group by r.id having count(s.id) < 2
  ) x;
  if bad_routes > 0 then
    raise exception 'transport: % active route(s) still have < 2 placed stops', bad_routes;
  end if;

  -- NOTE: lag() is computed in its own subquery and NULL-filtered before the
  -- distance formula. Postgres greatest()/least() IGNORE nulls, so
  -- greatest(-1, NULL) is -1, not NULL -- folding the formula inline would make
  -- every route's FIRST stop report acos(-1) = 20015 km and fail this check on
  -- perfectly good data. Caught in the dry run of this very migration.
  select count(*) into long_hops from (
    select 6371 * acos(least(1, greatest(-1,
             cos(radians(p.latitude)) * cos(radians(p.plat))
               * cos(radians(p.plng) - radians(p.longitude))
             + sin(radians(p.latitude)) * sin(radians(p.plat))))) as km
      from (
        select s.latitude, s.longitude,
               lag(s.latitude)  over w as plat,
               lag(s.longitude) over w as plng
          from public.transport_stops s
          join public.transport_routes r on r.id = s.route_id
         where r.is_active and s.latitude is not null
        window w as (partition by s.route_id order by s.stop_order)
      ) p
     where p.plat is not null
  ) h where h.km > 12;
  if long_hops > 0 then
    raise exception 'transport: % consecutive stop hop(s) exceed 12 km', long_hops;
  end if;

  select count(*) into stray_campus
    from public.transport_stops s
    join public.transport_routes r on r.id = s.route_id
   where r.is_active and s.latitude is not null
     and public.transport_stop_key(s.stop_name) = 'daffodilsmartcity'
     and 6371 * acos(least(1, greatest(-1,
           cos(radians(s.latitude)) * cos(radians(23.8756013))
             * cos(radians(90.3203018) - radians(s.longitude))
           + sin(radians(s.latitude)) * sin(radians(23.8756013))))) > 0.5;
  if stray_campus > 0 then
    raise exception 'transport: % campus stop(s) pinned > 500 m from campus', stray_campus;
  end if;

  select count(*) into dup_numbers from (
    select route_number from public.transport_routes
     where is_active group by route_number having count(*) > 1
  ) d;
  if dup_numbers > 0 then
    raise exception 'transport: % route number(s) still active twice', dup_numbers;
  end if;
end $verify$;
