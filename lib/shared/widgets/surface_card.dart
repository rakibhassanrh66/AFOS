import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';

/// The plain neutral bordered-surface block (surface color + rounded
/// corners + a 0.5px border in the theme's border color) was hand-rolled
/// as an ad hoc Container in 20+ files with no shared widget, which let
/// border widths/colors drift out of sync between screens (some 0.5px
/// surface borders sitting right next to unrelated 2px avatar-ring/
/// selection borders) — this is the "double border" inconsistency users
/// noticed. Use this instead of repeating the Container/BoxDecoration
/// pattern; leave genuinely different borders (avatar rings, selection
/// state, colored type-indicators) as their own explicit styling.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  const SurfaceCard({
    super.key,
    required this.child,
    this.radius = 14,
    this.padding = const EdgeInsets.all(14),
    this.margin,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.surfaceOf(context),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: AppColors.borderOf(context), width: 0.5),
        ),
        child: child,
      );
}
