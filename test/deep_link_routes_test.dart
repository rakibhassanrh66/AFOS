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
  final router = File('lib/config/routes/app_router.dart').readAsStringSync();
  final routes = RegExp(r"path:\s*'([^']+)'")
      .allMatches(router)
      .map((m) => m.group(1)!)
      .toList();

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

  test('every deepLink in lib/ matches a route in app_router.dart', () {
    expect(routes, isNotEmpty, reason: 'no routes parsed — has app_router.dart moved?');

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

  /// The same failure, one layer up.
  ///
  /// A menu entry, a dashboard tile or an Uploads card that names a route the
  /// router does not have is dead in exactly the way a bad deep link is: it
  /// looks right in the source, renders correctly, and does nothing when
  /// tapped. The capability list is the app's single answer to "what can this
  /// person do", so a wrong route there is wrong in the slide menu, the web
  /// sidebar, the role consoles and the command palette at once.
  test('every capability and tile route resolves', () {
    final dead = <String>[];

    void check(String path, RegExp pattern, {int group = 1}) {
      final f = File(path);
      if (!f.existsSync()) {
        dead.add('MISSING FILE $path');
        return;
      }
      final text = f.readAsStringSync();
      for (final m in pattern.allMatches(text)) {
        final link = m.group(group)!;
        if (!link.startsWith('/')) continue;
        if (!matches(link)) dead.add('$link   ($path)');
      }
    }

    check('lib/core/auth/capabilities.dart', RegExp(r"route:\s*'([^']+)'"));
    check('lib/features/uploads/presentation/uploads_hub_screen.dart',
        RegExp(r"route:\s*'([^']+)'"));
    // _Module('Label', icon, colour, '/route', 'hint')
    check('lib/features/dashboard/presentation/dashboard_screen.dart',
        RegExp(r"_Module\([^)]*?,\s*'(/[^']+)'\s*,"));

    expect(dead, isEmpty,
        reason: 'these navigation targets resolve to no route:\n${dead.join('\n')}');
  });
}
