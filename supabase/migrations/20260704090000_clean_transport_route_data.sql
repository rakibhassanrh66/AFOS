-- =====================================================================
--  AFOS — Clean up bad transport_routes data from a prior imperfect parse
--
--  Found live: R10's "Middle Badda" stop had a stray "<" character stuck
--  to it (cleanName() didn't strip angle brackets — fixed in the
--  parse-routine edge function). Also found three junk rows that are not
--  real routes at all: a literal repeated header ("Route No"/"Route
--  Name"/"Route Details") and two section-label rows ("Friday Schedule @
--  DSC", "Shuttle service") that got ingested as if they were routes —
--  also fixed at the parser level (isRealRoute filter) so future uploads
--  won't reintroduce these, but the already-live bad rows need a direct
--  cleanup since nothing will re-upload them automatically.
-- =====================================================================

UPDATE transport_routes
SET stops = (
  SELECT jsonb_agg(
    CASE WHEN (elem->>'name') LIKE '<%'
         THEN jsonb_set(elem, '{name}', to_jsonb(ltrim(elem->>'name', '<')))
         ELSE elem
    END
  )
  FROM jsonb_array_elements(stops) AS elem
)
WHERE route_number = 'R10';

DELETE FROM transport_routes
WHERE route_number IN ('Route No', 'Friday Schedule @ DSC', 'Shuttle service');
