-- DSC == Daffodil Smart City. One place, one canonical name, no duplicate routes.
--
-- The app's PARSER has understood this for a while (`_isDsc()` in
-- transport_grid_parser.dart matches both spellings, and `kCanonicalDestination`
-- = 'Daffodil Smart City'). What was never cleaned up is the DATA that predates
-- that parser -- so the database still disagreed with itself, which is what made
-- the app look like it did not know the two names are the same place.
--
-- ============================================================================
-- 1. Retire the stale `legacy-import` batch (19 active routes from 2026-07-03).
--
-- TransportImportService.write only prunes within the same
-- (semester, schedule_type) key, so the Summer-2026 upload on 2026-07-19 never
-- swept the older batch. The result was 40 active routes where there should be
-- 21 -- every route present twice, once per naming convention. THAT is the
-- "app doesn't know they're the same place" symptom.
--
-- Verified safe before writing this, twice, because getting it wrong loses
-- routes:
--   * Matching by route_number across ALL Summer-2026 schedule types (not just
--     'regular' -- F1..F5 are Friday routes and R11/R12/R14/R15 are shuttles)
--     accounts for all 19.
--   * Matching by ORIGIN LOCATION rather than number, because the numbers were
--     reused with different meanings between batches (legacy R11 = "Mirpur-1",
--     Summer-2026 R11 = "Tongi station route"). All 14 distinct legacy origins
--     -- baipail, dhamrai bus stand, dhanmondi, ecb chattor, konabari pukur par,
--     middle badda, mirpur, narayanganj chasara, savar, tongi college gate,
--     tongi station route, uttara, uttara center metro rail, uttara moylar mor
--     -- are present in Summer-2026. Nothing is lost.
--
-- is_active = false, NOT a DELETE: reversible, and it keeps the history of what
-- ran in a previous semester.
-- ============================================================================

update transport_routes
   set is_active = false,
       updated_at = now()
 where is_active
   and semester = 'legacy-import';

-- ============================================================================
-- 2. Repair welded stop names.
--
-- The old importer split Route Details on a separator it got wrong, which
-- welded the terminal campus stop onto the FIRST stop of the next route --
-- 'DSC Baipail', 'DSC ECB Chattor', 'DSC Dhanmondi - Sobhanbag', and one welded
-- the other way round, 'Daffodil Smart City Tongi station route'.
--
-- Order matters: the exact-match canonicalisation runs FIRST, so that the
-- prefix-stripping rules below (which require trailing text) cannot eat a row
-- that is legitimately just the campus itself. The 17 rows already reading
-- exactly 'Daffodil Smart City' are left untouched by all three statements.
--
-- transport_stops has no unique constraint on stop_name (checked), so collapsing
-- names cannot violate one.
-- ============================================================================

-- 2a. Bare shorthand -> canonical.
update transport_stops
   set stop_name = 'Daffodil Smart City'
 where btrim(stop_name) = 'DSC';

-- 2b. 'DSC <somewhere>' -> '<somewhere>'. The \S guard means a row that is only
--     'DSC' (already handled above) can never match.
update transport_stops
   set stop_name = btrim(regexp_replace(stop_name, '^DSC\s+', '', 'i'))
 where stop_name ~* '^DSC\s+\S';

-- 2c. Same weld, other spelling: 'Daffodil Smart City <somewhere>' ->
--     '<somewhere>'. Again guarded so the plain canonical rows are untouched.
update transport_stops
   set stop_name = btrim(regexp_replace(stop_name, '^Daffodil\s+Smart\s+City\s+', '', 'i'))
 where stop_name ~* '^Daffodil\s+Smart\s+City\s+\S';

-- ============================================================================
-- 3. Canonicalise the shorthand inside ACTIVE route names.
--
-- Display already normalises this (`_displayRouteName`), but only in
-- transport_screen -- anything else reading route_name (search, notifications,
-- the import preview) saw the raw 'DSC'. Normalising at rest means every reader
-- agrees, instead of each one needing to remember to canonicalise.
--
-- \m and \M are Postgres word boundaries, so this cannot corrupt a word that
-- merely contains those letters.
-- ============================================================================

update transport_routes
   set route_name = regexp_replace(route_name, '\mDSC\M', 'Daffodil Smart City', 'gi'),
       updated_at = now()
 where is_active
   and route_name ~* '\mDSC\M';
