import 'package:flutter/material.dart';

import 'app_colors.dart';

/// The palette for DATA marks — deliberately not the UI accent colours.
///
/// WHY THIS IS A SEPARATE FILE. Until now every chart in AFOS drew itself with
/// `AppColors.holoBlue / holoTeal / holoviolet / amber`, which are UI accents
/// chosen to sit on chrome. Run through the dataviz validator against the real
/// surfaces this app uses, that set FAILS in both modes:
///
///   light, on #FFFFFF   3 of 4 fills below the 3:1 contrast floor
///                       (holoBlue 2.1, holoTeal 1.94, amber 2.08)
///   dark,  on #101A2D   3 of 4 outside the L 0.48–0.67 band
///                       (0.755, 0.762, 0.766 — far too light)
///
/// An accent that reads well as a 2px border or a glow is not the same thing as
/// a fill a reader has to compare areas of. These steps are the same four hue
/// families re-stepped until the validator passes, per mode:
///
///   node scripts/validate_palette.js "#1B78C2,#10855A,#6A56C8,#96660A" \
///        --mode light --surface "#FFFFFF"   -> ALL CHECKS PASS
///   node scripts/validate_palette.js "#3187C8,#1E9A69,#7460C6,#B37F1C" \
///        --mode dark  --surface "#101A2D"   -> ALL CHECKS PASS
///
/// Re-run both if you touch a value. Do not eyeball it — the failure mode is a
/// chart that looks fine to you and is unreadable to someone else.
///
/// KNOWN AND HANDLED: the blue and the green separate by ΔE ~3–4 under
/// TRITANOPIA (they pass on deuteranopia at ~17). Blue-blind readers cannot
/// tell those two fills apart by colour, so anywhere they are adjacent — the
/// occupancy ring above all — the mark MUST carry secondary encoding: a direct
/// label, a value in the legend, and a surface-coloured gap between fills.
/// That is not decoration, it is the thing making the chart readable.
class ChartPalette {
  ChartPalette._();

  // Fixed order. Slot 0 is always the first series, slot 3 always the fourth,
  // whatever the data is — colour follows the entity, never its rank, so a
  // filter that drops a series must never repaint the survivors.
  static const List<Color> _light = [
    Color(0xFF1B78C2), // blue
    Color(0xFF10855A), // green
    Color(0xFF6A56C8), // violet
    Color(0xFF96660A), // amber
  ];

  static const List<Color> _dark = [
    Color(0xFF3187C8),
    Color(0xFF1E9A69),
    Color(0xFF7460C6),
    Color(0xFFB37F1C),
  ];

  /// The de-emphasis ink, and the fill for a folded "Other" bucket.
  static Color muted(BuildContext c) => AppColors.isDark(c)
      ? const Color(0xFF5A6B85)
      : const Color(0xFF8A97A8);

  static List<Color> of(BuildContext c) =>
      AppColors.isDark(c) ? _dark : _light;

  /// The colour for series [i].
  ///
  /// NEVER CYCLES. The old role-breakdown did `_accents[i % length]`, which
  /// silently hands series 4 the same fill as series 0 — two different things
  /// wearing one colour, which is worse than an honest grey. Past the fourth
  /// slot everything is [muted], and the caller is expected to have folded the
  /// tail into a single "Other" row before it ever gets here.
  static Color series(BuildContext c, int i) {
    final p = of(c);
    return (i >= 0 && i < p.length) ? p[i] : muted(c);
  }

  /// How many distinct series this palette can seat before folding is required.
  static const int seats = 4;

  /// Single-hue ramp for MAGNITUDE — heatmaps, density grids, anything where
  /// more is darker. A rainbow here would make a reader decode a legend for
  /// every cell.
  ///
  /// VALIDATED as an ordinal ramp, which is a different set of checks from the
  /// categorical one above — monotone lightness, adjacent ΔL >= 0.06, a single
  /// hue, and a LIGHT END THAT CLEARS THE SURFACE. That last one failed three
  /// times before this: the obvious pale first step (#DCEBF7) sits at 1.22:1
  /// on white, so the lowest-density cell was invisible and the grid appeared
  /// to have holes in it. Both ramps now start at ~2.2:1.
  ///
  ///   --ordinal --mode light --surface "#FFFFFF"  -> ALL CHECKS PASS
  ///   --ordinal --mode dark  --surface "#101A2D"  -> ALL CHECKS PASS
  static List<Color> ramp(BuildContext c) => AppColors.isDark(c)
      ? const [
          Color(0xFF31566F),
          Color(0xFF3E7192),
          Color(0xFF4B8DB5),
          Color(0xFF58AAD8),
          Color(0xFF6DC5F2),
        ]
      : const [
          Color(0xFF83B5DD),
          Color(0xFF6098CA),
          Color(0xFF3F7BB2),
          Color(0xFF245F94),
          Color(0xFF0E4372),
        ];

  /// Picks a ramp step for [value] within [max]. Zero is the lightest step
  /// rather than transparent, so an empty cell still reads as a cell and the
  /// grid keeps its shape.
  static Color rampStep(BuildContext c, num value, num max) {
    final steps = ramp(c);
    if (max <= 0) return steps.first;
    final t = (value / max).clamp(0.0, 1.0);
    return steps[(t * (steps.length - 1)).round()];
  }

  /// Reserved for STATE, never for "series 5". Always shipped with a word
  /// beside them — a pill that is only green tells a colour-blind reader
  /// nothing, and these all carry a fact somebody has to act on.
  static Color good(BuildContext c) => series(c, 1);
  static Color warning(BuildContext c) => series(c, 3);
  static Color critical(BuildContext c) =>
      AppColors.isDark(c) ? const Color(0xFFD2566E) : const Color(0xFFB3243F);

  /// The recessive ink for grid lines and axes. Chart furniture must never
  /// compete with the marks it measures.
  static Color grid(BuildContext c) =>
      AppColors.borderOf(c).withValues(alpha: AppColors.isDark(c) ? 0.55 : 0.9);
}
