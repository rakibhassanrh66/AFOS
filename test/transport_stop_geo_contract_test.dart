import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/features/transport/data/transport_display.dart';

/// The contract between Dart's [stopKey] and the SQL `transport_stop_key`.
///
/// WHY THIS TEST EXISTS. Migration `20260905120000` moved stop coordinates out
/// of `transport_stops` and into a canonical `transport_stop_geo` reference,
/// applied by a trigger that looks a stop up BY NAME:
///
///     where stop_key = public.transport_stop_key(new.stop_name)
///
/// Every pin on the map now depends on that lookup hitting. So the two
/// normalizations — one in Postgres, one in `transport_display.dart` — are a
/// single contract written twice, in two languages, in two repositories of
/// truth. Nothing in either file makes the other fail when it drifts, and the
/// failure mode is silent: a stop simply stops being placed, exactly the
/// symptom the migration was written to end.
///
/// The two are also NOT written the same way round:
///
///     SQL   lower(regexp_replace(name, '[^a-zA-Z0-9]', '', 'g'))  -- strip, then lower
///     Dart  name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '') -- lower, then strip
///
/// For ASCII those commute. For a character that lower-cases INTO ASCII
/// (Turkish 'İ' → 'i̇') they do not, and Dart would key a stop the database
/// cannot find. This test proves they agree on the real corpus and pins the
/// divergence so it is a decision rather than a surprise.
void main() {
  /// The SQL function's exact semantics, transcribed: strip first, lower second.
  String sqlStopKey(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

  /// Every place name seeded into `transport_stop_geo`, read out of the
  /// migration itself so this corpus cannot fall behind the migration.
  late final List<String> referenceNames = () {
    final sql = File(
      'supabase/migrations/20260905120000_the_place_names_and_their_pins_had_drifted_apart.sql',
    ).readAsStringSync();
    final block = sql.substring(
      sql.indexOf('from (values'),
      sql.indexOf(') as v(n, lat, lng)'),
    );
    return RegExp(r"\('((?:[^']|'')*)',\s*-?\d+\.\d+,\s*-?\d+\.\d+\)")
        .allMatches(block)
        .map((m) => m.group(1)!.replaceAll("''", "'"))
        .toList();
  }();

  test('the migration still seeds the full reference, not a truncated one', () {
    // 76 places validated in 20260722082525 + the 3 resolved in 20260814213849.
    expect(referenceNames.length, 79);
    // Spot-check the two that mattered most in the incident: the campus (which
    // was pinned in seven different places) and a terminus 9.4 km adrift.
    expect(referenceNames, contains('Daffodil Smart City'));
    expect(referenceNames, contains('Narayanganj Chasara'));
  });

  test('Dart stopKey and SQL transport_stop_key agree on every seeded name', () {
    for (final name in referenceNames) {
      expect(
        stopKey(name),
        sqlStopKey(name),
        reason: 'Dart and SQL disagree on "$name" — the trigger would fail to '
            'place this stop and the map would silently drop its pin.',
      );
    }
  });

  test('they agree on the punctuation cases the network actually contains', () {
    for (final name in const [
      'Mirpur 10', 'Mirpur-10', 'C&B', 'Uttara - Rajlokkhi',
      'Dhanmondi - Sobhanbag', 'Mirpur 01 - Sony Cinema Hall',
      'Malibagh Railgate (South Bus Stop)', 'gulistan', 'sonir akhra',
    ]) {
      expect(stopKey(name), sqlStopKey(name), reason: name);
    }
  });

  test('the reference has no two names collapsing to one key with the SQL rule', () {
    // ON CONFLICT DO UPDATE raises 21000 ("cannot affect row a second time")
    // when two rows in one INSERT share a key. That is not hypothetical: the
    // first push of 20260905120000 failed exactly this way on
    // 'Mirpur 10'/'Mirpur-10', which is why the seed carries `distinct on`.
    // This test states the reason the dedupe is load-bearing.
    final byKey = <String, List<String>>{};
    for (final n in referenceNames) {
      byKey.putIfAbsent(sqlStopKey(n), () => []).add(n);
    }
    final collisions = byKey.entries.where((e) => e.value.length > 1).toList();
    expect(
      collisions.map((e) => e.value).toList(),
      [
        ['Mirpur 10', 'Mirpur-10'],
      ],
      reason: 'A NEW collision means the seed INSERT needs its `distinct on` '
          'ordering re-checked, and that the two spellings genuinely denote '
          'one place before they are collapsed.',
    );
  });

  test('a name that lower-cases into ASCII is where the two rules diverge', () {
    // Documented, not fixed: no stop on this network is spelled this way, and
    // "fix" here would mean changing one side of a contract the other side
    // cannot see. If a stop name ever arrives with such a character, THIS is
    // the test that says why its pin went missing.
    const turkishDottedCapitalI = 'İ'; // 'İ'
    expect(stopKey(turkishDottedCapitalI), isNot(sqlStopKey(turkishDottedCapitalI)));
    expect(sqlStopKey(turkishDottedCapitalI), isEmpty);
  });
}
