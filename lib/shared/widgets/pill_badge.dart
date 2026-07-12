import 'package:flutter/material.dart';

/// A small rounded status/role/category pill — the standard shape used
/// throughout the app (RETAKE, PRESIDENT, status filters, credit-hour tags,
/// etc). Centralized here because every one of these previously hand-rolled
/// a `Container(padding..., child: Text(...))` and, since the labels are
/// short all-caps/no-descender words ("ALL", "RETAKE", "PRESIDENT"), the
/// font reserved descent space for a g/y/p/q/j that never appears — the
/// glyphs visually sat near the top of the pill with dead space below,
/// confirmed live across Clubs, Class Schedule search, and elsewhere.
/// `applyHeightToLastDescent: false` ALONE was not enough — confirmed live
/// again on the "SUPER ADMIN" app-bar badge — the font's ASCENT reservation
/// above the actual cap-height glyphs is still being centered as if it were
/// real content, so the visible ink still sits high with a gap below.
/// `applyHeightToFirstAscent: false` trims that side too, so the line box
/// tightly hugs the glyphs and the pill's padding alone centers them.
class PillBadge extends StatelessWidget {
  final String label;
  final Color color;
  final double fontSize;
  final FontWeight fontWeight;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double letterSpacing;
  final Color? backgroundColor;
  final BorderSide? border;

  const PillBadge({
    super.key,
    required this.label,
    required this.color,
    this.fontSize = 10,
    this.fontWeight = FontWeight.w700,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    this.borderRadius = 10,
    this.letterSpacing = 0.3,
    this.backgroundColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: backgroundColor ?? color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(borderRadius),
          border: border != null ? Border.fromBorderSide(border!) : null,
        ),
        child: Text(
          label,
          textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
          style: TextStyle(color: color, fontSize: fontSize, height: 1.0, fontWeight: fontWeight, letterSpacing: letterSpacing),
        ),
      );
}
