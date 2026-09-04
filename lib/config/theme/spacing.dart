import 'package:flutter/widgets.dart';

/// The spacing scale.
///
/// WHY. The Phase 0 audit could not find a spacing system because there was
/// not one: padding and gap values were written per call site, so the same
/// visual relationship was expressed as 10 in one file, 11 in another and 14 in
/// a third. Nothing was *wrong* individually, and that is the point — without a
/// scale there is no way to be wrong, and therefore no rhythm.
///
/// A scale does two things a free-form number cannot. It makes unequal things
/// look deliberately unequal (12 next to 24 reads as a decision; 12 next to 14
/// reads as a mistake). And it makes the whole app retunable from one file.
///
/// The steps are roughly geometric rather than linear, because perceived
/// difference is ratio-based: 4→8 is obvious, 44→48 is invisible.
///
/// Use [gap] / [vGap] for space BETWEEN siblings and let layout own it —
/// per-child margins silently collapse or double, which is the bug this
/// prevents.
class AppSpace {
  AppSpace._();

  /// Hairline separation. Icon to its own label.
  static const double xs = 4;

  /// Tightly related elements inside one component.
  static const double sm = 8;

  /// Default gap inside a component.
  static const double md = 12;

  /// Component padding, and the gap between components in a list.
  static const double lg = 16;

  /// Between distinct groups of content.
  static const double xl = 24;

  /// Section separation.
  static const double xxl = 32;

  /// Major breaks; the top of a screen under an app bar.
  static const double xxxl = 48;

  /// The full ladder, for asserting in tests that a value is on-scale.
  static const List<double> all = [xs, sm, md, lg, xl, xxl, xxxl];

  /// True when [v] sits on the scale. Used by the design-system test so an
  /// off-scale value fails CI rather than being noticed in review.
  static bool isOnScale(double v) => v == 0 || all.contains(v);

  // ------------------------------------------------------------------ helpers

  static const EdgeInsets allXs = EdgeInsets.all(xs);
  static const EdgeInsets allSm = EdgeInsets.all(sm);
  static const EdgeInsets allMd = EdgeInsets.all(md);
  static const EdgeInsets allLg = EdgeInsets.all(lg);
  static const EdgeInsets allXl = EdgeInsets.all(xl);

  /// Screen-edge padding. One value, so every screen's content aligns to the
  /// same vertical line — the single cheapest thing that makes an app look
  /// designed rather than assembled.
  static const EdgeInsets screenH = EdgeInsets.symmetric(horizontal: lg);

  /// Horizontal gap between siblings in a Row.
  static const Widget gapXs = SizedBox(width: xs);
  static const Widget gapSm = SizedBox(width: sm);
  static const Widget gapMd = SizedBox(width: md);
  static const Widget gapLg = SizedBox(width: lg);

  /// Vertical gap between siblings in a Column.
  static const Widget vGapXs = SizedBox(height: xs);
  static const Widget vGapSm = SizedBox(height: sm);
  static const Widget vGapMd = SizedBox(height: md);
  static const Widget vGapLg = SizedBox(height: lg);
  static const Widget vGapXl = SizedBox(height: xl);

  /// Minimum tappable extent. Anything interactive must reach this in both
  /// axes even when its painted size is smaller — wrap in a SizedBox or give
  /// the GestureDetector opaque behaviour and padding.
  ///
  /// The audit found stop markers painted at 14px acting as their own tap
  /// target, which is less than a third of this.
  static const double minTouchTarget = 48;

  /// Cross-axis height for a horizontal strip of chips, grown against the
  /// reader's text scale.
  ///
  /// A horizontally-scrolling ListView has to be given a fixed cross-axis
  /// extent, so every chip strip in the app hard-codes one — and a hard-coded
  /// height is a clipped label the moment someone turns text size up. Measured
  /// on the real widgets rather than reasoned about: the attendance course
  /// chip (12px label, 9px vertical padding) lays out at 30.0px at 1.0x and
  /// 42.0px at 2.0x, and [GlassChip] at 35.0px and 45.0px. Both had been
  /// wrapped in a bare `SizedBox(height: 38)` and `height: 44`, so both
  /// overflowed at the largest accessibility scale — by 4.0px and 1.0px.
  ///
  /// The 24-per-scale-step growth and the 62px cap are NOT new numbers: they
  /// are the formula `marks_entry_screen` already carried, whose own comment
  /// records that 38px "burst at 1.67x". Passing that screen's `base` of 38
  /// through here reproduces its current height exactly, which is the point —
  /// the fix unifies three call sites without re-rendering the one that was
  /// already right.
  ///
  /// [base] is what the strip measures at 1.0x; [max] stops a 3.0x system
  /// scale from handing a phone a 100px band of chips.
  static double chipStrip(BuildContext context, double base,
          {double max = 62}) =>
      (base + (MediaQuery.textScalerOf(context).scale(1) - 1) * 24)
          .clamp(base, max);
}
