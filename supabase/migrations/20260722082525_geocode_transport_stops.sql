-- Coordinates for the transport network's stops, so the map can finally draw a
-- route polyline and place stop pins (see migration 20260722072545, which made
-- `transport_stops` populated and writable in the first place).
--
-- Geocoded once via the Google Geocoding API v4 and validated before writing.
-- Three checks, because a bus stop pinned in the wrong place is worse than a
-- missing pin -- and "no wrong pin" was the explicit requirement:
--
--   1. Region bounds. Every stop on this network lies in Dhaka Division;
--      anything resolving outside lat 23.4-24.3 / lng 89.8-90.9 was rejected.
--      This caught "Kolma" (matched a Kalma in Sylhet) and "Paragram"
--      (matched a Paragram near Barisal).
--
--   2. Region-centroid fallback. Seven stops -- Bismail, C&B, Chankharpul,
--      Estern Mor, House building, Polli Biddut, Prantik -- all returned the
--      IDENTICAL coordinate 23.95357,90.14950, which is the centroid of Dhaka
--      Division itself: Google found nothing and handed back the region. Those
--      are indistinguishable from a real answer by status alone, and would have
--      dropped seven pins on an empty field near Dhamrai.
--
--   3. Route context. Consecutive stops on a bus route are close together, so a
--      stop far from BOTH its neighbours is a same-name match elsewhere. This is
--      what exposed the subtle ones: R6/R7 run Baipail > Nabinagar > JU > C&B
--      through Savar/Ashulia, but "Nabinagar" had matched Narayanganj's, 35 km
--      away; R4/R13 run through Mirpur, but "Gudaraghat" had matched
--      Narayanganj's; R10 runs Badda > Jamuna Future Park > Kuril, but
--      "Notun Bazar" had matched Siddhirganj's and "Kuril Bisso Road" had
--      matched "Basabo Bisso Rd"; and "gulistan" had matched *Gulshan*.
--      Each was re-queried with its route's locality as a hint.
--
-- Verified after applying: ZERO consecutive-stop hops longer than 12 km across
-- all 21 active routes, and all 21 have >= 2 placed stops, so every route can
-- draw a line.
--
-- 76 of 79 stops placed. Three are deliberately left NULL rather than guessed:
--   * Kohinur Market  -- keeps resolving ~20 km south of its R7 neighbours
--   * Mirpur Konabari -- keeps matching Konabari in GAZIPUR, not Mirpur
--   * Charabag        -- only ever matches the road named for its neighbour
--                        Kumkumari, so it has no distinct location
-- The app already renders a stop without coordinates honestly, and
-- `TransportImportService._syncStops` preserves coordinates across re-imports,
-- so these three can be filled in by hand later without being overwritten.

create temporary table _geo(stop_name text primary key, lat double precision, lng double precision) on commit drop;

insert into _geo(stop_name, lat, lng) values
  ('Akran',23.8603343,90.3072067),
  ('Ashulia Bazar',23.8971149,90.3308863),
  ('Badda Suvastu tower',23.7814334,90.4170902),
  ('Baipail',23.9325782,90.2784385),
  ('Bashabo',23.7426044,90.4307836),
  ('Beribadh',23.8248157,90.3437695),
  ('Birulia',23.8477331,90.3351107),
  ('Birulia Bus Stand',23.8506812,90.3411775),
  ('Bismail',23.895606,90.270935),
  ('C&B',23.8724113,90.2731743),
  ('Chankharpul',23.7237041,90.4005067),
  ('Commerce College',23.8070848,90.354656),
  ('Daffodil Smart City',23.8756013,90.3203018),
  ('Dhamrai Bus Stand',23.9051487,90.2200386),
  ('Dhanmondi - Sobhanbag',23.7554056,90.3765456),
  ('Dhour',23.8862902,90.3689508),
  ('Diyabari Bridge',23.8740431,90.3790494),
  ('Eastern Housing',23.8298204,90.3501258),
  ('Eastern Housing Rup Nogor',23.8205098,90.3555377),
  ('ECB Chattor',23.8225517,90.3934291),
  ('Estern Housing',23.8298204,90.3501258),
  ('Estern Mor',23.8697294,90.309887),
  ('Ghosbag',23.9206289,90.3066277),
  ('Gonosastho',23.9179674,90.2449484),
  ('Grand Zamzam Tower',23.8740618,90.3903604),
  ('Gudaraghat',23.8022189,90.3490521),
  ('gulistan',23.7228045,90.4133616),
  ('House building',23.874188,90.40073),
  ('Jamuna Future Park',23.8135411,90.4242393),
  ('JU',23.8818302,90.2624636),
  ('Kalshi More',23.8228327,90.3776604),
  ('Kamar Para',23.8892301,90.3830754),
  ('Khagan',23.874879,90.310977),
  ('kolabagan',23.7494231,90.3830754),
  ('Kolma',23.8829775,90.2882348),
  ('Konabari Bus Stop',23.7951301,90.3482875),
  ('Konabari Pukur Par',24.0112973,90.3219053),
  ('Kumkumari',23.8822709,90.3055992),
  ('Kuril Bisso Road',23.8211887,90.4195458),
  ('Majar Road Gabtoli',23.7876709,90.3479928),
  ('Malibagh Railgate (South Bus Stop)',23.7496015,90.4125881),
  ('Middle Badda',23.7798106,90.4237121),
  ('Mirpur 01 - Sony Cinema Hall',23.8003906,90.3553414),
  ('Mirpur 02',23.8336634,90.3746197),
  ('Mirpur 10',23.8028556,90.3748344),
  ('Mirpur 12',23.8280274,90.3640039),
  ('Mirpur-10',23.8028556,90.3748344),
  ('Mugda Medical College',23.731981,90.4301631),
  ('Nabinagar',23.912477,90.259787),
  ('Narayanganj Chasara',23.6263613,90.4992069),
  ('New Market',23.7331937,90.3837664),
  ('Nilkhet',23.7321134,90.3852486),
  ('Nobinagar',23.912477,90.259787),
  ('Norshingpur',23.930424,90.308329),
  ('Notun Bazar',23.7805462,90.4266584),
  ('Paragram',23.8787642,90.3367212),
  ('Polli Biddut',23.8964944,90.3267087),
  ('Prantik',23.8896752,90.2720048),
  ('Radio Colony',23.8578761,90.2640617),
  ('Rampura Bazar Bus Stop',23.7606706,90.4191967),
  ('Rampura Bridge',23.7680925,90.4232073),
  ('Savar',23.8479013,90.257699),
  ('Savar Bus Stand',23.8474877,90.2575424),
  ('saydabad bus stand',23.7159254,90.4258436),
  ('Shyamoli Square',23.7746596,90.365494),
  ('sign board',23.6918777,90.4814999),
  ('sonir akhra',23.7075811,90.4537748),
  ('Sony Cinema Hall',23.8003906,90.3553414),
  ('Technical Bus stand',23.7814677,90.3517409),
  ('Technical Mor',23.781384,90.351898),
  ('Tongi College Gate Bus Stand',23.889974,90.4073472),
  ('Tongi station route',23.8900689,90.4071462),
  ('Uttara - Rajlokkhi',23.8643746,90.399609),
  ('Uttara Metro rail Center',23.8596875,90.3651875),
  ('Uttara Moylar Mor',23.874052,90.3841088),
  ('Zirabo',23.9101983,90.3172039);

update public.transport_stops ts
set latitude = g.lat, longitude = g.lng
from _geo g
where g.stop_name = ts.stop_name;
