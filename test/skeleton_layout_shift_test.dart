import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/shared/widgets/info_card.dart';
import 'package:afos_v7/shared/widgets/shimmer_card.dart';

/// The constitution's rule for loading states is one line:
///
/// > Skeleton loaders must match final layout geometry exactly (zero layout
/// > shift).
///
/// It has been asserted in every phase log and **never measured**. This file
/// measures it.
///
/// WHY IT MATTERS, concretely. A skeleton that claims an 80px row in front of a
/// list whose real rows are 110px does not "look slightly off" — the moment the
/// data lands, every row below the first jumps down by 30px each. On a
/// ten-row list the bottom of the screen moves by 300px. A user who was
/// reaching for a row taps whatever slid under their finger instead. That is
/// the entire cost of a skeleton whose geometry is decorative.
///
/// WHAT IS AND IS NOT TESTED HERE, honestly:
///  * The skeleton primitives' own geometry contract IS tested — a
///    `ShimmerCard(height: h)` must occupy exactly `h`, and a
///    `ShimmerList(count: n, itemHeight: h)` must occupy exactly
///    `n * (h + gap)`. If those drift, every screen's skeleton is wrong at once.
///  * The pairing between a screen's skeleton and that screen's REAL row is
///    tested only where the real row is a shared widget that can be pumped
///    without a Supabase session — `InfoCard`, the standard list row. Rows that
///    are private `_Tile` classes inside a screen file cannot be reached from a
///    unit test; those are verified on the device instead.
void main() {
  /// The gap `ShimmerList` puts under each row. Declared here so a change to
  /// the widget breaks this test rather than silently changing every screen's
  /// skeleton height.
  const shimmerListGap = 12.0;

  /// `ShimmerList`'s own defaults, which ~20 screens take unmodified.
  const defaultItemHeight = 80.0;
  const defaultCount = 4;

  Future<Size> measure(WidgetTester tester, Widget child,
      {double width = 360, double scale = 1.0}) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          // Scrollable, so the child gets UNBOUNDED height.
          //
          // Not cosmetic. `ShimmerList` is a shrink-wrapped ListView, which
          // takes min(content, constraint) — measure it inside a 600px-tall
          // test surface and a 6-row 120px skeleton reports 600, i.e. the
          // harness's own height, not the widget's. That is exactly the
          // clipping the widget documents, and measuring it would have made
          // this test assert the surface size.
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: KeyedSubtree(key: key, child: child),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    return tester.getSize(find.byKey(key));
  }

  group('skeleton primitives keep the geometry they advertise', () {
    testWidgets('ShimmerCard occupies exactly its declared height',
        (tester) async {
      for (final h in <double>[56, 64, 70, 80, 90, 110, 120]) {
        final size = await measure(tester, ShimmerCard(height: h));
        expect(size.height, h,
            reason: 'ShimmerCard(height: $h) laid out at ${size.height}');
      }
    });

    testWidgets('ShimmerCard does not grow with the text scale',
        (tester) async {
      // A skeleton is boxes, not text. If it ever started scaling it would
      // drift away from the row it stands in for at exactly the accessibility
      // settings where a layout jump hurts most.
      for (final scale in <double>[1.0, 1.3, 1.6, 2.0]) {
        final size = await measure(tester, const ShimmerCard(height: 80),
            scale: scale);
        expect(size.height, 80,
            reason: 'ShimmerCard drifted to ${size.height} at ${scale}x');
      }
    });

    testWidgets('ShimmerList occupies count * (itemHeight + gap)',
        (tester) async {
      for (final count in <int>[1, 3, 4, 6]) {
        for (final h in <double>[64, 80, 120]) {
          final size = await measure(
              tester, ShimmerList(count: count, itemHeight: h));
          expect(size.height, count * (h + shimmerListGap),
              reason: 'ShimmerList(count: $count, itemHeight: $h) '
                  'laid out at ${size.height}');
        }
      }
    });

    testWidgets('ShimmerList defaults are the ones the screens assume',
        (tester) async {
      // ~20 screens write `const ShimmerList()` with no arguments and thereby
      // inherit these two numbers. Changing a default silently re-geometries
      // all of them, so the defaults are pinned here.
      final size = await measure(tester, const ShimmerList());
      expect(size.height, defaultCount * (defaultItemHeight + shimmerListGap));
    });
  });

  group('a skeleton row matches the real row it stands in for', () {
    /// The exact shape `global_search_screen` renders: icon badge, title, one
    /// line of subtitle, trailing chevron.
    ///
    /// ON THE CHOICE OF FIXTURE, because it is the whole difficulty here.
    /// An `InfoCard` is not a fixed-height row — it grows when its title wraps.
    /// Measured at 360px: 68px with no subtitle, 69px with a one-line one,
    /// **101px in this shape**, and 136px once the title takes a second line.
    /// A fixed-height skeleton therefore cannot match every row, and pretending
    /// otherwise by picking the tallest would make short rows jump UP instead
    /// of down — the same defect with the sign flipped.
    ///
    /// So the constant is calibrated on the MODAL row: a title that fits one
    /// line, which is what a book title, club name or route label does. Rows
    /// with a wrapping title still shift, by up to 35px, and that is a real
    /// residual limit of fixed-geometry skeletons rather than something this
    /// test is hiding.
    Widget searchResultRow() => const InfoCard(
          icon: Icons.menu_book_rounded,
          title: 'Data Structures',
          subtitle: 'Library · 3 copies',
          trailing: Icon(Icons.chevron_right_rounded, size: 20),
        );

    testWidgets('ShimmerCard.infoCardRow is the height of a real InfoCard',
        (tester) async {
      // This is the assertion that makes the constant honest. If someone
      // changes InfoCard's padding, its icon badge, or its text styles, the
      // skeleton silently stops matching it — and a skeleton that no longer
      // matches is worse than none, because it promises a geometry it does not
      // deliver. Pinning it here means that change breaks the build instead.
      final drift = <String>[];
      for (final width in <double>[320, 360, 412]) {
        final real = await measure(tester, searchResultRow(), width: width);
        final delta = (real.height - ShimmerCard.infoCardRow).abs();
        if (delta > 1) {
          drift.add('at ${width.toInt()}px the real row is ${real.height}px vs '
              'a ${ShimmerCard.infoCardRow}px skeleton — ${delta}px per row');
        }
      }
      expect(drift, isEmpty,
          reason: 'ShimmerCard.infoCardRow has drifted from the widget it was '
              'measured against:\n${drift.join('\n')}');
    });

    testWidgets('the bare ShimmerList default does NOT match an InfoCard '
        '— which is why call sites must pass itemHeight', (tester) async {
      // Documented as a test rather than a comment, because it is the reason
      // the constant above exists. The default 80 is not wrong in itself — it
      // is right for a compact row — it is wrong to take it by accident on a
      // list of InfoCards. Screens whose rows are private classes cannot be
      // measured from here and are verified on the device instead.
      final real = await measure(tester, searchResultRow(), width: 360);
      expect((real.height - defaultItemHeight).abs(),
          greaterThan(shimmerListGap),
          reason: 'If the default now matches an InfoCard, this test and '
              'ShimmerCard.infoCardRow are both obsolete — delete them.');
    });
  });
}
