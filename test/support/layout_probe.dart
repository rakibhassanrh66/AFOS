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
// RenderParagraph, for the starved-text check below. material.dart does not
// re-export it, despite what the "unnecessary import" hint claims.
import 'package:flutter/rendering.dart';
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

/// How narrow a TRUNCATED text has to get before it counts as starved, as a
/// fraction of the viewport width.
///
/// Calibrated, not guessed. It has to sit above the widths a starved title
/// actually lands on when a badge or button eats the row (tens of px), and
/// below the width of a text that is merely long — a title ellipsised across a
/// nearly-full-width card is correct behaviour and must not be reported. At
/// 0.35 the trip point is 112px on the 320dp phone and 144px on the 412dp one,
/// which is roughly "less than a third of the screen for something that has
/// more to say".
const starvedWidthFraction = 0.35;

/// How much of a label has to be invisible before it counts as starved.
///
/// Truncation by a hair is a rounding artifact — a button label that needs
/// 91.4px in a 91.0px box is not a bug anyone can see, and failing the build
/// over it would train people to ignore this harness. 25% is the point where a
/// word is genuinely unreadable rather than merely tight.
const starvedHiddenFraction = 0.25;

/// Pumps [child] at [size]/[scale] and returns everything laid out wrong.
///
/// An empty list means the widget is readable at that combination.
/// Texts whose truncation is the POINT of the case, keyed by exact label.
///
/// Deliberately narrow, and deliberately awkward to use. There is exactly one
/// legitimate reason to reach for it: a case that asserts a guard works, where
/// the guard working means something gets ellipsised. The badge in
/// `course_offering_layout_test`'s over-long-label case is the whole example —
/// a 29-character badge clipping itself is the cap doing its job, and the thing
/// being asserted is that the TITLE beside it survives.
///
/// It is not for silencing a starve you would rather not fix.
typedef ExpectedTruncations = Set<String>;

Future<List<String>> probeLayout(
    WidgetTester tester, Widget child, Size size, double scale,
    {ExpectedTruncations expectTruncated = const {}}) async {
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
    if (data.trim().length <= 4) continue; // "3", "CSE" — narrow on purpose.
    final label = data.substring(0, data.length.clamp(0, 40));

    // Tall and pencil-thin == one glyph per line.
    if (w < 34 && h > w * 2.2) {
      faults.add('VERTICAL TEXT "$label" '
          'w=${w.toStringAsFixed(1)} h=${h.toStringAsFixed(1)}');
    }

    // Starved down to an ellipsis, which the two checks above CANNOT see.
    //
    // Those catch a text that was given 0px and answered by stacking glyphs
    // vertically. Add `maxLines: 1, overflow: ellipsis` — as most of this app's
    // cards now have — and the same 0px produces a tidy "…" instead: no
    // RenderFlex overflow, nothing pencil-thin, and a probe that reports
    // success on a card whose title is gone. The previous round of fixes put
    // that cap on widget after widget, so it cured the visible symptom and made
    // the underlying starve invisible to this harness at the same time.
    //
    // `didExceedMaxLines` is precisely "this was truncated". Truncation on its
    // own is legitimate and common — a long course title ellipsised across a
    // full-width line is working as intended — so the fault is truncation
    // *while narrow*: the text was squeezed into a sliver by a non-flex
    // sibling rather than simply being longer than a generous line.
    if (box is RenderParagraph &&
        box.didExceedMaxLines &&
        !expectTruncated.contains(data) &&
        w < size.width * starvedWidthFraction) {
      // Measure how much of the CONTENT is cut off, so the report proves
      // itself instead of asserting a starve. `box.text` is the fully resolved
      // span — style, scaler and all — so this is the text the screen actually
      // laid out, not a reconstruction of it.
      //
      // Compared by HEIGHT at the box's own width, not by single-line width.
      // Width only works for a one-line text: measuring a `maxLines: 2` title
      // as if it had to fit on one line reported a 2-line heading that renders
      // perfectly as "88px of the 847px it needs, 90% hidden" — nonsense, and
      // it would have sent me rewriting healthy widgets. Laying the span out
      // unbounded in lines at the real width gives the honest answer for one
      // line and many: how many lines of content exist versus how many fit.
      final painter = TextPainter(
        text: box.text,
        textDirection: box.textDirection,
        textScaler: box.textScaler,
      )..layout(maxWidth: w);
      final neededHeight = painter.height;
      painter.dispose();
      if (neededHeight <= 0) continue;

      final hidden = 1 - (h / neededHeight);
      if (hidden >= starvedHiddenFraction) {
        faults.add('STARVED "$label" showing ${h.toStringAsFixed(0)}px '
            'of ${neededHeight.toStringAsFixed(0)}px of text '
            '(${(hidden * 100).toStringAsFixed(0)}% hidden) '
            'in w=${w.toStringAsFixed(1)} on a ${size.width.toStringAsFixed(0)} screen');
      }
    }
  }
  return faults;
}

/// Registers one `testWidgets` per entry in [cases], sweeping every size and
/// scale and failing with the full list of what went wrong where.
void runLayoutSweep(
  String group,
  Map<String, Widget Function()> cases, {
  /// Per-case allowances, keyed by the case name. See [ExpectedTruncations].
  Map<String, ExpectedTruncations> expectTruncated = const {},
}) {
  for (final entry in cases.entries) {
    testWidgets('$group: ${entry.key}', (tester) async {
      final failures = <String>[];
      for (final size in probeSizes.entries) {
        for (final scale in probeScales) {
          for (final fault in await probeLayout(
              tester, entry.value(), size.value, scale,
              expectTruncated: expectTruncated[entry.key] ?? const {})) {
            failures.add('${size.key} @ ${scale}x -> $fault');
          }
        }
      }
      expect(failures, isEmpty,
          reason: '${entry.key} laid out wrong:\n${failures.join('\n')}');
    });
  }
}
