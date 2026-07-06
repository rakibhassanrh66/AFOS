-- Corrected against more precise real information: male halls are Yunus
-- Khan Scholar Garden (YKSG) with THREE buildings, not two — YKSG-2 is a
-- 10-floor building holding 1000+ students specifically. Female halls are
-- Rowshan Ara Scholar Garden (RASG) with two buildings. Fixes the earlier
-- spelling ("Younus" -> "Yunus", "Scholars'" -> "Scholar") and adds the
-- missing third male building. Also adds a shared amenities list (24/7
-- security, wifi, dining, medical room, gym, laundry) described for every
-- hall.
ALTER TABLE halls ADD COLUMN IF NOT EXISTS amenities text[];

UPDATE halls SET name = 'Yunus Khan Scholar Garden-1', capacity = 500,
  amenities = ARRAY['24/7 security', 'Wi-Fi', 'Dining space', 'Medical room', 'Gym', 'Laundry']
  WHERE name = 'Younus Khan Scholars'' Garden - Hostel 1';
UPDATE halls SET name = 'Yunus Khan Scholar Garden-2', capacity = 1000,
  amenities = ARRAY['24/7 security', 'Wi-Fi', 'Dining space', 'Medical room', 'Gym', 'Laundry']
  WHERE name = 'Younus Khan Scholars'' Garden - Hostel 2';
UPDATE halls SET name = 'Rowshan Ara Scholar Garden-1',
  amenities = ARRAY['24/7 security', 'Wi-Fi', 'Dining space', 'Medical room', 'Gym', 'Laundry']
  WHERE name = 'Rowshan Ara Scholar Garden - 1';
UPDATE halls SET name = 'Rowshan Ara Scholar Garden-2',
  amenities = ARRAY['24/7 security', 'Wi-Fi', 'Dining space', 'Medical room', 'Gym', 'Laundry']
  WHERE name = 'Rowshan Ara Scholar Garden - 2';

INSERT INTO halls (name, gender, capacity, amenities) VALUES
  ('Yunus Khan Scholar Garden-3', 'male', 500,
   ARRAY['24/7 security', 'Wi-Fi', 'Dining space', 'Medical room', 'Gym', 'Laundry'])
ON CONFLICT (name) DO NOTHING;
