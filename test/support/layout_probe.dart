/// The shared layout probe behind `course_offering_layout_test` and
/// `review_screens_layout_test`.
///
/// WHAT THIS CATCHES, and why an overflow-only harness does not.
///
/// A `Row` lays its NON-FLEX children out first, with unbounded width, and
/// gives an `Expanded` sibling only what is left. A badge carrying a long
/// label, or a button whose theme sets `minimumSize: Size(double.infinity, 52)`,
/// therefore takes the whole row and leaves the `Expanded(Text)` beside it with
/// **0.0px**. An uncapped `Text` answers a 0px box by wrapping one glyph per
/// line — a 500px-tall column of single letters where a course title should be.
/// That is not a RenderFlex overflow, so an overflow-only harness reports
/// success while the screen is unreadable. It shipped twice.
///
/// So [probeLayout] asserts BOTH conditions. Drive the REAL widgets through it.
/// A copy in a test is worthless here: the first version of this harness used
/// simplified copies, "reproduced" a bug in two cards that were actually fine,
/// and missed nothing only by luck.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real devices, smallest first. The vertical-text failure starts at 1.0x on a
/// 320dp phone and reaches a 412dp phone by 1.3x, so a default-scale-only sweep
/// would miss it.
const probeSizes = <String, Size>{
  '320x568 (small Android)': Size(320, 568),
  '360x780 (common Android)': Size(360, 780),
  '412x915 (large Android)': Size(412, 915),
};

/// Up to a 2.0x accessibility text scale — the largest Android offers.
const probeScales = <double>[1.0, 1.3, 1.6, 2.0];

/// Pumps [child] at [size]/[scale] and returns everything laid out wrong.
///
/// An empty list means the widget is readable at that combination.
Future<List<String>> probeLayout(
    WidgetTester tester, Widget child, Size size, double scale) async {
  final faults = <String>[];
  final previous = FlutterError.onError;
  // EVERY error is captured, not just overflows.
  //
  // This used to record only messages containing 'overflowed' and silently
  // drop the rest — but dropping them does not make them go away: the binding
  // still holds the un-handled error and later fails the test with "A test
  // overrode FlutterError.onError but either failed to return it to its
  // original state", which says nothing about what actually broke. Anything
  // else that throws during layout is a fault worth reporting on its own
  // terms.
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    faults.add(text.contains('overflowed')
        ? 'OVERFLOW: ${text.split('\n').first}'
        : 'EXCEPTION: ${text.split('\n').first}');
  };

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        // Scrollable on purpose: every one of these cards lives in a ListView
        // in the app, so "taller than the phone" is normal and a bottom
        // overflow here would be an artifact of the harness rather than a fault
        // in the widget. Width is what is genuinely constrained, and that is
        // where all of these bugs live.
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: child,
          ),
        ),
      ),
    ),
  ));
  // Not pumpAndSettle: some of these cards run an entrance animation.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  FlutterError.onError = previous;

  for (final element in find.byType(Text).evaluate()) {
    final box = element.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) continue;
    final w = box.size.width, h = box.size.height;
    final data = (element.widget as Text).data ?? '';
    // Tall and pencil-thin == one glyph per line.
    if (data.trim().length > 4 && w < 34 && h > w * 2.2) {
      faults.add('VERTICAL TEXT "${data.substring(0, data.length.clamp(0, 40))}" '
          'w=${w.toStringAsFixed(1)} h=${h.toStringAsFixed(1)}');
    }
  }
  return faults;
}

/// Registers one `testWidgets` per entry in [cases], sweeping every size and
/// scale and failing with the full list of what went wrong where.
void runLayoutSweep(String group, Map<String, Widget Function()> cases) {
  for (final entry in cases.entries) {
    testWidgets('$group: ${entry.key}', (tester) async {
      final failures = <String>[];
      for (final size in probeSizes.entries) {
        for (final scale in probeScales) {
          for (final fault
              in await probeLayout(tester, entry.value(), size.value, scale)) {
            failures.add('${size.key} @ ${scale}x -> $fault');
          }
        }
      }
      expect(failures, isEmpty,
          reason: '${entry.key} laid out wrong:\n${failures.join('\n')}');
    });
  }
}
