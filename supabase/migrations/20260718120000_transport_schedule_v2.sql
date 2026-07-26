-- =====================================================================
--  AFOS — Transport schedule v2
--  Reworks transport_routes to hold the real DIU transport-schedule shape:
--  a semester + schedule_type (regular / shuttle / friday), and per-trip
--  objects {time, note, status} for each direction (To DSC / From DSC) so
--  trip notes/exceptions and "coming soon" trips are first-class instead of
--  bare time strings. Adds a per-import metadata row for the "Schedule for
--  <semester> · Updated <date>" header.
--
--  Migration is additive-then-drop-legacy, in strict order:
--    1. add new columns
--    2. backfill from the legacy string-array columns
--    3. swap the natural key (route_number  ->  semester+schedule_type+route_number)
--    4. DROP the legacy columns (departure_times, to_dsc_times, from_dsc_times)
--
--  RLS is unchanged: transport_routes keeps its existing admin write gate
--  (admin_write_routes); the new meta table mirrors it. transport_stops and
--  transport_live_status are untouched.
-- =====================================================================

-- 1. New columns -------------------------------------------------------
ALTER TABLE transport_routes
  ADD COLUMN IF NOT EXISTS semester      TEXT,
  ADD COLUMN IF NOT EXISTS schedule_type TEXT NOT NULL DEFAULT 'regular',
  ADD COLUMN IF NOT EXISTS imported_at   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS to_dsc_trips   JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS from_dsc_trips JSONB NOT NULL DEFAULT '[]'::jsonb;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'transport_routes_schedule_type_chk'
  ) THEN
    ALTER TABLE transport_routes
      ADD CONSTRAINT transport_routes_schedule_type_chk
      CHECK (schedule_type IN ('regular','shuttle','friday'));
  END IF;
END $$;

-- 2. Backfill new columns from the legacy string arrays ----------------
--    Each legacy "HH:MM"/"7:00 AM" string becomes {time, note:null, status:'scheduled'}.
UPDATE transport_routes SET
  to_dsc_trips = COALESCE((
    SELECT jsonb_agg(jsonb_build_object('time', elem, 'note', NULL, 'status', 'scheduled'))
    FROM jsonb_array_elements_text(COALESCE(to_dsc_times, '[]'::jsonb)) AS elem
  ), '[]'::jsonb),
  from_dsc_trips = COALESCE((
    SELECT jsonb_agg(jsonb_build_object('time', elem, 'note', NULL, 'status', 'scheduled'))
    FROM jsonb_array_elements_text(COALESCE(from_dsc_times, '[]'::jsonb)) AS elem
  ), '[]'::jsonb),
  semester    = COALESCE(semester, 'legacy-import'),
  imported_at = COALESCE(imported_at, updated_at, NOW())
WHERE TRUE;

-- 3. Swap the natural key ---------------------------------------------
--    route_number is only unique WITHIN a (semester, schedule_type); the
--    Friday section reuses F-numbering and shuttle continues R-numbering.
ALTER TABLE transport_routes DROP CONSTRAINT IF EXISTS transport_routes_route_number_key;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'transport_routes_semester_type_number_key'
  ) THEN
    ALTER TABLE transport_routes
      ADD CONSTRAINT transport_routes_semester_type_number_key
      UNIQUE (semester, schedule_type, route_number);
  END IF;
END $$;

-- 4. Drop the legacy columns (replaced by to_dsc_trips / from_dsc_trips)
ALTER TABLE transport_routes
  DROP COLUMN IF EXISTS departure_times,
  DROP COLUMN IF EXISTS to_dsc_times,
  DROP COLUMN IF EXISTS from_dsc_times;

-- 5. Import metadata table --------------------------------------------
--    One row per import; is_current flags the schedule the app should show.
CREATE TABLE IF NOT EXISTS transport_schedule_meta (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  semester     TEXT NOT NULL,
  campus       TEXT,
  imported_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  uploaded_by  UUID REFERENCES profiles(id),
  is_current   BOOLEAN NOT NULL DEFAULT TRUE
);
ALTER TABLE transport_schedule_meta ENABLE ROW LEVEL SECURITY;

-- Any authenticated user can read the current schedule metadata.
DROP POLICY IF EXISTS "auth_read_transport_meta" ON transport_schedule_meta;
CREATE POLICY "auth_read_transport_meta" ON transport_schedule_meta
  FOR SELECT TO authenticated USING (TRUE);

-- Writes gated to the same admin set as transport_routes (mirrors
-- admin_write_routes from 20260715120000; RLS is NOT loosened).
DROP POLICY IF EXISTS "admin_write_transport_meta" ON transport_schedule_meta;
CREATE POLICY "admin_write_transport_meta" ON transport_schedule_meta FOR ALL TO authenticated USING (
  EXISTS (SELECT 1 FROM profiles
          WHERE profiles.id = auth.uid()
            AND profiles.is_verified
            AND (profiles.role = ANY (ARRAY['admin','teacher','dept_admin','super_admin'])
                 OR caller_can('transport','upload')))
);

-- Live header updates when a new schedule is imported.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'transport_schedule_meta'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE transport_schedule_meta;
  END IF;
END $$;
