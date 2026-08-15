import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:afos_v7/features/transport/data/route_geometry_service.dart';

/// Phase 5 — the geometry maths, tested without touching the network.
///
/// The fetch itself is deliberately NOT tested here. Mocking OSRM would assert
/// that my mock returns what I told it to; what is worth pinning is the part
/// that runs on every frame and that a wrong answer would quietly ruin — the
/// simplification.
void main() {
  group('Douglas–Peucker simplification', () {
    test('keeps the endpoints, always', () {
      // If simplification ever moved an endpoint, the route would visibly
      // detach from its first or last stop.
      final line = [
        const LatLng(23.8103, 90.4125),
        const LatLng(23.8110, 90.4130),
        const LatLng(23.8125, 90.4142),
        const LatLng(23.8140, 90.4155),
      ];
      for (final tol in [0.0, 0.0001, 0.01, 1.0]) {
        final out = RouteGeometryService.simplify(line, tol);
        expect(out.first, line.first, reason: 'tolerance $tol moved the start');
        expect(out.last, line.last, reason: 'tolerance $tol moved the end');
      }
    });

    test('a straight line collapses to two points', () {
      // 50 collinear points carry exactly as much shape as 2. At low zoom this
      // is most of a route: long arterial roads digitised finely.
      final straight = List.generate(
          50, (i) => LatLng(23.80 + i * 0.001, 90.40 + i * 0.001));
      final out = RouteGeometryService.simplify(straight, 0.0001);
      expect(out.length, 2);
    });

    test('a genuine corner survives', () {
      // The failure that would matter: simplifying away a turn, so the route
      // cuts the corner and crosses a block it never drives through.
      final corner = [
        const LatLng(23.800, 90.400),
        const LatLng(23.805, 90.400),
        const LatLng(23.810, 90.400),
        const LatLng(23.810, 90.410), // 90-degree turn
        const LatLng(23.810, 90.420),
      ];
      final out = RouteGeometryService.simplify(corner, 0.0001);
      expect(out.length, greaterThanOrEqualTo(3),
          reason: 'the turn was flattened — the line now cuts the corner');
      expect(out.contains(const LatLng(23.810, 90.400)), isTrue,
          reason: 'the corner vertex itself is what must be kept');
    });

    test('a bigger tolerance never produces more points', () {
      final wobbly = List.generate(
        200,
        (i) => LatLng(
          23.80 + i * 0.0005 + (i.isEven ? 0.00002 : -0.00002),
          90.40 + i * 0.0004,
        ),
      );
      var previous = wobbly.length;
      for (final tol in [0.0, 0.00001, 0.0001, 0.001, 0.01]) {
        final n = RouteGeometryService.simplify(wobbly, tol).length;
        expect(n, lessThanOrEqualTo(previous),
            reason: 'tolerance $tol produced MORE points than a smaller one');
        previous = n;
      }
      expect(previous, 2, reason: 'a huge tolerance should reach the endpoints');
    });

    test('degenerate inputs are returned untouched', () {
      expect(RouteGeometryService.simplify(const [], 0.001), isEmpty);
      const one = [LatLng(23.8, 90.4)];
      expect(RouteGeometryService.simplify(one, 0.001), one);
      const two = [LatLng(23.8, 90.4), LatLng(23.9, 90.5)];
      expect(RouteGeometryService.simplify(two, 0.001), two);
    });

    test('zero tolerance is a no-op, not a collapse', () {
      // The high-zoom path. Getting this backwards would simplify hardest
      // exactly where the user is inspecting individual streets.
      final line = List.generate(
          30, (i) => LatLng(23.80 + i * 0.001, 90.40 + (i % 3) * 0.0007));
      expect(RouteGeometryService.simplify(line, 0).length, line.length);
    });
  });
}
