-- Three place names had no coordinates, and that broke the drawn path of
-- every active route they appear on.
--
-- WHAT WAS WRONG. `_MapTab` builds its polyline from `transport_stops`, and
-- drops any stop whose latitude/longitude is null:
--
--     .where((s) => s['latitude'] != null && s['longitude'] != null)
--
-- That is a silent skip, not an error. So a route containing an ungeocoded
-- stop still drew a line — just one that cut the corner straight past the
-- missing stop, with no dot where the bus actually stops. Nothing anywhere
-- said a stop had been left out.
--
-- Six such rows existed across the ACTIVE network, and they were only THREE
-- distinct places:
--
--   Charabag         4 active routes (Baipail, C&B, Dhamrai, Savar)
--   Kohinur Market   1 active route  (Dhamrai Bus Stand <> Nabinagar <> C&B)
--   Mirpur Konabari  1 active route  (Dhanmondi <> DSC)
--
-- So three lookups repair the drawn geometry of the entire active network.
-- The parser was never at fault: all 21 active routes already agree between
-- their `stops` jsonb and `transport_stops`, and all of them have full trips.
--
-- WHERE THESE COORDINATES COME FROM, AND HOW THEY WERE CHECKED.
--
-- Each was resolved against OpenStreetMap (Nominatim) and then validated
-- against the stop's own NEIGHBOURS on the route, which is the check that
-- actually matters — a geocoder will happily return a same-named place in the
-- wrong district, and on this data that error would be invisible.
--
--   Charabag -> 23.8859260, 90.3108332
--     "Charabag More Bus Stop", Anwar Jang Sarak, C&B, Ashulia Model Town,
--     Savar. Corroborated by a second OSM feature 40 m away ("Charabag
--     Glorious School", 23.8855088/90.3112054). Sits on the Birulia-Akran
--     corridor between Kolma (23.8830/90.2882) and Daffodil Smart City
--     (23.8756/90.3203), which is exactly where all four routes place it.
--
--   Kohinur Market -> 23.9157000, 90.2359593
--     "Kohinur Gate Bus Stop", Dhaka-Aricha Highway, Savar. Falls inside the
--     box formed by its two neighbours on the only route that uses it --
--     Dhamrai Bus Stand (23.9051/90.2200) and Gonosastho (23.9180/90.2449) --
--     in both latitude and longitude.
--
--   Mirpur Konabari -> 23.7950603, 90.3482823
--     "Konabari Bus Stop", Mirpur Beribadh Road, Bishil. Its neighbours are
--     Majar Road Gabtoli (23.7877/90.3480) and Eastern Housing
--     (23.8298/90.3501); this lands between them and on the same road. OSM
--     also names the adjacent stop "Mazar Road Konabari", matching the
--     preceding stop's own name in our data.
--
-- MATCHED BY NAME, NOT BY ROW. The same physical place is stored once per
-- route, so Charabag alone is 7 rows. Fixing the 6 rows that happen to sit on
-- active routes would leave the identical place ungeocoded elsewhere and
-- reintroduce the gap the moment a route is reactivated.
--
-- STILL UNGEOCODED AFTER THIS: 18 rows, every one of them on an INACTIVE
-- route only (Mirpur/Uttara/Tongi names from the retired import). No user can
-- see those today. They are left for the same pass that resolves the
-- jsonb-vs-table drift on those 19 retired routes, because geocoding rows
-- whose stop list is itself in dispute would just freeze one of two
-- disagreeing sources in place.

update transport_stops set latitude = 23.8859260, longitude = 90.3108332
 where stop_name = 'Charabag' and (latitude is null or longitude is null);

update transport_stops set latitude = 23.9157000, longitude = 90.2359593
 where stop_name = 'Kohinur Market' and (latitude is null or longitude is null);

update transport_stops set latitude = 23.7950603, longitude = 90.3482823
 where stop_name = 'Mirpur Konabari' and (latitude is null or longitude is null);

-- Fail loudly rather than shipping a half-applied fix: after this migration no
-- stop on an ACTIVE route may lack coordinates. If a future import adds one,
-- this migration's guarantee is what should break first.
do $$
declare missing int;
begin
  select count(*) into missing
    from transport_stops s
    join transport_routes r on r.id = s.route_id
   where r.is_active and (s.latitude is null or s.longitude is null);
  if missing > 0 then
    raise exception 'still % ungeocoded stop(s) on active routes', missing;
  end if;
end $$;
