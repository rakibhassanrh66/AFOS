-- Real, previously-undetected bug: parse-routine's transport upsert
-- silently dropped to_dsc_times/from_dsc_times on the wrong assumption
-- they weren't real transport_routes columns (fixed in this session's edge
-- function deploy). The live effect: 16 of 18 active routes have an empty
-- to_dsc_times while the real "to DSC" schedule sits in departure_times
-- instead -- the Transport screen's "Departure Times (To DSC)" panel has
-- been showing blank/"no trip times" for the overwhelming majority of
-- routes. Backfill immediately rather than waiting on the next re-upload.
update transport_routes
set to_dsc_times = departure_times
where (to_dsc_times is null or jsonb_array_length(to_dsc_times) = 0)
  and departure_times is not null and jsonb_array_length(departure_times) > 0;
