import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/services/local_cache_service.dart';

/// Turns an ordered list of bus stops into a line that **follows actual roads**.
///
/// THE BUG THIS EXISTS TO FIX. The map drew `Polyline(points: stops)` — straight
/// segments between raw stop coordinates. That is why the route read as
/// "geometrical and dumb": a bus route through Dhaka rendered as a handful of
/// chords cutting across blocks, rivers and the campus itself. No amount of
/// stroke styling fixes that, because the geometry is wrong, not the paint.
///
/// ---------------------------------------------------------------------------
/// WHY OSRM'S PUBLIC DEMO SERVER, stated plainly with its terms
///
/// Candidates were OSRM (public demo), OpenRouteService, GraphHopper, Valhalla
/// and Mapbox Directions. All the open ones route on OpenStreetMap data, so
/// Dhaka coverage is broadly equivalent between them and not the deciding
/// factor.
///
/// **The deciding factor is that this repository is PUBLIC.** OpenRouteService
/// (2,500 req/day, 40,000/month), GraphHopper and Mapbox all require an API key.
/// A key cannot be committed here, and a routing key injected at build time via
/// `--dart-define` is a release-process change for a value that buys us nothing
/// at our volume. OSRM's demo server needs **no key at all**.
///
/// Its published terms, which this class is built to respect rather than skirt:
///  * **≤ 1 request per second.** Enforced below by [_gate] — every request in
///    the app funnels through one serialized queue with a 1.1s floor.
///  * **Reasonable, non-commercial use.** AFOS is a university facilities app,
///    not a product being sold. Selling access is forbidden and we do not.
///  * **No uptime, latency or freshness guarantee, and access may be withdrawn
///    at any time without a reason.** This is the real risk, and it is why the
///    fallback chain below is not optional decoration: the map must still work
///    the day the demo server says no.
///
/// At our volume this is close to free: 21 routes, geometry that changes only
/// when an admin edits stops, and a cache keyed by the stop list. A device
/// fetches a given route's shape **once**, not once per app open.
///
/// **The upgrade path, if this ever outgrows the demo server:** get an
/// OpenRouteService key, inject it with `--dart-define=ORS_KEY=...`, and change
/// [_endpointFor]. Nothing else in this file or its callers changes. Better
/// still, apply `db/proposed/001_route_geometry_cache.sql` so the geometry is
/// fetched once for the whole university and served from our own database —
/// then the routing service is a build-time dependency, not a runtime one.
/// ---------------------------------------------------------------------------
class RouteGeometryService {
  RouteGeometryService._();

  /// What the map should draw, and whether it is the real thing.
  ///
  /// [snapped] false means these are the raw stop-to-stop chords — the caller
  /// must say so in the UI rather than present a straight line as the route.
  /// Silently degrading is how a wrong map becomes a trusted map.
  static ({List<LatLng> points, bool snapped}) _result(
          List<LatLng> points, bool snapped) =>
      (points: points, snapped: snapped);

  static final Dio _dio = Dio(BaseOptions(
    // Short. A route line is an enhancement over a drawable fallback, so
    // waiting 30s for it would make the map feel broken in exchange for a
    // prettier line nobody is still looking at.
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 8),
  ));

  static String _endpointFor(List<LatLng> stops) {
    // OSRM wants lon,lat — the opposite order to LatLng. Getting this backwards
    // returns a route somewhere in the Indian Ocean rather than an error, so it
    // is worth stating.
    final coords =
        stops.map((p) => '${p.longitude},${p.latitude}').join(';');
    return 'https://router.project-osrm.org/route/v1/driving/$coords'
        // full geometry, not the simplified overview: we are drawing the road,
        // and geojson saves us hand-decoding a precision-5 polyline.
        '?overview=full&geometries=geojson';
  }

  // ------------------------------------------------------------------ the gate
  //
  // One request at a time, at most one per 1.1 seconds, app-wide. The demo
  // server's limit is a rate we agreed to honour, not a number to approach —
  // and being throttled would cost us the geometry anyway.
  static Future<void> _lastCall = Future.value();
  static DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _minGap = Duration(milliseconds: 1100);

  static Future<T> _gate<T>(Future<T> Function() task) {
    final completer = _lastCall.then((_) async {
      final since = DateTime.now().difference(_lastAt);
      if (since < _minGap) await Future.delayed(_minGap - since);
      _lastAt = DateTime.now();
      return task();
    });
    // Keep the chain alive even when one link throws, or every later request
    // inherits the failure.
    _lastCall = completer.then((_) {}, onError: (_) {});
    return completer;
  }

  /// A cache key that changes when the STOPS change.
  ///
  /// Keyed on the coordinates, not on the route id alone: an admin who moves or
  /// reorders a stop must not keep getting the old shape back. Rounded to 5
  /// decimals (~1m) so floating-point noise in the same data does not look like
  /// an edit.
  static String _keyFor(String routeId, List<LatLng> stops) {
    final sig = stops
        .map((p) =>
            '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}')
        .join(';');
    return 'route_geometry_${routeId}_${sig.hashCode}';
  }

  /// Road-following geometry for [stops], cached.
  ///
  /// The fallback chain, in order — each step is a real state the UI can be in:
  ///  1. cached snapped geometry (the normal path after first view)
  ///  2. a live OSRM request
  ///  3. the raw stops, flagged `snapped: false` so the UI can label the line
  ///     approximate
  static Future<({List<LatLng> points, bool snapped})> forStops(
    String routeId,
    List<LatLng> stops,
  ) async {
    // OSRM needs at least an origin and a destination, and a 2-stop "route" on
    // a straight road is the same line either way.
    if (stops.length < 2) return _result(stops, false);

    final key = _keyFor(routeId, stops);
    final cached = LocalCacheService.instance.getMap(key);
    if (cached != null) {
      final pts = _decode(cached.data['points']);
      if (pts.length >= 2) return _result(pts, true);
    }

    try {
      final res = await _gate(() => _dio.get<dynamic>(_endpointFor(stops)));
      final body = res.data is String
          ? jsonDecode(res.data as String) as Map<String, dynamic>
          : Map<String, dynamic>.from(res.data as Map);

      if (body['code'] != 'Ok') return _result(stops, false);
      final routes = body['routes'] as List?;
      if (routes == null || routes.isEmpty) return _result(stops, false);

      final coords = (routes.first as Map)['geometry']?['coordinates'] as List?;
      if (coords == null || coords.length < 2) return _result(stops, false);

      // Back from lon,lat to LatLng.
      //
      // `as num` then `.toDouble()`, NOT `as double`: JSON gives an int for a
      // coordinate that happens to land on a whole number, and `as double`
      // throws on an int in Dart rather than coercing. That would have turned
      // one unlucky coordinate into a total fetch failure — and silently, since
      // the catch below just falls back to chords.
      final points = coords
          .whereType<List>()
          .where((c) => c.length >= 2 && c[0] is num && c[1] is num)
          .map((c) => LatLng(
                (c[1] as num).toDouble(),
                (c[0] as num).toDouble(),
              ))
          .toList();
      if (points.length < 2) return _result(stops, false);

      await LocalCacheService.instance.putMap(key, {
        'points': points
            .map((p) => [p.latitude, p.longitude])
            .toList(growable: false),
      });
      return _result(points, true);
    } catch (e) {
      // Down, rate-limited, offline, or withdrawn. Draw something rather than
      // nothing, and tell the truth about what it is.
      debugPrint('RouteGeometryService: falling back to stop chords ($e)');
      return _result(stops, false);
    }
  }

  static List<LatLng> _decode(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<List>()
        .map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()))
        .toList();
  }

  /// Douglas–Peucker simplification, for drawing a long route at a low zoom.
  ///
  /// A snapped Dhaka route is ~2,000 points. Every one of them is laid out and
  /// painted each frame, and at z11 most of them land inside the same pixel —
  /// so the cost is real and the fidelity is not. [toleranceDeg] is in degrees;
  /// roughly 1e-5 is a metre.
  static List<LatLng> simplify(List<LatLng> pts, double toleranceDeg) {
    if (pts.length < 3 || toleranceDeg <= 0) return pts;

    var maxDist = 0.0;
    var index = 0;
    for (var i = 1; i < pts.length - 1; i++) {
      final d = _perpendicularDistance(pts[i], pts.first, pts.last);
      if (d > maxDist) {
        maxDist = d;
        index = i;
      }
    }

    if (maxDist <= toleranceDeg) return [pts.first, pts.last];

    final left = simplify(pts.sublist(0, index + 1), toleranceDeg);
    final right = simplify(pts.sublist(index), toleranceDeg);
    return [...left.sublist(0, left.length - 1), ...right];
  }

  static double _perpendicularDistance(LatLng p, LatLng a, LatLng b) {
    final dx = b.longitude - a.longitude;
    final dy = b.latitude - a.latitude;
    if (dx == 0 && dy == 0) {
      return math.sqrt(math.pow(p.longitude - a.longitude, 2) +
          math.pow(p.latitude - a.latitude, 2));
    }
    final t = ((p.longitude - a.longitude) * dx + (p.latitude - a.latitude) * dy) /
        (dx * dx + dy * dy);
    final clamped = t.clamp(0.0, 1.0);
    final projX = a.longitude + clamped * dx;
    final projY = a.latitude + clamped * dy;
    return math.sqrt(math.pow(p.longitude - projX, 2) +
        math.pow(p.latitude - projY, 2));
  }
}
