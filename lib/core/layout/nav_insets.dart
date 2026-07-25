import 'package:flutter/widgets.dart';

/// The single supported way a screen asks for floating-bottom-nav clearance.
///
/// WHY THIS EXISTS. There used to be two mechanisms for the same job: the
/// shell injected a MediaQuery bottom inset (`AppShell.build`), and screens
/// *also* hard-coded `+ GlassBottomNav.navContentClearance` into their scroll
/// padding. Both were live and additive, so ~55 screens reserved the bar's
/// height twice — ending content 145-219px above a 129px bar. That left
/// nothing behind the glass, and a `BackdropFilter` with nothing behind it to
/// blur renders as a flat opaque slab instead of frosted glass. Dashboard
/// looked correct only because it happened to hard-code nothing.
///
/// So the constant is gone and this is the only entry point. It reads the
/// inset the shell injected, which means it is automatically:
///   * 0 on auth routes and the splash screen (outside the ShellRoute),
///   * 0 on the web desktop nav rail (no floating bar there),
///   * 0 while the keyboard is open (the bar is behind the IME),
///   * and inclusive of the device's own gesture-bar inset.
///
/// A screen that passes `padding: null` to a ListView/GridView needs none of
/// this — `BoxScrollView` adopts MediaQuery's vertical padding on its own.
/// This is for the screens that set their own scroll padding, which by doing
/// so opt out of that automatic behaviour.
abstract final class NavInsets {
  const NavInsets._();

  /// Clearance the floating nav needs below this screen's content, in logical
  /// pixels, already including the device's bottom safe area.
  static double of(BuildContext context) => MediaQuery.paddingOf(context).bottom;

  /// Extra room a screen with a [FloatingActionButton] needs so its last row
  /// isn't left permanently under the button. Scaffold already lifts the FAB
  /// itself by the shell's inset, so this only covers the button's own height
  /// plus a gap — the Material-recommended ~76px, not a per-screen guess.
  static const double fabClearance = 76;

  /// Scroll padding that keeps the last item reachable above the bar while
  /// still letting content scroll *under* the frost on the way there.
  ///
  /// [bottom] is the gap you want between the last item and the bar — the
  /// bar's own height is added on top of it, so callers never restate it.
  /// Pass `fab: true` on screens with a floating action button.
  static EdgeInsets content(
    BuildContext context, {
    double h = 16,
    double top = 16,
    double bottom = 16,
    bool fab = false,
  }) =>
      EdgeInsets.fromLTRB(
          h, top, h, bottom + of(context) + (fab ? fabClearance : 0));

  /// Same clearance as an inset-only value, for callers that already have an
  /// [EdgeInsets] to merge with (or that pad a non-scrolling widget pinned to
  /// the bottom of the screen).
  static EdgeInsets only(BuildContext context, {double extra = 0}) =>
      EdgeInsets.only(bottom: of(context) + extra);
}
