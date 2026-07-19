import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_theme.dart';
import '../../config/theme/liquid_glass_tokens.dart';

/// Floating-tier glass for modals and bottom sheets: heaviest frost, the
/// signature 28px top radius, a drag handle, and one tuned entrance
/// (LiquidGlass.motionStandard / motionCurve, scale-from + fade) so every
/// sheet in the app opens the same way. Use via [showGlassSheet] (inline
/// content — the sheet owns padding + keyboard lift) or [showGlassModal]
/// (wrap an existing sheet builder that already provides its own padding /
/// keyboard handling).
class GlassSheet extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// When true the whole sheet is translated above the keyboard (for inline
  /// content with fields). Feature sheets that already pad by
  /// `MediaQuery.viewInsets.bottom` pass false to avoid doubling.
  final bool liftForKeyboard;

  const GlassSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 24),
    this.liftForKeyboard = true,
  });

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlassTheme.of(context);
    const radius = BorderRadius.vertical(top: Radius.circular(LiquidGlass.radiusSheet));
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final keyboardInset = liftForKeyboard ? MediaQuery.of(context).viewInsets.bottom : 0.0;

    final body = ClipRRect(
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: BackdropFilter(
        filter: LiquidGlass.frost(LiquidGlass.blurFloating),
        child: DecoratedBox(
          decoration: BoxDecoration(
            // Sheets sit over dimmed content, so the fill leans on the canvas
            // color for legibility — but lowered (0.86 -> 0.6) so the frost
            // reads as translucent glass rather than a flat solid panel.
            color: Color.alphaBlend(AppColors.glassFill(context), glass.canvas.withValues(alpha: 0.6)),
            borderRadius: radius,
            border: Border.all(color: glass.glassBorder, width: 1),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle always gets its own breathing room, independent of
                // the child's padding.
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(top: 10, bottom: 8),
                    decoration: BoxDecoration(
                      color: glass.glassBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Flexible(child: Padding(padding: padding, child: child)),
              ],
            ),
          ),
        ),
      ),
    );

    final lifted = keyboardInset > 0
        ? Padding(padding: EdgeInsets.only(bottom: keyboardInset), child: body)
        : body;

    if (reduceMotion) return lifted;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: LiquidGlass.entranceDuration,
      curve: LiquidGlass.motionCurve,
      child: lifted,
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

/// Standard entry point for a Liquid Glass bottom sheet with **inline**
/// content — the sheet owns the padding, drag handle, frost, and keyboard
/// lift. Pass a scrollable child (SingleChildScrollView / a min Column).
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required Widget child,
  bool isScrollControlled = true,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(20, 0, 20, 24),
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      builder: (_) => GlassSheet(padding: padding, child: child),
    );

/// Wraps an existing sheet [builder] (that already supplies its own padding /
/// keyboard handling / StatefulBuilder) in the glass frost + tuned entrance —
/// a one-line migration for the app's bespoke feature sheets. The builder's
/// content is left untouched (padding defaults to zero here, and the sheet
/// does NOT double the keyboard lift).
Future<T?> showGlassModal<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
  bool isDismissible = true,
  bool enableDrag = true,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => GlassSheet(
        padding: padding,
        liftForKeyboard: false,
        child: Builder(builder: builder),
      ),
    );
