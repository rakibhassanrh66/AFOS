-- PROPOSED — NOT APPLIED. Requires your explicit decision before it runs.
--
-- WHAT THIS IS FOR
-- `RouteGeometryService` fetches road-following geometry for a bus route from
-- OSRM's public demo server and caches the result on the DEVICE. That works,
-- and it keeps the app inside the demo server's "≤1 request/second, reasonable
-- non-commercial use" terms comfortably: a device fetches a route's shape once
-- and never again unless an admin edits the stops.
--
-- But "once per device" still means once per device. With 21 routes and a few
-- thousand students, that is a few thousand requests against a free service
-- that publishes no uptime guarantee and may withdraw access at any time,
-- for geometry that is IDENTICAL for everyone.
--
-- Caching it server-side turns that into 21 requests total, ever. It also
-- removes the routing service from the runtime path entirely: if OSRM
-- disappears tomorrow, every student still sees the correct road line, because
-- it is our data by then.
--
-- WHY IT IS NOT APPLIED
-- The redesign phases are forbidden from touching schema (CLAUDE.md HARD RULE
-- 1). This is written down, unapplied, for you to decide on.

alter table public.transport_routes
  add column if not exists route_geometry jsonb,
  add column if not exists route_geometry_updated_at timestamptz,
  -- The stop-coordinate signature the geometry was derived from. Lets a reader
  -- detect "an admin moved a stop, this shape is stale" without re-deriving it.
  add column if not exists route_geometry_signature text;

comment on column public.transport_routes.route_geometry is
  'Road-following line for this route as a JSON array of [lat, lon] pairs, '
  'derived from the ordered stops by an OSM routing service. Regenerate when '
  'route_geometry_signature stops matching the current stops.';

-- READ access only for app users. Geometry is written by an admin tool or a
-- one-off job, never by the client — a client-writable geometry column is a
-- client-writable map.
--
-- NOTE: no policy is created here on purpose. `transport_routes` already has
-- RLS policies, and this column is covered by the existing SELECT policy. If
-- you decide a specific write path is needed, that is a separate, deliberate
-- change and should be reviewed on its own.

-- BACKFILL is NOT included. Populating this means calling the routing service
-- 21 times from a trusted context (an edge function or a local script), which
-- is a task to run once and check, not a migration side effect.
