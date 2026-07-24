import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_text_styles.dart';

/// A single "label … value" row — one component replacing the four near-identical
/// `_InfoTile` / `_InfoRow` / `_ReadOnlyRow` / `_DetailRow` implementations. The
/// value is always overflow-safe (truncates at the right edge, never pushes past
/// the container).
class LabelValueRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Color? valueColor;
  final int valueMaxLines;
  final EdgeInsetsGeometry padding;

  const LabelValueRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.valueColor,
    this.valueMaxLines = 1,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        // Center, not start: the icon (18px), the label (bodyMedium) and the
        // value (titleMedium, a larger style) all have different intrinsic
        // heights, so top-aligning them left the icon and label sitting
        // visibly higher than the value's baseline — the "profile text
        // alignment" this fixes. Centering the row is also correct for the
        // rare 2-line label wrap: the icon settles against the middle of the
        // wrapped block rather than pinned to just its first line.
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.textSecondaryOf(context)),
            const SizedBox(width: 10),
          ],
          // FIXED width, not Flexible: with a Flexible label, each row's label
          // column was exactly as wide as that row's OWN text ("Name" vs
          // "Student ID" vs "Department"), and the value was right-aligned to
          // the far edge on top of that — so the gap between label and value
          // varied row to row (small for a long label + long value, huge for
          // a short label + short value), reading as "scrambled" alignment
          // down the card. A fixed column plus a left-aligned value gives
          // every row the same label width and the same small gap, so values
          // start at one consistent x position — the actual fix for "some
          // words too far, some too close". 100 comfortably fits every label
          // this widget is used with today ("Student ID", "Designation",
          // "Department") on one line at default text scale; maxLines: 2
          // below is the safety net at larger accessibility scales.
          SizedBox(
            width: 100,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondaryOf(context)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              maxLines: valueMaxLines,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleMedium.copyWith(
                  color: valueColor ?? AppColors.textPrimaryOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}
