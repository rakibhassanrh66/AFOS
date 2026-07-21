import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_tokens.dart';

/// A compact number-over-label stat tile — one component replacing the three
/// hand-rolled `_StatTile`s (manage_users / manage_clubs /
/// manage_conference_rooms). Overflow-safe label, optional icon + tap.
class StatTile extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;
  final Color color;
  final VoidCallback? onTap;
  final bool active;

  const StatTile({
    super.key,
    required this.value,
    required this.label,
    this.icon,
    this.color = AppColors.blue,
    this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final on = active || onTap != null;
    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.14) : AppColors.glassFill(context),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        border: Border.all(
          color: active ? color.withValues(alpha: 0.4) : AppColors.glassBorder(context),
          width: active ? 1 : 0.5,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: on ? color : AppColors.textSecondaryOf(context)),
                const Spacer(),
              ],
              // Flexible: maxLines/ellipsis alone do NOT prevent overflow --
              // the Text still claims its full intrinsic width, leaving the
              // Spacer at zero and pushing the Row past the tile. These sit
              // three-across in an Expanded Row on the admin summary bars, so
              // at a large text scale each tile is genuinely narrower than its
              // own number.
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: on ? color : AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              if (icon == null) const Spacer(),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 11),
          ),
        ],
      ),
    );
    if (onTap == null) return tile;
    return GestureDetector(onTap: onTap, child: tile);
  }
}
