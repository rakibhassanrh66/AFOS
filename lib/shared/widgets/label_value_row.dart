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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: AppColors.textSecondaryOf(context)),
            const SizedBox(width: 10),
          ],
          Text(
            label,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
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
