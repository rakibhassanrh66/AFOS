import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/features/shell/presentation/top_app_bar.dart';

/// Pure-arithmetic coverage for `webHeaderOverflowWidth`
/// (lib/features/shell/presentation/top_app_bar.dart), the calculation
/// `_WebPageHeader` uses to escape app_shell.dart's 1440px body-readability
/// cap so the desktop header/bell reaches the browser's true right edge.
/// `_WebPageHeader` itself never builds under a non-web `flutter test` run
/// (`kIsWeb` is a compile-time constant), so the arithmetic is tested
/// directly rather than via a pumped widget.
void main() {
  test('subtracts the sidebar rail from the window width', () {
    expect(webHeaderOverflowWidth(windowWidth: 1920, railWidth: 264), 1656);
    expect(webHeaderOverflowWidth(windowWidth: 1704, railWidth: 264), 1440);
  });

  test('never goes negative on a window narrower than the rail', () {
    // Shouldn't happen in practice (this path only runs once
    // Responsive.isExpanded is already true, at >=1024px), but a negative
    // maxWidth would be an invalid BoxConstraints, not just a visual bug.
    expect(webHeaderOverflowWidth(windowWidth: 200, railWidth: 264), 0);
  });
}
