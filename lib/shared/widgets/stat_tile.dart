import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_tokens.dart';
import 'pressable.dart';

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
          // Expanded + textAlign, NOT Spacer + Flexible.
          //
          // `Spacer` is an `Expanded` with flex 1, and `Flexible` defaults to
          // flex 1 too, so the pair split the free space 50/50: the number
          // could only ever use HALF the tile before ellipsising, with an equal
          // gap sitting beside it, and — because a loose `Flexible` gives back
          // whatever it doesn't use — it came to rest in a different horizontal
          // position on every tile, in proportion to how many digits it had.
          // Three of these side by side on the admin summary bars is where that
          // reads as scrambled.
          //
          // `Expanded` is tight, so the text gets the whole remaining width and
          // `textAlign` is what decides the edge. maxLines/ellipsis stay: they
          // do not prevent overflow on their own (the Text still claims its
          // intrinsic width), and these tiles are genuinely narrower than their
          // own number at a large text scale.
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: on ? color : AppColors.textSecondaryOf(context)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // Right when an icon holds the left, left when nothing does —
                  // which is where the label underneath starts.
                  textAlign: icon != null ? TextAlign.end : TextAlign.start,
                  style: TextStyle(
                    color: on ? color : AppColors.textPrimaryOf(context),
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
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
    // Pressable, not a bare GestureDetector: a stat tile is a control that
    // navigates, and it answered a touch with nothing at all until the route
    // pushed.
    return Pressable(onTap: onTap, child: tile);
  }
}
