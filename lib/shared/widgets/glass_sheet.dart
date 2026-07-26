import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_theme.dart';
import '../../config/theme/liquid_glass_tokens.dart';

/// How many glass sheets are currently on screen.
///
/// Sheets deliberately live on the SHELL navigator (see [showGlassSheet]), so
/// they are a *sibling* of the floating bottom nav in AppShell's Stack — and
/// the nav is a later child, so it paints straight over the sheet. On the New
/// Course Offering form that put the frosted bar on top of the Submit button,
/// reading as "an extra square box cutting things off".
///
/// AppShell watches this and hides the bar while any sheet is open. A counter
/// rather than a bool because a sheet can open a second sheet over itself (the
/// meeting editor used to do exactly that), and the nav must stay hidden until
/// the last one closes.
final ValueNotifier<int> openGlassSheetCount = ValueNotifier<int>(0);

/// Runs [show] with the sheet counter held up for the whole lifetime of the
/// route, so the count is correct however the sheet is dismissed — Navigator
/// .pop, a drag, a scrim tap, or the hardware back button.
Future<T?> _countedSheet<T>(Future<T?> Function() show) async {
  openGlassSheetCount.value++;
  try {
    return await show();
  } finally {
    openGlassSheetCount.value--;
  }
}

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
    final mq = MediaQuery.of(context);
    final reduceMotion = mq.disableAnimations;
    final keyboardInset = liftForKeyboard ? mq.viewInsets.bottom : 0.0;

    // AppShell inflates padding.bottom by the floating nav's clearance so that
    // ordinary screens keep their content above the bar. A sheet must NOT
    // reserve that: the bar is hidden for as long as one is open (see
    // openGlassSheetCount), so honouring the inflated inset just leaves a tall
    // empty frosted band under the form. Read the untouched window insets
    // rather than subtracting the bar's height back off — no magic constant,
    // and it stays correct if the bar is ever resized.
    final deviceBottom = MediaQueryData.fromView(View.of(context)).padding.bottom;

    // `isScrollControlled: true` lets a tall form (the New Course Offering one
    // especially) grow to the full window height, which slid the drag handle
    // and the first field up under the status bar / camera notch. The browser
    // has no notch, which is why this only ever reproduced on the phone. Cap
    // the sheet so it always stops clear of it.
    //
    // Guarded because the subtraction can go non-positive on a degenerate
    // surface (a widget test harness whose top padding is as tall as the
    // window, a zero-size view mid-teardown), and ConstrainedBox asserts on a
    // negative maxHeight. Falling back to unbounded restores exactly the
    // pre-cap behaviour instead of collapsing the sheet to nothing.
    final rawMaxHeight = mq.size.height - mq.padding.top - LiquidGlass.radiusSheet;
    final maxHeight = rawMaxHeight > 0 ? rawMaxHeight : double.infinity;

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

    // ALWAYS a Padding, even at zero inset. This used to be
    // `keyboardInset > 0 ? Padding(...) : body`, which changed the child's
    // widget TYPE the instant the keyboard began to open. `Widget.canUpdate`
    // compares runtimeType, so Flutter deactivated the entire sheet subtree
    // and inflated a fresh one — disposing every State below it, including
    // each AfosTextField's FocusNode and every TextEditingController in the
    // form. The focused node died mid-animation, the engine hid the keyboard
    // again, and typed text was wiped. That is why the New Course Offering
    // search "wouldn't open the keyboard": it opened and was torn down.
    //
    // Keeping one stable Padding (animated, so the lift still eases in)
    // preserves element identity across the whole keyboard transition.
    final lifted = AnimatedPadding(
      duration: LiquidGlass.motionStandard,
      curve: LiquidGlass.motionCurve,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        // Above `body`, so the SafeArea inside it reads the corrected inset.
        child: MediaQuery(
          data: mq.copyWith(padding: mq.padding.copyWith(bottom: deviceBottom)),
          child: body,
        ),
      ),
    );

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
///
/// Deliberately left on the SHELL navigator (`useRootNavigator` defaults to
/// false). Pushing sheets on the root navigator would put them above the
/// floating nav bar, which is visually nicer — but `Navigator.pop(context)`
/// with a *screen* context (how roughly 50 call sites across 18 files close
/// their sheets) would then resolve to the shell navigator and pop the whole
/// SCREEN instead of the sheet. AppShell already strips the keyboard inset and
/// collapses the nav clearance while typing, so the dead-space and
/// double-lift problems that motivated the change are solved without it.
Future<T?> showGlassSheet<T>(
  BuildContext context, {
  required Widget child,
  bool isScrollControlled = true,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(20, 0, 20, 24),
}) =>
    _countedSheet(() => showModalBottomSheet<T>(
          context: context,
          isScrollControlled: isScrollControlled,
          backgroundColor: Colors.transparent,
          builder: (_) => GlassSheet(padding: padding, child: child),
        ));

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
    _countedSheet(() => showModalBottomSheet<T>(
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
        ));
