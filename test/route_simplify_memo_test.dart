import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:afos_v7/features/transport/data/route_geometry_service.dart';

/// Douglas–Peucker is correct but expensive, and it was being run from
/// `build()`.
///
/// `_MapTabState.build` called `RouteGeometryService.simplify` directly on
/// what the service's own doc comment calls "~2,000 points" for a snapped
/// Dhaka route — recursive, allocating a fresh `sublist` at every level. It
/// re-ran on every rebuild: opening or closing a stop callout, the locate
/// button resolving, the one-minute `Timer.periodic` tick, any parent rebuild.
/// Each of those recomputed a list identical to the one already on screen.
///
/// The memo in `_MapTabState` is keyed on (route identity, tolerance). These
/// tests cover the two properties that make that key SOUND, because the memo
/// lives in a private State class where it cannot be reached directly:
///
///   1. `simplify` is pure — same inputs, same output — so caching is exact
///      rather than an approximation.
///   2. Tolerance genuinely changes the result, so tolerance must be part of
///      the key. A memo keyed on the route alone would freeze the line at
///      whatever zoom it was first drawn at.
void main() {
  /// A route with real structure: a long run plus fine detail that a coarse
  /// tolerance should discard and a fine one should keep.
  List<LatLng> route() {
    final pts = <LatLng>[];
    for (var i = 0; i < 800; i++) {
      final t = i / 799;
      // A gentle arc, with a small zigzag riding on top of it.
      pts.add(LatLng(
        23.70 + t * 0.20 + (i.isEven ? 0.00004 : -0.00004),
        90.30 + t * 0.15 + (i % 3 == 0 ? 0.00003 : 0),
      ));
    }
    return pts;
  }

  test('simplify is pure, so a cached result is exact and not an approximation', () {
    final pts = route();
    final a = RouteGeometryService.simplify(pts, 0.0004);
    final b = RouteGeometryService.simplify(pts, 0.0004);
    expect(a.length, b.length);
    for (var i = 0; i < a.length; i++) {
      expect(a[i].latitude, b[i].latitude);
      expect(a[i].longitude, b[i].longitude);
    }
  });

  test('simplify does not mutate the route it is given', () {
    // The memo holds a reference to the source list and compares with
    // identical(). If simplify ever mutated its input, a cache hit would
    // return a line built from points that had since changed underneath it.
    final pts = route();
    final before = pts.map((p) => '${p.latitude},${p.longitude}').join(';');
    RouteGeometryService.simplify(pts, 0.0004);
    final after = pts.map((p) => '${p.latitude},${p.longitude}').join(';');
    expect(after, before);
    expect(pts.length, 800);
  });

  test('tolerance changes the output, so it must be part of the cache key', () {
    final pts = route();
    final coarse = RouteGeometryService.simplify(pts, 0.0004);
    final fine = RouteGeometryService.simplify(pts, 0.000001);
    expect(coarse.length, lessThan(fine.length),
        reason: 'If these matched, the zoom-dependent tolerance would be doing '
            'nothing and the memo key could safely ignore it. They do not.');
    // And the coarse pass must actually be worth doing.
    expect(coarse.length, lessThan(pts.length ~/ 2),
        reason: 'A simplification that keeps most of the points is not saving '
            'the raster time it exists to save.');
  });

  test('the endpoints always survive, at any tolerance', () {
    // A route whose first or last stop moved would be drawn starting or ending
    // in the wrong place — worse than an unsimplified line.
    final pts = route();
    for (final tol in [0.0, 0.000001, 0.0001, 0.0004, 0.01]) {
      final out = RouteGeometryService.simplify(pts, tol);
      expect(out.first.latitude, pts.first.latitude, reason: 'tolerance $tol');
      expect(out.first.longitude, pts.first.longitude, reason: 'tolerance $tol');
      expect(out.last.latitude, pts.last.latitude, reason: 'tolerance $tol');
      expect(out.last.longitude, pts.last.longitude, reason: 'tolerance $tol');
      expect(out.length, greaterThanOrEqualTo(2), reason: 'tolerance $tol');
    }
  });

  test('a zero or negative tolerance returns the route untouched', () {
    // This is the z>=15 case: the user is inspecting streets and wants every
    // point. It must not be a no-op that silently drops detail.
    final pts = route();
    expect(RouteGeometryService.simplify(pts, 0).length, pts.length);
    expect(RouteGeometryService.simplify(pts, -1).length, pts.length);
  });
}
