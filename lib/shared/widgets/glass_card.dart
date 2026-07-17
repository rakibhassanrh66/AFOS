import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_theme.dart';
import '../../config/theme/liquid_glass_tokens.dart';

/// Liquid Glass depth tiers.
///
/// [base] is cheap enough for repeated tiles; [raised] is the default hero
/// card; [floating] is reserved for one-off overlays (modals, the VR-ID
/// card) — it carries the heaviest blur and an entrance scale-in, so never
/// put it inside a scrolling list (this app has a documented jank history
/// around per-row BackdropFilters).
enum GlassTier { base, raised, floating }

/// The app's signature surface: frosted blur + saturation boost behind a
/// translucent fill, a tinted (never grey) hairline border, an ambient
/// tinted glow (never a black drop shadow), and the AFOS silhouette — three
/// large corners with the top-right cut tight.
///
/// [animated] previously drove a perpetual sweep-gradient rotation (a
/// continuous GPU cost); it now opts into the floating-tier entrance
/// animation instead, honoring `MediaQuery.disableAnimations`.
class GlassCard extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final Color? glowColor;
  final bool animated;
  final EdgeInsetsGeometry? padding;
  final GlassTier tier;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = LiquidGlass.radiusCard,
    this.glowColor,
    this.animated = false,
    this.padding,
    this.tier = GlassTier.raised,
    this.onTap,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _pressed = false;

  double get _sigma => switch (widget.tier) {
        GlassTier.base => LiquidGlass.blurBase,
        GlassTier.raised => LiquidGlass.blurRaised,
        GlassTier.floating => LiquidGlass.blurFloating,
      };

  void _setPressed(bool v) {
    if (widget.onTap == null) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlassTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = LiquidGlass.signatureRadius(widget.borderRadius);
    final tint = widget.glowColor;
    final border = tint?.withValues(alpha: 0.35) ?? glass.glassBorder;
    final glow = tint?.withValues(alpha: 0.18) ?? glass.ambientShadow;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // Press adds +4 blur per the Liquid Glass motion spec.
    final sigma = _pressed ? _sigma + 4 : _sigma;

    Widget glassBody = Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: widget.tier == GlassTier.base
            ? null
            : [
                BoxShadow(
                  color: glow,
                  blurRadius: widget.tier == GlassTier.floating ? 48 : 40,
                  offset: const Offset(0, 12),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: BackdropFilter(
          filter: LiquidGlass.frost(sigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.glassFill(context),
              borderRadius: radius,
              border: Border.all(color: border, width: 1),
            ),
            child: Stack(
              children: [
                // Glossy sheen: light catching the glass, painted over the
                // fill and behind the content (never intercepts pointers).
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        gradient: LiquidGlass.sheen(isDark: isDark),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: widget.padding ?? EdgeInsets.zero,
                  child: widget.child,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.onTap != null) {
      glassBody = GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: reduceMotion
            ? glassBody
            : AnimatedScale(
                scale: _pressed ? LiquidGlass.pressScale : 1.0,
                duration: LiquidGlass.pressDuration,
                curve: Curves.easeOut,
                child: glassBody,
              ),
      );
    }

    final wantsEntrance =
        (widget.animated || widget.tier == GlassTier.floating) && !reduceMotion;
    if (!wantsEntrance) return glassBody;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: LiquidGlass.entranceDuration,
      curve: Curves.easeOut,
      child: glassBody,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: LiquidGlass.entranceScaleFrom +
              (1 - LiquidGlass.entranceScaleFrom) * t,
          child: child,
        ),
      ),
    );
  }
}
