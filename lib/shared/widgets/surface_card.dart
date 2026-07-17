import 'dart:ui';
import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_theme.dart';
import '../../config/theme/liquid_glass_tokens.dart';

/// Base-tier liquid glass for repeated content (list rows, dashboard tiles):
/// real frosted blur (the light [LiquidGlass.blurBase] sigma) + glossy sheen +
/// a tinted hairline border + the signature top-right cut, all clipped to the
/// rounded shape (so glyphs — and the web text-selection highlight — can never
/// paint past the border).
///
/// Every instance is wrapped in a [RepaintBoundary] and the blur is the cheap
/// base sigma, but on a long, fast-scrolling list even a cheap per-row
/// BackdropFilter can add up — pass `blur: false` there to fall back to a
/// solid tinted fill (visually near-identical over [LiquidBackdrop]) with zero
/// blur cost.
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? accent;
  final bool blur;
  final VoidCallback? onTap;

  const SurfaceCard({
    super.key,
    required this.child,
    this.radius = LiquidGlass.radiusCard,
    this.padding = const EdgeInsets.all(14),
    this.margin,
    this.accent,
    this.blur = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlassTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = LiquidGlass.signatureRadius(radius);
    final borderColor = accent?.withValues(alpha: 0.35) ?? glass.glassBorder;

    Widget content = Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: LiquidGlass.sheen(isDark: isDark),
              ),
            ),
          ),
        ),
        Padding(padding: padding, child: child),
      ],
    );

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        // With blur, lean on the translucent fill; without it, blend the fill
        // over the canvas so text keeps full contrast with no blur pass.
        color: blur
            ? AppColors.glassFill(context)
            : Color.alphaBlend(AppColors.glassFill(context), glass.canvas),
        borderRadius: borderRadius,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: content,
    );

    Widget card = ClipRRect(
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(
                  sigmaX: LiquidGlass.blurBase, sigmaY: LiquidGlass.blurBase),
              child: surface,
            )
          : surface,
    );

    if (onTap != null) {
      card = Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          child: card,
        ),
      );
    }

    return RepaintBoundary(
      child: Padding(
        padding: margin ?? EdgeInsets.zero,
        child: card,
      ),
    );
  }
}
