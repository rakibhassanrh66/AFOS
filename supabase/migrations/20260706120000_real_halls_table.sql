-- The Apply-for-Hall dropdown used 4 hardcoded, entirely fictional hall
-- names ('Ahsanullah Hall', 'Bangabandhu Hall', 'Pritilata Hall', 'Sheikh
-- Hasina Hall' — real hall names from other Bangladeshi universities, not
-- DIU). Replaces them with a real reference table seeded with DIU's actual
-- Daffodil Smart City residential halls (confirmed via daffodilvarsity.edu.bd
-- and the university's own hostel-booking references): Younus Khan
-- Scholars' Garden (boys, two hostel buildings) and Rowshan Ara Scholar
-- Garden (girls, two buildings). Capacity figures are reasonable estimates,
-- not officially published numbers — a super_admin can correct them later
-- via a direct update once exact figures are known; this is about fixing
-- the fictional names and adding a real, dynamic (not hardcoded-in-Dart)
-- source of truth with computable live availability, not claiming exact
-- official capacity numbers.
CREATE TABLE IF NOT EXISTS halls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  gender text NOT NULL CHECK (gender IN ('male', 'female')),
  capacity integer NOT NULL DEFAULT 500,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE halls ENABLE ROW LEVEL SECURITY;

CREATE POLICY auth_read_halls ON halls FOR SELECT USING (true);
CREATE POLICY admin_write_halls ON halls FOR ALL USING (
  EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid()
    AND profiles.role = ANY (ARRAY['admin', 'super_admin']))
);

INSERT INTO halls (name, gender, capacity) VALUES
  ('Younus Khan Scholars'' Garden - Hostel 1', 'male', 500),
  ('Younus Khan Scholars'' Garden - Hostel 2', 'male', 500),
  ('Rowshan Ara Scholar Garden - 1', 'female', 400),
  ('Rowshan Ara Scholar Garden - 2', 'female', 400)
ON CONFLICT (name) DO NOTHING;

ALTER PUBLICATION supabase_realtime ADD TABLE halls;
