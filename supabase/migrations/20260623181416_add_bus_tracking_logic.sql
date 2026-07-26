-- 1. Bus Tracking Tables
CREATE TABLE IF NOT EXISTS bus_routes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text
);

CREATE TABLE IF NOT EXISTS bus_stops (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  route_id uuid REFERENCES bus_routes(id) ON DELETE CASCADE,
  name text NOT NULL,
  lat numeric(10,8),
  lng numeric(11,8),
  stop_order int
);

CREATE TABLE IF NOT EXISTS buses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  route_id uuid REFERENCES bus_routes(id),
  bus_number text UNIQUE NOT NULL,
  driver_name text,
  driver_profile_id uuid REFERENCES profiles(id),
  capacity int
);

CREATE TABLE IF NOT EXISTS bus_live_locations (
  bus_id uuid PRIMARY KEY REFERENCES buses(id) ON DELETE CASCADE,
  lat numeric(10,8),
  lng numeric(11,8),
  heading numeric(5,2),
  speed numeric(5,2),
  updated_at timestamp with time zone DEFAULT now()
);

-- 2. Enable RLS
ALTER TABLE bus_routes ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_stops ENABLE ROW LEVEL SECURITY;
ALTER TABLE buses ENABLE ROW LEVEL SECURITY;
ALTER TABLE bus_live_locations ENABLE ROW LEVEL SECURITY;

-- 3. RLS Policies
-- Read access for all
CREATE POLICY public_read_routes ON bus_routes FOR SELECT TO authenticated USING (true);
CREATE POLICY public_read_stops ON bus_stops FOR SELECT TO authenticated USING (true);
CREATE POLICY public_read_buses ON buses FOR SELECT TO authenticated USING (true);
CREATE POLICY public_read_locations ON bus_live_locations FOR SELECT TO authenticated USING (true);

-- Driver write access (Upsert)
CREATE POLICY driver_write_location ON bus_live_locations FOR INSERT TO authenticated 
WITH CHECK (EXISTS (SELECT 1 FROM buses WHERE buses.id = bus_live_locations.bus_id AND buses.driver_profile_id = auth.uid()));

CREATE POLICY driver_update_location ON bus_live_locations FOR UPDATE TO authenticated 
USING (EXISTS (SELECT 1 FROM buses WHERE buses.id = bus_live_locations.bus_id AND buses.driver_profile_id = auth.uid()));
