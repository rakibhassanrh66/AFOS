import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/shared/widgets/glass_bottom_nav.dart';

/// A nav tap must act on the FIRST frame, never after the double-tap window.
///
/// THE BUG THIS LOCKS DOWN. `_NavItem` used to be a `GestureDetector` carrying
/// both `onTap` and `onDoubleTap`. That puts a `DoubleTapGestureRecognizer` in
/// the gesture arena beside the tap recogniser, and it holds the arena open for
/// `kDoubleTapTimeout` (300ms) in case a second tap arrives — so `onTap` could
/// not fire until it gave up. Every tab press paid 300ms before navigation even
/// started, which is how the double-tap-search shortcut turned the whole nav
/// bar into a "crawl".
///
/// WHY IT NEEDED A TEST RATHER THAN A PROFILER. Nothing was slow. Measured on
/// the device with the bug live, `dumpsys gfxinfo` reported **0.00% janky
/// frames** and a **5ms** 50th-percentile frame time while flagging high input
/// latency on **114 of 117** frames. Fast frames, late touches. A rendering
/// profile would have shown a healthy app, and `flutter analyze` sees nothing
/// at all — the cost was in gesture arbitration, which only a timing assertion
/// catches.
///
/// So these tests pump ONE frame and assert the callback already ran. Restore
/// `onDoubleTap:` onto the GestureDetector and the first test fails.
void main() {
  const dests = [
    BottomNavDest(label: 'Home', icon: Icons.home, route: '/home'),
    BottomNavDest(label: 'Search', icon: Icons.search, route: '/search'),
    BottomNavDest(label: 'Profile', icon: Icons.person, route: '/profile'),
  ];

  Widget host({
    required ValueChanged<int> onTap,
    ValueChanged<int>? onDoubleTap,
    int currentIndex = 0,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: GlassBottomNav(
              destinations: dests,
              currentIndex: currentIndex,
              onTap: onTap,
              onDoubleTap: onDoubleTap,
            ),
          ),
        ),
      );

  testWidgets('a tab tap fires on the first frame, even with a double-tap handler',
      (tester) async {
    int? tapped;
    await tester.pumpWidget(host(
      onTap: (i) => tapped = i,
      // The shortcut is REGISTERED here. That is the whole point: it must not
      // cost anything to the ordinary single tap.
      onDoubleTap: (_) {},
    ));

    await tester.tap(find.text('Search'));
    await tester.pump(); // exactly one frame — no settle, no timeout elapsed

    expect(tapped, 1,
        reason: 'navigation must begin immediately; waiting out '
            '${kDoubleTapTimeout.inMilliseconds}ms first is the bug');
  });

  testWidgets('the double-tap shortcut still works', (tester) async {
    final taps = <int>[];
    int? doubled;
    await tester.pumpWidget(host(
      onTap: taps.add,
      onDoubleTap: (i) => doubled = i,
    ));

    await tester.tap(find.text('Search'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Search'));
    await tester.pump();

    expect(doubled, 1, reason: 'a quick second tap is the shortcut');
    expect(taps, [1],
        reason: 'the first tap still navigated — that is what makes acting '
            'immediately safe, since it was never the wrong action');
  });

  testWidgets('two slow taps are two ordinary taps, not a shortcut',
      (tester) async {
    final taps = <int>[];
    var doubled = 0;
    await tester.pumpWidget(host(
      onTap: taps.add,
      onDoubleTap: (_) => doubled++,
      currentIndex: -1, // not on a tab, so every tap navigates
    ));

    await tester.tap(find.text('Search'));
    await tester.pump();
    // runAsync, not pump(duration). `pump` advances Flutter's FAKE clock,
    // while _handleTap compares real `DateTime.now()` values — so a pumped
    // 350ms leaves the two taps microseconds apart in wall-clock terms and
    // they read as a double tap. Only a real delay separates them.
    await tester.runAsync(() =>
        Future<void>.delayed(kDoubleTapTimeout + const Duration(milliseconds: 60)));
    await tester.tap(find.text('Search'));
    await tester.pump();

    expect(doubled, 0);
    expect(taps, [1, 1]);
  });

  testWidgets('double-tapping the tab you are already on still reaches it',
      (tester) async {
    int? doubled;
    await tester.pumpWidget(host(
      onTap: (_) {},
      onDoubleTap: (i) => doubled = i,
      currentIndex: 1, // already on Search
    ));

    await tester.tap(find.text('Search'));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('Search'));
    await tester.pump();

    expect(doubled, 1,
        reason: 'the "already on this tab" early-return must be checked AFTER '
            'the double-tap test — this is the main way the shortcut is used');
  });
}
