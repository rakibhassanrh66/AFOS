-- =====================================================================
--  AFOS — Transport stop-to-stop route finding
--  transport_routes previously only stored a flat departure_times list
--  with no notion of stops, so there was no way to answer "which bus
--  goes from my stop to campus, and when". Add an ordered `stops` list
--  per route: [{ "name": "Mirpur-10", "time": "07:30" }, ...] in travel
--  order, so the client can find every route containing both a chosen
--  origin and destination (origin appearing before destination) and
--  show its departure/arrival time at each.
-- =====================================================================

ALTER TABLE transport_routes ADD COLUMN IF NOT EXISTS stops jsonb DEFAULT '[]'::jsonb;
