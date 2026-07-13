import 'package:flutter/material.dart';
import '../../config/theme/liquid_glass_theme.dart';

/// The canvas every glass surface floats over: the flat canvas color plus
/// two very soft, very low-alpha radial washes in the capped brand hues.
/// Deliberately restrained — the Liquid Glass spec forbids the
/// gradient-mesh "purple blob field" look; the washes exist only so the
/// blur tiers have something gentle to refract, and they are static
/// (no animation, no repaint cost).
class LiquidBackdrop extends StatelessWidget {
  final Widget child;
  const LiquidBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlassTheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final washAlpha = isDark ? 0.10 : 0.07;
    return DecoratedBox(
      decoration: BoxDecoration(color: glass.canvas),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Teal wash, upper-left quadrant.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.9, -0.85),
                radius: 1.1,
                colors: [
                  glass.accent.withValues(alpha: washAlpha),
                  glass.accent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          // Blue wash, lower-right quadrant.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1.0, 0.9),
                radius: 1.2,
                colors: [
                  glass.accentSecondary.withValues(alpha: washAlpha),
                  glass.accentSecondary.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
