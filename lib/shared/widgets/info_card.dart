import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_text_styles.dart';
import '../../config/theme/liquid_glass_tokens.dart';
import 'surface_card.dart';

/// The app's standard glass content card for lists/feeds — one component
/// replacing the ~9 hand-rolled `_NoticeCard`/`_ClassCard`/`_BookCard`/… raw
/// `Container`s. Built on [SurfaceCard] (base-tier blur + sheen + clip), with
/// overflow-safe title/subtitle baked in so long text always truncates inside
/// the rounded border instead of painting past it.
///
/// Two shapes:
///  * Provide [icon]/[title]/[subtitle]/[trailing] for the common
///    icon-badge + two-line layout.
///  * Provide [child] for a fully custom body (still clipped + accented).
class InfoCard extends StatelessWidget {
  final Color accent;
  final IconData? icon;
  final Widget? leading;
  final String? title;
  final String? subtitle;
  final int subtitleMaxLines;
  final Widget? trailing;
  final Widget? child;
  final VoidCallback? onTap;
  final bool stripe;
  final bool blur;
  final EdgeInsetsGeometry padding;
  final double radius;

  const InfoCard({
    super.key,
    this.accent = AppColors.blue,
    this.icon,
    this.leading,
    this.title,
    this.subtitle,
    this.subtitleMaxLines = 2,
    this.trailing,
    this.child,
    this.onTap,
    this.stripe = false,
    this.blur = true,
    this.padding = const EdgeInsets.all(14),
    this.radius = LiquidGlass.radiusCard,
  });

  @override
  Widget build(BuildContext context) {
    final body = child ?? _defaultBody(context);
    return SurfaceCard(
      accent: accent,
      blur: blur,
      radius: radius,
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: stripe
          ? IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(width: 3, color: accent),
                  Expanded(child: Padding(padding: padding, child: body)),
                ],
              ),
            )
          : Padding(padding: padding, child: body),
    );
  }

  Widget _defaultBody(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null)
          Padding(padding: const EdgeInsets.only(right: 12), child: leading)
        else if (icon != null) ...[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: accent, size: 20),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Text(
                  title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.textPrimaryOf(context)),
                ),
              if (title != null && subtitle != null) const SizedBox(height: 2),
              if (subtitle != null)
                Text(
                  subtitle!,
                  maxLines: subtitleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondaryOf(context)),
                ),
            ],
          ),
        ),
        if (trailing != null)
          Padding(padding: const EdgeInsets.only(left: 8), child: trailing),
      ],
    );
  }
}
