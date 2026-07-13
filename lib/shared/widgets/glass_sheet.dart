import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_theme.dart';
import '../../config/theme/liquid_glass_tokens.dart';

/// Floating-tier glass for modals and bottom sheets: heaviest frost, 28px
/// top radius, entrance scale 0.96 → 1.0 (plain appearance under reduced
/// motion). Use via [showGlassSheet] so every sheet in the app shares one
/// treatment instead of each screen hand-rolling its own container.
class GlassSheet extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const GlassSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 24),
  });

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlassTheme.of(context);
    const radius = BorderRadius.vertical(top: Radius.circular(LiquidGlass.radiusSheet));
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    final body = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: LiquidGlass.frost(LiquidGlass.blurFloating),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            // Sheets sit over dimmed content, so the fill leans on the
            // canvas color for legibility instead of pure translucency.
            color: Color.alphaBlend(AppColors.glassFill(context), glass.canvas.withValues(alpha: 0.86)),
            borderRadius: radius,
            border: Border.all(color: glass.glassBorder, width: 1),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: glass.glassBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Flexible(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (reduceMotion) return body;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: LiquidGlass.entranceDuration,
      curve: Curves.easeOut,
      child: body,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(
          scale: LiquidGlass.entranceScaleFrom + (1 - LiquidGlass.entranceScaleFrom) * t,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
    );
  }
}

/// Standard entry point for Liquid Glass bottom sheets.
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required Widget child,
  bool isScrollControlled = true,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      builder: (_) => GlassSheet(child: child),
    );
