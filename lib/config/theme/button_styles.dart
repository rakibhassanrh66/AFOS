import 'package:flutter/material.dart';

import 'liquid_glass_tokens.dart';

/// Opt-out from the app theme's full-width button sizing, for buttons that sit
/// beside another control instead of being a screen's primary action.
///
/// WHY THIS EXISTS. Both `elevatedButtonTheme` and `outlinedButtonTheme` set
/// `minimumSize: Size(double.infinity, 52)`. That is right for a form's submit
/// button and wrong for every Decline/Accept, Remove/Reconsider or
/// Withdraw/Reopen pair: each button demands the ENTIRE row width, so
///
///   * in a `Row`, the second one is pushed off the edge and clipped — which is
///     the "the admin could see the pending offering and had no way to act on
///     it" bug, previously diagnosed as the pair needing "~301px in a 297px
///     card" and worked around with a Wrap. The 4px was a red herring; an
///     infinitely-wide button never fits next to anything.
///   * in a `Wrap`, each one takes a line of its own, which is what the Join
///     Requests cards actually shipped as: a full-width Decline with a small
///     Accept stranded underneath it.
///
/// `FilledButton` is unaffected because the app sets no `filledButtonTheme`,
/// which is why the two halves of a pair rendered at different widths.
///
/// 44 is the minimum comfortable touch target; the width floor goes to zero so
/// the button is as wide as its label needs and no wider.
final ButtonStyle kRowActionButton = ButtonStyle(
  minimumSize: WidgetStateProperty.all(const Size(0, 44)),
  padding: WidgetStateProperty.all(
      const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  shape: WidgetStateProperty.all(RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(LiquidGlass.radiusControl))),
);

/// [kRowActionButton] merged with a caller's own `styleFrom` (usually just a
/// foreground colour), so a call site keeps its colour without restating the
/// sizing.
ButtonStyle rowAction([ButtonStyle? base]) =>
    base == null ? kRowActionButton : kRowActionButton.merge(base);
