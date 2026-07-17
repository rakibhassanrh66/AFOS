import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_text_styles.dart';
import '../../config/theme/liquid_glass_tokens.dart';

/// The glossy gradient hero header used at the top of most feature screens —
/// one component replacing the ~15 inline `Container(gradient: …)` headers each
/// screen hand-rolled. Rounded, clipped, with a glossy sheen and overflow-safe
/// title/subtitle (white-on-gradient).
///
/// [accent] drives a two-stop gradient in-family; pass an explicit [gradient]
/// to override (e.g. the brand [AppColors.holoGradient] or a module gradient).
class FeatureHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color accent;
  final Gradient? gradient;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const FeatureHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.accent = AppColors.blue,
    this.gradient,
    this.trailing,
    this.padding = const EdgeInsets.all(18),
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final g = gradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.92),
            Color.lerp(accent, AppColors.background, 0.35)!,
          ],
        );
    return Padding(
      padding: margin,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
          clipBehavior: Clip.antiAlias,
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: g),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration:
                          BoxDecoration(gradient: LiquidGlass.sheen(isDark: isDark)),
                    ),
                  ),
                ),
                Padding(
                  padding: padding,
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(icon, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 14),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.headlineLarge
                                  .copyWith(color: Colors.white),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 3),
                              Text(
                                subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.bodyMedium.copyWith(
                                    color: Colors.white.withValues(alpha: 0.85)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: 12),
                        trailing!,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
