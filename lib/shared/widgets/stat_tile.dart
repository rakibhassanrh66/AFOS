import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_text_styles.dart';
import '../../config/theme/depth.dart';
import '../../config/theme/spacing.dart';

/// A compact number-over-label stat tile, and the hairline that separates two
/// of them.
///
/// ONE component replacing the three hand-rolled `_StatTile`s that stood in
/// `manage_users_screen`, `manage_clubs_screen` and
/// `manage_conference_rooms_screen`. Two of those three were byte-identical
/// and the third differed only by an `onTap`, so the app carried three copies
/// of one design and three places to fix anything wrong with it.
///
/// WHY THIS SHAPE, AND NOT A BORDERED CARD. An earlier version of this file
/// was a self-contained bordered tile with its own fill and radius. It never
/// got adopted, and it could not have been: every real call site puts these
/// inside a [GlassCard] with [StatDivider] hairlines between them, so a tile
/// with its own border is a box drawn inside a box. The design that shipped is
/// borderless and centred, and that is the one this component now is.
class StatTile extends StatelessWidget {
  final String label;
  final int value;

  /// Optional destination. A tile without one is a readout, not a control, and
  /// deliberately gets no press affordance.
  final VoidCallback? onTap;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // maxLines + ellipsis on BOTH lines, which none of the three copies
        // had. These sit two or three to a row inside a fixed-width card, so
        // at a large system text scale the number and the label genuinely are
        // wider than the space they get — "CR Requests" at 2.0x overflowed and
        // striped the admin header yellow.
        Text(
          '$value',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.displayMedium.copyWith(
            color: AppColors.holoviolet,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: AppTextStyles.labelSmall
              .copyWith(color: AppColors.textSecondaryOf(context)),
        ),
      ],
    );
    if (onTap == null) return content;
    return InkWell(
      borderRadius: AppDepth.radius(0),
      onTap: onTap,
      // A stat tile that navigates is a control, so it has to be reachable as
      // one: centred content in an Expanded is often only ~20dp tall, well
      // under the 48dp floor, and the whole row is a common mis-tap target.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSpace.minTouchTarget),
        child: Center(child: content),
      ),
    );
  }
}

/// The hairline between two [StatTile]s. Was `_StatDivider` in
/// `manage_users_screen` and an inline `Container(width: 0.5, …)` in the other
/// two — same three-copy problem, smaller.
class StatDivider extends StatelessWidget {
  const StatDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
      width: 0.5, height: 32, color: AppColors.borderOf(context));
}
