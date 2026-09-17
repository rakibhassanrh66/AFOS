import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';

/// Foreground colours for the About screen that are legible in BOTH themes.
///
/// Its own file so that the card and the content widgets can both use it
/// without importing each other.

/// WCAG 2.1 contrast ratio between two opaque colours.
///
/// `Color.computeLuminance()` already is the WCAG relative-luminance formula,
/// so this is the whole of it.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// An accent colour that is safe to use as TEXT on [background].
///
/// WHY THIS IS NEEDED, with the numbers. This screen uses its accents as
/// foreground — the credential chips, the "turn it over" label, the support
/// button. On the dark canvas that is comfortable: the brand teal measures
/// **8.02:1** against the card. In LIGHT mode the same colour on a near-white
/// card measures **1.93:1**, and the sky blue **2.07:1**, against a required
/// 4.5:1. Not marginal — under half. The text is present and effectively
/// unreadable, and no amount of checking on a dark emulator would show it.
///
/// So the colour is darkened in small steps until it actually passes. It is
/// COMPUTED rather than hand-picked so it stays correct if an accent changes:
/// a constant chosen once is a constant nobody re-measures.
///
/// NOTE FOR LATER, and deliberately not fixed here: `PillBadge` and friends in
/// `lib/shared/widgets/` paint an accent as text over a 14% tint of itself with
/// no light-mode adjustment, so the same fault is app-wide. Changing shared
/// widgets is outside this change's file scope.
Color readableOn(Color accent, Color background) {
  var c = accent;
  // 20 steps of 8% bottoms out near 19% of the original, darker than any
  // accent needs against white. The loop exits as soon as it passes.
  for (var i = 0; i < 20 && contrastRatio(c, background) < 4.5; i++) {
    c = Color.lerp(c, Colors.black, 0.08)!;
  }
  return c;
}

/// Muted text that stays legible in both themes.
///
/// `AppColors.textMutedOf` drops light mode to `lightMuted` at 70% alpha, which
/// composites to **3.23:1** on a white card — acceptable for a large heading,
/// not for the body copy this screen uses it for (glossary definitions,
/// timeline entries, the translation under the dedication). At full alpha the
/// same colour is 6.53:1. Dark mode is left alone at 5.07:1, so the
/// muted-below-secondary hierarchy survives where it actually reads.
Color aboutMuted(BuildContext context) =>
    AppColors.isDark(context) ? AppColors.textMuted : AppColors.lightMuted;
