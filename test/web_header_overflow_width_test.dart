import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the desktop-web page header
/// (`_WebPageHeader` in lib/features/shell/presentation/top_app_bar.dart).
///
/// WHAT THIS REPLACED, AND WHY IT IS A SOURCE CHECK.
///
/// This file used to test `webHeaderOverflowWidth`, the arithmetic behind an
/// `OverflowBox` that let the header escape app_shell.dart's centred 1440px
/// content cap so it could sit flush against the browser edge. The arithmetic
/// passed its tests and the feature was still broken, because the bug was not
/// in the number:
///
///   * The width was measured from the RAIL (`window - rail`) while the header
///     actually begins a gutter further right, the 1440 column being centred.
///     On a 1920px window that laid the header out from x=372 to x=2028 — the
///     actions and the notification bell 108px beyond the right edge of the
///     window.
///   * More fundamentally, `RenderBox.hitTest` refuses any position outside
///     `_size`, and every ancestor applies that test — including the 1440
///     ConstrainedBox. So everything painted past the column was visible and
///     unclickable no matter what width was chosen. That is the "clicks don't
///     work on web" report, and it appeared only above 1704px (1440 + 264),
///     which is why it looked intermittent.
///
/// The fix was to stop escaping: the header occupies its column. There is no
/// longer any arithmetic to unit-test, and `_WebPageHeader` cannot be pumped
/// in a `flutter test` run anyway — it is behind `kIsWeb`, a compile-time
/// constant that is false off the web. What CAN be checked, and what actually
/// prevents the regression, is that nothing has reintroduced a widget which
/// paints outside the box that hit-tests it.
void main() {
  // Comments stripped first — this file's own source explains at length what
  // an OverflowBox did to the bell, and the header's does too. Matching those
  // would make the check fire on its own documentation.
  final source = File('lib/features/shell/presentation/top_app_bar.dart')
      .readAsStringSync()
      .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '')
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

  test('the app bar never paints outside the box that hit-tests it', () {
    // OverflowBox / SizedBox.expand-style escapes and negative-margin
    // Transforms all produce the same class of defect: pixels the mouse
    // cannot reach. If a future layout genuinely needs one, it must also
    // prove the control inside it is still hittable — delete this
    // expectation deliberately, with that test alongside it.
    for (final escape in const ['OverflowBox(', 'UnconstrainedBox(', 'Transform.translate(']) {
      expect(
        source.contains(escape),
        isFalse,
        reason: 'top_app_bar.dart reintroduced $escape. Anything it paints '
            'beyond its parent box is invisible to hit testing, which is how '
            'the notification bell went dead on wide browser windows.',
      );
    }
  });

  test('the removed escape hatch is gone rather than merely unused', () {
    expect(source.contains('webHeaderOverflowWidth'), isFalse);
  });
}
