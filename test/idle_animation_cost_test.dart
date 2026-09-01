import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/shared/widgets/profile_identity_header.dart';

/// Nothing off-screen may keep a ticker running.
///
/// WHY THIS EXISTS. The slide menu is never unmounted — `app_shell` moves it
/// with `AnimatedPositioned(left: isOpen ? 0 : -(menuWidth + 20))`, so it stays
/// in the tree, laid out and ticking, for the entire life of the app. Anything
/// inside it that calls `AnimationController.repeat()` therefore runs at 60fps
/// forever, whether or not the drawer has ever been opened.
///
/// `GlowingAvatar` did exactly that, and its painter is not cheap: per frame it
/// built a SweepGradient, called `createShader` TWICE, and stroked two circles
/// through `MaskFilter.blur`. That is continuous UI-thread rebuild plus raster
/// work behind a shell that stacks BackdropFilters — and a BackdropFilter
/// re-rasterises whenever the tree behind it is dirtied. The symptom is not a
/// slow drawer; it is the whole app, including the nav bar, answering touches
/// late.
///
/// This project has been here before. `app_shell.dart` still carries the note
/// explaining why the dim overlay's BackdropFilter was removed: "a real,
/// continuous rendering cost live in both debug and release builds, reported as
/// the whole app feeling heavy".
///
/// `transientCallbackCount` is the measurement, not a proxy for it: a running
/// Ticker schedules exactly one transient frame callback, so zero means nothing
/// in this subtree is asking to be redrawn.
void main() {
  Widget host({required bool enabled}) => MaterialApp(
        home: TickerMode(
          enabled: enabled,
          child: const Scaffold(
            body: Center(child: GlowingAvatar(initials: 'RH')),
          ),
        ),
      );

  testWidgets('a visible GlowingAvatar does animate', (tester) async {
    await tester.pumpWidget(host(enabled: true));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0),
        reason: 'the sweep is the point of the widget when it IS on screen');
    // Let it settle so the ticker does not leak into the next test.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an off-screen GlowingAvatar runs nothing at all', (tester) async {
    await tester.pumpWidget(host(enabled: false));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0,
        reason: 'a closed drawer must cost nothing per frame — this is the '
            'assertion that the shell relies on when it wraps the off-screen '
            'SlideMenu in TickerMode');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('it keeps working after being brought back on screen',
      (tester) async {
    await tester.pumpWidget(host(enabled: false));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);

    // Muting a ticker must not kill it: reopening the drawer has to bring the
    // sweep back, or the fix trades a performance bug for a dead animation.
    await tester.pumpWidget(host(enabled: true));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });
}
