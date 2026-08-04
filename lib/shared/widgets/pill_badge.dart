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

  /// Hard ceiling on how much room a badge may take.
  ///
  /// A `Row` lays its non-flex children out FIRST with unbounded width and
  /// gives an `Expanded` sibling only the remainder — so a badge with a long
  /// label takes the entire row and leaves the title beside it with 0.0px, i.e.
  /// invisible. That is not a RenderFlex overflow and no overflow test catches
  /// it. It shipped twice on the Teaching Load cards.
  ///
  /// 160 is deliberately generous for a real badge ('SUBMITTED', 'AWAITING',
  /// 'SUPER ADMIN' all fit unclipped at normal scale) and still leaves the
  /// title a usable share on a 320dp phone. It does NOT scale with the text
  /// scaler, on purpose: the point is to bound the badge's appetite, and a cap
  /// that grew with the font would stop capping anything.
  ///
  /// That was tested rather than assumed. Making it scale — to fix a badge
  /// clipping its own 'UNANSWERED' at 2.0x — immediately re-broke the guard
  /// case in `course_offering_layout_test`: a 29-character label was free to
  /// take 60% of the screen and left the title beside it 26px of the 182px it
  /// needed. The cap exists precisely for that shape and cannot be relaxed
  /// globally.
  ///
  /// **Pass `maxWidth: double.infinity` when the badge is on a line of its
  /// own.** There it competes with nothing, so the cap has nothing to defend
  /// and only gets in the way of showing the label at a large text scale.
  final double maxWidth;

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
    this.maxWidth = 160,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: backgroundColor ?? color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(borderRadius),
          border: border != null ? Border.fromBorderSide(border!) : null,
        ),
        child: Text(
          label,
          // A pill is one line, always. Without this a long label in a badge
          // that ends up width-constrained wraps into a vertical column of
          // single letters -- and worse, an UNCONSTRAINED long label makes the
          // badge demand the whole Row, leaving a sibling `Expanded(Text)` with
          // 0.0px and rendering THAT one letter per line. Both were live on the
          // Teaching Load cards ('ACCEPTED — CREATE OFFERING' at 26 characters),
          // reproducing from 1.0x text scale on a 320dp phone upward.
          // Keep labels to a word or two; see course_offering_layout_test.dart.
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
          style: TextStyle(color: color, fontSize: fontSize, height: 1.0, fontWeight: fontWeight, letterSpacing: letterSpacing),
        ),
      ),
    );
  }
}
