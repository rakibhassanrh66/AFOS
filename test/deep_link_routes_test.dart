import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every `deepLink:` a notification carries must resolve to a real route.
///
/// A dead deep link is invisible in every way that matters: the notification
/// still arrives, still looks correct, and simply does nothing when tapped. No
/// analyzer warning, no test failure, no crash report — the user just concludes
/// the app ignored them.
///
/// One shipped: `/schedule/my-courses`, sent to a student the moment their join
/// request was APPROVED, which is the single most-tapped notification in the
/// course flow. The screen it means is titled "My Courses" in its app bar but
/// is routed at `/schedule/browse-courses`, so the string looked right in
/// review and in the source.
///
/// Source-level rather than a widget test on purpose: this needs to see every
/// call site at once, and a widget test would only cover the ones it happened
/// to drive.
void main() {
  test('every deepLink in lib/ matches a route in app_router.dart', () {
    final router = File('lib/config/routes/app_router.dart').readAsStringSync();
    final routes = RegExp(r"path:\s*'([^']+)'")
        .allMatches(router)
        .map((m) => m.group(1)!)
        .toList();
    expect(routes, isNotEmpty, reason: 'no routes parsed — has app_router.dart moved?');

    // A route with a :param matches any single segment in that position.
    bool matches(String link) {
      for (final route in routes) {
        final r = route.split('/'), l = link.split('/');
        if (r.length != l.length) continue;
        var ok = true;
        for (var i = 0; i < r.length; i++) {
          if (r[i].startsWith(':')) continue;
          if (r[i] != l[i]) { ok = false; break; }
        }
        if (ok) return true;
      }
      return false;
    }

    final dead = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final text = file.readAsStringSync();
      for (final m in RegExp(r"deepLink:\s*'([^']+)'").allMatches(text)) {
        final link = m.group(1)!;
        // Interpolated links carry a runtime id; check the static prefix only.
        final probe = link.contains(r'$')
            ? '${link.substring(0, link.indexOf(r'$'))}0'
            : link;
        if (!matches(probe)) dead.add('$link   (${file.path})');
      }
    }

    expect(dead, isEmpty,
        reason: 'these deep links resolve to no route:\n${dead.join('\n')}');
  });
}
