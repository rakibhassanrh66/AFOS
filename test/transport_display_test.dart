import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/features/transport/data/transport_display.dart';

/// Regression guards for the transport-screen display bugs fixed 2026-07-22.
///
/// Every case here is taken from the LIVE route data, not invented — the point
/// is that these exact inputs used to produce the wrong output on the user's
/// device.
void main() {
  group('stopKey — one place, one identity', () {
    test('collapses the live Mirpur 10 / Mirpur-10 split', () {
      // R4 spells it "Mirpur 10", F5 spells it "Mirpur-10". Before this, the
      // picker listed the stop twice and each entry found only one route.
      expect(stopKey('Mirpur 10'), stopKey('Mirpur-10'));
    });

    test('is case- and punctuation-insensitive', () {
      expect(stopKey('Dhanmondi - Sobhanbag'), stopKey('dhanmondi sobhanbag'));
      expect(stopKey('C&B'), 'cb');
      expect(stopKey('Uttara - Rajlokkhi'), 'uttararajlokkhi');
    });

    test('keeps genuinely different stops apart', () {
      // These are separate places in the live data and must NOT be merged.
      expect(stopKey('Savar'), isNot(stopKey('Savar Bus Stand')));
      expect(stopKey('Mirpur 10'), isNot(stopKey('Mirpur 12')));
      expect(stopKey('Sony Cinema Hall'), isNot(stopKey('Mirpur 01 - Sony Cinema Hall')));
    });
  });

  group('searchScore — what the old contains() search could not do', () {
    test('matches across punctuation and spacing', () {
      // The stop is stored "Mirpur 10"; all of these used to find nothing.
      for (final q in ['mirpur10', 'Mirpur-10', 'MIRPUR  10', 'mirpur 10']) {
        expect(searchScore('Mirpur 10', q), isNotNull, reason: q);
      }
      expect(searchScore('C&B', 'cb'), isNotNull);
      expect(searchScore('Dhanmondi - Sobhanbag', 'dhanmondi sobhanbag'), isNotNull);
    });

    test('matches tokens in any order', () {
      // A single substring test cannot span this label.
      expect(searchScore('Mirpur 01 - Sony Cinema Hall', 'sony mirpur'), isNotNull);
      expect(searchScore('Mirpur 01 - Sony Cinema Hall', 'hall cinema'), isNotNull);
    });

    test('still rejects genuine non-matches', () {
      expect(searchScore('Mirpur 10', 'uttara'), isNull);
      expect(searchScore('Savar', 'mirpur'), isNull);
      // Every token must be present, not just one of them.
      expect(searchScore('Mirpur 10', 'mirpur uttara'), isNull);
    });

    test('ranks exact and prefix matches above mid-string ones', () {
      final exact = searchScore('Mirpur 10', 'mirpur 10')!;
      final prefix = searchScore('Mirpur 12', 'mirpur')!;
      final mid = searchScore('Mirpur 01 - Sony Cinema Hall', 'sony')!;
      expect(exact, lessThan(prefix));
      expect(prefix, lessThanOrEqualTo(mid));
    });

    test('an empty query matches everything', () {
      expect(searchScore('anything', ''), isNotNull);
      expect(searchScore('anything', '   '), isNotNull);
    });
  });

  group('searchRank — ordering and stability', () {
    test('puts the exact match first when several stops share a prefix', () {
      final stops = ['Mirpur 01 - Sony Cinema Hall', 'Mirpur 02', 'Mirpur 10', 'Mirpur 12'];
      expect(searchRank(stops, 'Mirpur 10', (s) => s).first, 'Mirpur 10');
    });

    test('filters out non-matches', () {
      final stops = ['Mirpur 10', 'Savar', 'Uttara Moylar Mor'];
      expect(searchRank(stops, 'mirpur', (s) => s), ['Mirpur 10']);
    });

    test('an empty query returns the list untouched, same order', () {
      final stops = ['b', 'a', 'c'];
      expect(searchRank(stops, '', (s) => s), stops);
    });

    test('is stable within an equal score', () {
      // Both are mid-string matches, so input order must be preserved.
      final stops = ['Alpha Mirpur', 'Beta Mirpur'];
      expect(searchRank(stops, 'mirpur', (s) => s), stops);
    });
  });

  group('prettyStop — only fixes unambiguously mis-entered names', () {
    test('title-cases the five all-lower-case stops in the live data', () {
      expect(prettyStop('gulistan'), 'Gulistan');
      expect(prettyStop('kolabagan'), 'Kolabagan');
      expect(prettyStop('saydabad bus stand'), 'Saydabad Bus Stand');
      expect(prettyStop('sign board'), 'Sign Board');
      expect(prettyStop('sonir akhra'), 'Sonir Akhra');
    });

    test('leaves deliberate casing completely alone', () {
      for (final s in ['C&B', 'JU', 'ECB Chattor', 'Mirpur-10', 'Dhanmondi - Sobhanbag',
                       'Daffodil Smart City', 'Uttara Metro rail Center']) {
        expect(prettyStop(s), s, reason: s);
      }
    });

    test('cannot change identity — matching is unaffected', () {
      expect(stopKey(prettyStop('sonir akhra')), stopKey('sonir akhra'));
      expect(prettyStop(''), '');
    });
  });

  group('compareRouteNumbers — natural ordering', () {
    test('R2 sorts before R10 (the DB returns them the other way round)', () {
      expect(compareRouteNumbers('R2', 'R10'), lessThan(0));
      expect(compareRouteNumbers('R10', 'R2'), greaterThan(0));
    });

    test('sorts a full live regular-schedule section correctly', () {
      // Exactly what `order by route_number` hands back today.
      final live = ['R1', 'R10', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7', 'R8', 'R9']
        ..sort(compareRouteNumbers);
      expect(live, ['R1', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7', 'R8', 'R9', 'R10']);
    });

    test('sorts the live shuttle section correctly', () {
      final live = ['R11', 'R12', 'R13', 'R14', 'R15', 'R16']..sort(compareRouteNumbers);
      expect(live, ['R11', 'R12', 'R13', 'R14', 'R15', 'R16']);
    });

    test('groups by letter prefix before number', () {
      final mixed = ['R2', 'F10', 'F1', 'R1']..sort(compareRouteNumbers);
      expect(mixed, ['F1', 'F10', 'R1', 'R2']);
    });

    test('is a total order — equal inputs compare equal, no crash on oddities', () {
      expect(compareRouteNumbers('R1', 'R1'), 0);
      expect(compareRouteNumbers('', ''), 0);
      // A numberless code must not throw and must sort after a numbered one.
      expect(compareRouteNumbers('R1', 'RX'), lessThan(0));
    });
  });

  group('sampleWaypoints — Google caps waypoints at nine', () {
    test('passes short routes through untouched', () {
      final five = ['a', 'b', 'c', 'd', 'e'];
      expect(sampleWaypoints(five), five);
      expect(sampleWaypoints(List.generate(maxMapsWaypoints, (i) => '$i')).length,
          maxMapsWaypoints);
    });

    test('caps R9 (17 stops → 15 intermediates) at nine', () {
      final intermediates = List.generate(15, (i) => 'stop$i');
      final sampled = sampleWaypoints(intermediates);
      expect(sampled.length, maxMapsWaypoints);
      // Spread across the whole route, not truncated to the first nine — the
      // last intermediate stop must survive or the back half of the journey
      // vanishes from the directions.
      expect(sampled.first, 'stop0');
      expect(sampled.last, 'stop14');
    });

    test('never emits duplicates or reorders', () {
      for (final n in [10, 12, 14, 15, 20, 40]) {
        final sampled = sampleWaypoints(List.generate(n, (i) => 'stop$i'));
        expect(sampled.length, maxMapsWaypoints, reason: 'n=$n');
        expect(sampled.toSet().length, sampled.length, reason: 'duplicate at n=$n');
        final indices = sampled.map((s) => int.parse(s.substring(4))).toList();
        final sorted = [...indices]..sort();
        expect(indices, sorted, reason: 'out of order at n=$n');
      }
    });
  });

  group('googleMapsRouteUrl — correct region, correct pins', () {
    test('qualifies stops with Dhaka Division, never bare Dhaka', () {
      // "Konabari Pukur Par" is in GAZIPUR. The old ", Dhaka" suffix is what
      // dropped the pin on the wrong place.
      final url = googleMapsRouteUrl(['Konabari Pukur Par', 'Daffodil Smart City'])!;
      final decoded = Uri.decodeFull(url.toString());
      expect(decoded, contains('Konabari Pukur Par, Dhaka Division, Bangladesh'));
      expect(decoded, isNot(contains('Konabari Pukur Par, Dhaka, Bangladesh')));
    });

    test('builds directions with origin, destination and waypoints', () {
      final url = googleMapsRouteUrl(['A', 'B', 'C'])!;
      expect(url.toString(), startsWith('https://www.google.com/maps/dir/?api=1'));
      final decoded = Uri.decodeFull(url.toString());
      expect(decoded, contains('origin=A, $mapsRegion'));
      expect(decoded, contains('destination=C, $mapsRegion'));
      expect(decoded, contains('waypoints=B, $mapsRegion'));
      expect(decoded, contains('travelmode=driving'));
    });

    test('never exceeds nine waypoints for the longest live route', () {
      // R9: 17 stops.
      final url = googleMapsRouteUrl(List.generate(17, (i) => 'stop$i'))!;
      final waypoints = url.queryParameters['waypoints']!.split('|');
      expect(waypoints.length, lessThanOrEqualTo(maxMapsWaypoints));
    });

    test('omits the waypoints parameter for a two-stop route', () {
      final url = googleMapsRouteUrl(['A', 'B'])!;
      expect(url.queryParameters.containsKey('waypoints'), isFalse);
    });

    test('falls back to a search pin for a single stop', () {
      final url = googleMapsRouteUrl(['Daffodil Smart City'])!;
      expect(url.toString(), startsWith('https://www.google.com/maps/search/?api=1'));
      expect(Uri.decodeFull(url.toString()), contains('Daffodil Smart City, $mapsRegion'));
    });

    test('returns null when there is nothing to map', () {
      expect(googleMapsRouteUrl(const []), isNull);
      expect(googleMapsRouteUrl(const ['', '   ']), isNull);
    });

    test('ignores blank stop names rather than emitting empty places', () {
      final url = googleMapsRouteUrl(['A', '  ', 'B'])!;
      expect(url.queryParameters.containsKey('waypoints'), isFalse);
      expect(Uri.decodeFull(url.toString()), contains('destination=B, $mapsRegion'));
    });
  });
}
