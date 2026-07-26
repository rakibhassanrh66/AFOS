-- Expose the new halls.amenities column through the availability view too.
CREATE OR REPLACE VIEW hall_availability AS
SELECT
  h.id, h.name, h.gender, h.capacity,
  h.capacity - COALESCE(occupied.cnt, 0) AS available,
  h.amenities
FROM halls h
LEFT JOIN (
  SELECT preferred_hall, count(*) AS cnt
  FROM hall_applications
  WHERE status IN ('approved', 'cancel_requested')
  GROUP BY preferred_hall
) occupied ON occupied.preferred_hall = h.name
WHERE h.is_active;
