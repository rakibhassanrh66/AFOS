import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_theme.dart';
import '../../config/theme/liquid_glass_tokens.dart';

/// Base-tier liquid glass for repeated content (list rows, dashboard tiles):
/// translucent fill + tinted hairline border + the signature top-right cut,
/// but deliberately NO BackdropFilter — a real blur on every row is exactly
/// the per-frame cost that caused this app's documented jank complaints.
/// Rows read as glass because they sit over [LiquidBackdrop]'s soft wash;
/// reserve true frost for GlassCard (raised) and GlassSheet (floating).
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  const SurfaceCard({
    super.key,
    required this.child,
    this.radius = LiquidGlass.radiusCard,
    this.padding = const EdgeInsets.all(14),
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlassTheme.of(context);
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        // Solid-ish tint of the canvas so text keeps full contrast without
        // needing a blur pass behind it.
        color: Color.alphaBlend(AppColors.glassFill(context), glass.canvas),
        borderRadius: LiquidGlass.signatureRadius(radius),
        border: Border.all(color: glass.glassBorder, width: 1),
      ),
      child: child,
    );
  }
}
