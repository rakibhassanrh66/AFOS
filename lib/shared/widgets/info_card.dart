import '../../config/theme/depth.dart';
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
    // From 1.3x the trailing control drops below the text instead of sitting
    // beside it.
    //
    // Bounding it (below) stops it starving the title, but bounding cannot
    // create room that is not there: at a large accessibility scale an icon, a
    // two-line title, a subtitle AND a status badge do not fit across a 320dp
    // phone, so whatever loses the negotiation gets cut — the badge was showing
    // half of "SUBMITTED". Below the text it has the full card width and
    // nothing is truncated at all.
    if (trailing == null) return _defaultRow(context, includeTrailing: false);

    return LayoutBuilder(builder: (context, constraints) {
      // Width AND text scale, because this starves at BOTH. On a 320dp phone
      // at a perfectly ordinary 1.0x, an icon plus a status badge left the
      // title 91px for 160px of course title — 75% of it gone with no
      // accessibility setting involved at all. A text-scale trigger alone
      // would have missed that entirely.
      final roomy = constraints.maxWidth >= 400 &&
          MediaQuery.textScalerOf(context).scale(1.0) < 1.3;
      if (roomy) return _defaultRow(context, includeTrailing: true);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _defaultRow(context, includeTrailing: false),
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: trailing),
        ],
      );
    });
  }

  Widget _defaultRow(BuildContext context, {required bool includeTrailing}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null)
          Padding(padding: const EdgeInsetsDirectional.only(end: 12), child: leading)
        else if (icon != null) ...[
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: AppDepth.radius(1),
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
                  // Two lines. A course title beside a trailing control had
                  // 104px for 140px of text, so 86% of it was cut. The second
                  // line is only taken when the title needs it, so short
                  // titles — most of them — look exactly as before.
                  maxLines: 2,
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
        // Flexible, not a bare child: as a non-flex sibling the trailing widget
        // was laid out first at its full intrinsic width, leaving the Expanded
        // title 0.0px and rendering it one letter per line. This is the card
        // ~9 screens are built from, so the same starve was live in all of
        // them. Measured by shared_widgets_layout_test with a real course title
        // and a 'Remove from this course' button.
        // Bounded, not unbounded and not freely shrinkable.
        //
        // Left as a bare child it was laid out first at whatever width it
        // wanted, leaving the Expanded title 0.0px — one letter per line, in
        // the card ~9 screens are built from. Wrapping it in `Flexible`
        // overcorrected: a status badge then got squeezed to 10px and hid half
        // its own word.
        //
        // A hard ceiling gives both what they need. A badge or icon button is
        // well under 160 and renders at its natural size; only a wide control
        // is capped, and only it gives way.
        if (trailing != null && includeTrailing)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 8), child: trailing),
          ),
      ],
    );
  }
}
