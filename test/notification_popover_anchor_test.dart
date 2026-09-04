import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/features/notifications/presentation/notification_popover.dart';

/// Placement contract for the notification tray
/// (lib/features/notifications/presentation/notification_popover.dart).
///
/// WHAT THIS FILE USED TO DO, AND WHY IT DIDN'T CATCH THE BUG.
///
/// It hand-built a `CompositedTransformTarget`/`Follower` pair in the test and
/// asserted the panel sat 8px below the target. That passed. It kept passing
/// while the real tray hung off the bottom of short windows and sat 6px from
/// one screen edge and 18px from the other — because the thing under test was
/// a *copy* of the mechanism, and a copied widget cannot regress. The project
/// constitution says exactly this: test the real widget, never a copy of it.
///
/// [notificationPopoverRect] is the real production placement, so these are
/// the cases that actually decide where the tray lands. Anchoring below the
/// bell was never the hard part; staying inside the window is.
void main() {
  // A 400x800 phone with a 40px status bar and a 20px gesture inset, and the
  // bell where AfosAppBar really puts it: the floating pill insets 12, then a
  // 6px gap after the bell, so the bell's right edge is 18px from the screen.
  const phone = Size(400, 800);
  const phonePadding = EdgeInsets.only(top: 40, bottom: 20);
  const bell = Rect.fromLTWH(334, 46, 48, 48); // right = 382, bottom = 94

  Rect rectFor({
    Rect anchor = bell,
    Size screen = phone,
    EdgeInsets padding = phonePadding,
    double width = 380,
    double height = 520,
  }) =>
      notificationPopoverRect(
        anchor: anchor,
        screen: screen,
        viewPadding: padding,
        preferredWidth: width,
        preferredHeight: height,
      );

  test('sits below the bell, not over it', () {
    final r = rectFor();
    expect(r.top, bell.bottom + 8);
  });

  test('leaves an equal margin on both screen edges on a phone', () {
    // THE REPORTED BUG. The panel was `screenWidth - 24` wide and right-
    // aligned to a bell inset by 18, which left 6px on the left and 18px on
    // the right — close enough to symmetric to look like a rendering fault
    // rather than a choice.
    final r = rectFor();
    final leftGap = r.left;
    final rightGap = phone.width - r.right;
    expect(leftGap, rightGap,
        reason: 'tray margins must match; got $leftGap left, $rightGap right');
    expect(leftGap, 12);
  });

  test('never crosses the bottom of the window', () {
    // A short browser window: the old code measured max height as a fraction
    // of the screen from zero, ignoring that the panel starts below the bell,
    // so the footer went under the bottom edge and became unreachable.
    final r = rectFor(screen: const Size(400, 320), padding: EdgeInsets.zero);
    expect(r.bottom, lessThanOrEqualTo(320 - 12));
    expect(r.height, greaterThan(0));
  });

  test('flips above the bell when there is more room there', () {
    // Bell near the bottom — a web layout with the bar at the foot of the
    // window, or a phone in landscape.
    const lowBell = Rect.fromLTWH(334, 700, 48, 48);
    final r = rectFor(anchor: lowBell);
    expect(r.bottom, lessThanOrEqualTo(lowBell.top - 8));
    expect(r.top, greaterThanOrEqualTo(phonePadding.top + 12));
  });

  test('a status-bar inset moves the tray with the bell, not past it', () {
    // The original regression: an already-global position fed through a
    // SafeArea, double-counting the status bar. The gap below the bell must
    // be the same whether or not there is an inset.
    final withInset = rectFor();
    final without = rectFor(padding: EdgeInsets.zero);
    expect(withInset.top - bell.bottom, without.top - bell.bottom);
  });

  test('stays inside the safe area on a wide desktop window', () {
    // Bell at the right edge of the 1440 content column on a 1920 monitor.
    const deskBell = Rect.fromLTWH(1740, 20, 48, 48);
    final r = rectFor(
      anchor: deskBell,
      screen: const Size(1920, 1080),
      padding: EdgeInsets.zero,
    );
    expect(r.right, lessThanOrEqualTo(1920 - 12));
    expect(r.left, greaterThanOrEqualTo(12));
    expect(r.width, 380, reason: 'a wide window should get the full tray width');
  });

  test('degrades to the safe box rather than a negative size', () {
    // Narrower than the tray wants to be, which is what a 320px phone in the
    // constitution's responsive floor actually is.
    final r = rectFor(screen: const Size(320, 640), padding: EdgeInsets.zero);
    expect(r.width, lessThanOrEqualTo(320 - 24));
    expect(r.width, greaterThan(0));
    expect(r.left, greaterThanOrEqualTo(12));
  });
}
