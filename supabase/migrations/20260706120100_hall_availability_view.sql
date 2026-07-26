-- Computes live available-seat count per hall (capacity minus everyone
-- currently holding or awaiting release of a seat there) so the Apply tab
-- can show real availability instead of a static name-only dropdown.
CREATE OR REPLACE VIEW hall_availability AS
SELECT
  h.id, h.name, h.gender, h.capacity,
  h.capacity - COALESCE(occupied.cnt, 0) AS available
FROM halls h
LEFT JOIN (
  SELECT preferred_hall, count(*) AS cnt
  FROM hall_applications
  WHERE status IN ('approved', 'cancel_requested')
  GROUP BY preferred_hall
) occupied ON occupied.preferred_hall = h.name
WHERE h.is_active;

GRANT SELECT ON hall_availability TO authenticated;
