import 'package:flutter/material.dart';
import 'liquid_glass_tokens.dart';

/// Liquid page transition: a quiet crossfade with a slight scale settle.
/// The spec's full blur-ramp variant was deliberately toned down — a
/// whole-screen BackdropFilter per navigation is the exact rendering cost
/// class behind this app's past jank complaints. Honors reduced motion by
/// rendering the incoming page plainly.
class LiquidPageTransitionsBuilder extends PageTransitionsBuilder {
  const LiquidPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.of(context).disableAnimations) return child;
    final curved = CurvedAnimation(parent: animation, curve: LiquidGlass.motionCurve);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: LiquidGlass.entranceScaleFrom, end: 1.0).animate(curved),
        child: child,
      ),
    );
  }
}

/// Theme-resolved Liquid Glass values. Widgets read this via
/// `LiquidGlassTheme.of(context)` instead of branching on brightness
/// themselves, so the light/dark variants stay defined in exactly one place
/// (here) and both ThemeData builders just register the right instance.
class LiquidGlassTheme extends ThemeExtension<LiquidGlassTheme> {
  final Color canvas;
  final Color glassFill;
  final Color glassBorder;
  final Color ambientShadow;
  final Color accent;
  final Color accentSecondary;

  const LiquidGlassTheme({
    required this.canvas,
    required this.glassFill,
    required this.glassBorder,
    required this.ambientShadow,
    required this.accent,
    required this.accentSecondary,
  });

  static const dark = LiquidGlassTheme(
    canvas: LiquidGlass.canvasDark,
    glassFill: LiquidGlass.glassFillDark,
    glassBorder: LiquidGlass.glassBorderDark,
    ambientShadow: LiquidGlass.ambientShadowDark,
    accent: LiquidGlass.accentTeal,
    accentSecondary: LiquidGlass.accentBlueLight,
  );

  static const light = LiquidGlassTheme(
    canvas: LiquidGlass.canvasLight,
    glassFill: LiquidGlass.glassFillLight,
    glassBorder: LiquidGlass.glassBorderLight,
    ambientShadow: LiquidGlass.ambientShadowLight,
    accent: LiquidGlass.accentTeal,
    accentSecondary: LiquidGlass.accentBlueDeep,
  );

  /// Falls back to brightness-matched defaults so a context outside the
  /// app's own ThemeData (tests, isolated dialogs) still renders sanely.
  static LiquidGlassTheme of(BuildContext context) =>
      Theme.of(context).extension<LiquidGlassTheme>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  /// Ambient tinted glow — glass never casts a black drop shadow.
  List<BoxShadow> ambientGlow({double strength = 1}) => [
        BoxShadow(
          color: ambientShadow.withValues(alpha: (ambientShadow.a * strength).clamp(0, 1)),
          blurRadius: 40,
          offset: const Offset(0, 12),
        ),
      ];

  @override
  LiquidGlassTheme copyWith({
    Color? canvas,
    Color? glassFill,
    Color? glassBorder,
    Color? ambientShadow,
    Color? accent,
    Color? accentSecondary,
  }) =>
      LiquidGlassTheme(
        canvas: canvas ?? this.canvas,
        glassFill: glassFill ?? this.glassFill,
        glassBorder: glassBorder ?? this.glassBorder,
        ambientShadow: ambientShadow ?? this.ambientShadow,
        accent: accent ?? this.accent,
        accentSecondary: accentSecondary ?? this.accentSecondary,
      );

  @override
  LiquidGlassTheme lerp(ThemeExtension<LiquidGlassTheme>? other, double t) {
    if (other is! LiquidGlassTheme) return this;
    return LiquidGlassTheme(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      ambientShadow: Color.lerp(ambientShadow, other.ambientShadow, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSecondary: Color.lerp(accentSecondary, other.accentSecondary, t)!,
    );
  }
}
