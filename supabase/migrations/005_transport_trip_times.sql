-- ══════════════════════════════════════════════════════════════════════
--  AFOS — Transport: real DIU sheet shape (Route No / Start Time (To DSC) /
--  Route Name / Route Details / Departure Time (From DSC)), multiple trip
--  rows per route, stops embedded as "<>"-separated free text — not a
--  stop x time grid. Adds explicit to/from trip time lists.
-- ══════════════════════════════════════════════════════════════════════

ALTER TABLE transport_routes ADD COLUMN IF NOT EXISTS to_dsc_times JSONB DEFAULT '[]'::jsonb;
ALTER TABLE transport_routes ADD COLUMN IF NOT EXISTS from_dsc_times JSONB DEFAULT '[]'::jsonb;
ALTER TABLE transport_routes ADD COLUMN IF NOT EXISTS route_details TEXT;
