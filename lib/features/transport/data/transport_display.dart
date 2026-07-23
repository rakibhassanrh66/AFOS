/// Pure presentation logic for the transport screen — stop identity, route
/// ordering, and the Google Maps hand-off.
///
/// Lives in `data/` beside [StopTimeCalculator] rather than inside
/// `transport_screen.dart` so every rule here is directly unit-testable. Each
/// one exists because of a specific defect found in the live data; the doc
/// comments name it so a future change can't quietly undo the fix.
library;

/// Normalized identity for a stop name: lower-cased with every non-alphanumeric
/// character dropped, so "Mirpur 10" and "Mirpur-10" resolve to one place.
///
/// This is a live mismatch, not a hypothetical. Route R4 spells the stop
/// "Mirpur 10" and F5 spells it "Mirpur-10", so the Find-Route picker listed it
/// **twice** and picking either entry matched only one of the two routes — a
/// Friday rider searching for Mirpur 10 was told "No route stops there yet".
String stopKey(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Title-cases a stop name that arrived entirely lower-case, and leaves every
/// other name exactly as imported.
///
/// Five stops in the live data were typed in lower case — "gulistan",
/// "kolabagan", "saydabad bus stand", "sign board", "sonir akhra" — and they
/// looked like broken rows next to "ECB Chattor" and "Dhanmondi - Sobhanbag".
///
/// The "no upper-case at all" guard is what makes this safe: deliberate casing
/// like "C&B", "JU", "ECB Chattor" and "Mirpur-10" is never touched, so this
/// can only ever fix the names that were unambiguously mis-entered.
///
/// Purely cosmetic by construction. Stop identity everywhere else goes through
/// [stopKey] or `StopOffset.keyFor`, both of which lower-case first, so
/// changing display case cannot affect matching or offset lookups.
String prettyStop(String s) {
  if (s.isEmpty || s.contains(RegExp(r'[A-Z]'))) return s;
  return s.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}

/// Natural ordering for route numbers, so "R2" sorts before "R10".
///
/// The repository asks Postgres for `order by route_number`, which is
/// lexicographic on text — the live list really does arrive R1, R10, R2, R3 …
/// with R10 wedged between R1 and R2, in both All Routes and the My Route
/// picker. Sorting on the numeric part fixes both call sites at once.
int compareRouteNumbers(String a, String b) {
  final ma = RegExp(r'^([A-Za-z]*)0*(\d*)').firstMatch(a)!;
  final mb = RegExp(r'^([A-Za-z]*)0*(\d*)').firstMatch(b)!;
  final byPrefix = ma.group(1)!.toLowerCase().compareTo(mb.group(1)!.toLowerCase());
  if (byPrefix != 0) return byPrefix;
  final na = int.tryParse(ma.group(2)!);
  final nb = int.tryParse(mb.group(2)!);
  // A number always sorts before a numberless oddity, and equal numbers fall
  // through to raw text so the ordering stays total and stable.
  if (na != null && nb == null) return -1;
  if (na == null && nb != null) return 1;
  if (na != null && nb != null && na != nb) return na.compareTo(nb);
  return a.toLowerCase().compareTo(b.toLowerCase());
}

/// Lower-cases and reduces every run of non-alphanumerics to a single space,
/// so "Mirpur-10", "Mirpur 10" and "MIRPUR  10" all normalize identically.
String searchNormalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Scores [label] against a search [query]. Returns **null** when it does not
/// match at all; otherwise 0 (best) to 3 (weakest), for ranking.
///
/// Fixes three real failures of the previous plain
/// `label.toLowerCase().contains(query)`:
///
///  * **Punctuation.** Typing "mirpur10" or "mirpur-10" found nothing, because
///    the stop is stored "Mirpur 10". Typing "cb" missed "C&B". Both sides are
///    now normalized, and a space-free form is compared too.
///  * **Word order.** "sony mirpur" found nothing, because a single substring
///    test cannot span "Mirpur 01 - Sony Cinema Hall". Every query token must
///    now appear, in any order.
///  * **Ranking.** With 79 stops, "mirpur" returned 7 hits in alphabetical
///    order, so the exact "Mirpur 10" sat below "Mirpur 01 - Sony Cinema Hall".
///    Exact and prefix matches now sort first.
int? searchScore(String label, String query) {
  final q = searchNormalize(query);
  if (q.isEmpty) return 3;
  final l = searchNormalize(label);
  final lCompact = l.replaceAll(' ', '');
  final qCompact = q.replaceAll(' ', '');
  // Every token must be present somewhere, in any order.
  for (final token in q.split(' ')) {
    if (!l.contains(token) && !lCompact.contains(token)) return null;
  }
  if (l == q || lCompact == qCompact) return 0;
  if (l.startsWith(q) || lCompact.startsWith(qCompact)) return 1;
  final firstToken = q.split(' ').first;
  if (l.split(' ').any((w) => w.startsWith(firstToken))) return 2;
  return 3;
}

/// Filters and ranks [items] by [query] using [searchScore], keeping the
/// original relative order within an equal score (so an already-sorted list
/// stays stable). An empty query returns everything untouched.
List<T> searchRank<T>(List<T> items, String query, String Function(T) labelOf) {
  if (searchNormalize(query).isEmpty) return items;
  final scored = <({T item, int score, int index})>[];
  for (var i = 0; i < items.length; i++) {
    final s = searchScore(labelOf(items[i]), query);
    if (s != null) scored.add((item: items[i], score: s, index: i));
  }
  scored.sort((a, b) => a.score != b.score ? a.score.compareTo(b.score) : a.index.compareTo(b.index));
  return scored.map((e) => e.item).toList();
}

/// Region appended to every stop name before Google geocodes it.
///
/// This used to be plain "Dhaka", which is what produced the wrong pins the
/// user reported: most of this network's stops are **not** in Dhaka city.
/// Checked against the live route data — "Tongi College Gate Bus Stand" and
/// "Konabari Pukur Par" are in Gazipur, "Narayanganj Chasara" is in
/// Narayanganj, and "Baipail", "Zirabo", "Ashulia Bazar", "Nabinagar",
/// "Dhamrai Bus Stand", "Savar" and campus itself are Savar/Dhamrai/Ashulia.
/// Forcing ", Dhaka" onto those makes Google prefer a similarly-named place
/// inside the city instead of the real stop.
///
/// "Dhaka Division" is the smallest administrative region that genuinely
/// contains every stop on this network (the Dhaka, Gazipur, Narayanganj and
/// Savar districts are all inside it), so it disambiguates without relocating
/// anything.
const String mapsRegion = 'Dhaka Division, Bangladesh';

/// Google's Maps URLs API accepts at most **nine** waypoints. Past that the
/// directions link is rejected rather than trimmed, so the longest routes — the
/// ones most worth mapping — were exactly the ones that silently failed. Live
/// data: R9 has 17 stops, R10 has 16, R4 13, R7 12.
const int maxMapsWaypoints = 9;

String _place(String stop) => Uri.encodeComponent('$stop, $mapsRegion');

/// Evenly samples [middle] down to at most [maxMapsWaypoints] entries.
///
/// Deliberately spreads the picks along the route instead of taking the first
/// nine, which would draw R9 only as far as Dhanmondi and then jump straight to
/// campus, hiding the whole back half of the journey. Always keeps the first
/// and last intermediate stop.
List<String> sampleWaypoints(List<String> middle) {
  if (middle.length <= maxMapsWaypoints) return middle;
  final step = (middle.length - 1) / (maxMapsWaypoints - 1);
  return [for (var i = 0; i < maxMapsWaypoints; i++) middle[(i * step).round()]];
}

/// Builds the Google Maps link for a route, given its ordered stop names.
///
/// Name-based rather than coordinate-based on purpose: no stop on an active
/// route has GPS coordinates (all 183 rows in `transport_stops` belong to the
/// retired legacy import), so names are the only location data that exists.
/// Returns null when there is nothing to show.
Uri? googleMapsRouteUrl(List<String> stopNames) {
  final stops = stopNames.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (stops.isEmpty) return null;
  if (stops.length == 1) {
    // Nothing to route between — drop a pin on the one place we know.
    return Uri.parse('https://www.google.com/maps/search/?api=1&query=${_place(stops.first)}');
  }
  final waypoints = sampleWaypoints(stops.sublist(1, stops.length - 1)).map(_place).join('|');
  return Uri.parse('https://www.google.com/maps/dir/?api=1'
      '&origin=${_place(stops.first)}&destination=${_place(stops.last)}'
      '${waypoints.isNotEmpty ? '&waypoints=$waypoints' : ''}&travelmode=driving');
}
