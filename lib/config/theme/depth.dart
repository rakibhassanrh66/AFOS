import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'liquid_glass_tokens.dart';

/// One light source for the whole app, expressed as an elevation system.
///
/// THE PROBLEM THIS SOLVES. Shadows in this codebase were written per widget:
/// `BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18,
/// offset: const Offset(0, 6))` in one file, `blurRadius: 8, offset: Offset(0, 3)`
/// in the next, `Offset(0, 2)` in a third. Every one of them drops the shadow
/// straight DOWN. A scene lit from directly overhead has no direction, so
/// nothing reads as sitting *above* anything else — it reads as a sticker with
/// a smudge under it. Depth came out as blur radius, which is exactly the
/// "fake depth" the design constitution bans.
///
/// THE RULE. The light is at **top-left, 20° above the horizon**, for every
/// surface, on every screen, forever. Three consequences, all encoded below:
///
///  1. Shadows fall DOWN AND TO THE RIGHT. The horizontal offset is what sells
///     the light direction; a purely vertical offset is what makes UI look flat.
///  2. The top-left edge of a raised surface catches a 1px highlight — the lit
///     rim. Without it a card has a shadow but no lit side, which the eye reads
///     as a hole rather than a raised panel.
///  3. Higher elevation means a longer, softer, *fainter* shadow — not a darker
///     one. Doubling opacity to suggest height is what produces muddy UI.
///
/// Radius is part of the same system: a surface's corner radius states which
/// elevation class it belongs to, so a level-1 chip and a level-3 sheet are
/// never rounded the same. The radii map onto the existing
/// [LiquidGlass] values so the AFOS signature silhouette is preserved.
class AppDepth {
  AppDepth._();

  /// Where the light is. Kept as real numbers rather than magic offsets so the
  /// derivation below can be read and checked.
  static const double lightAzimuthDegrees = 315; // top-left
  static const double lightAltitudeDegrees = 20;

  /// The horizontal bias applied per unit of elevation, derived from the
  /// azimuth. Lower than the vertical component because a 20° light throws a
  /// shadow mostly downward on a screen-facing plane; enough to be read as
  /// directional, not so much that surfaces look like they are sliding.
  static const double _dx = 0.4;
  static const double _dy = 1.0;

  /// Shadow for elevation [level] (0–4).
  ///
  /// Level 0 is flush with its parent and casts nothing — returning an empty
  /// list rather than a zero-opacity shadow matters, because Flutter still
  /// composites a transparent shadow layer.
  static List<BoxShadow> shadow(int level, {required bool isDark}) {
    if (level <= 0) return const [];
    final l = level.clamp(1, 4);

    // Height above the surface below, in logical pixels.
    const heights = <int, double>{1: 2, 2: 5, 3: 12, 4: 22};
    final h = heights[l]!;

    // Softness grows faster than height: a distant surface has a diffuse edge.
    final blur = h * 2.2 + 4;

    // Opacity FALLS as the surface rises. A high surface is further from what
    // it shades, so its shadow is more spread and less dense.
    final opacity = (isDark ? 0.44 : 0.16) * (1 - (l - 1) * 0.13);

    return [
      // The cast shadow, offset along the light direction.
      BoxShadow(
        color: (isDark ? Colors.black : const Color(0xFF0F1B30))
            .withValues(alpha: opacity),
        blurRadius: blur,
        offset: Offset(h * _dx, h * _dy),
      ),
      // AFOS keeps a brand-tinted ambient bloom under raised glass — this is
      // the app's own signature and predates this file. Retained, but now
      // strictly secondary to the directional shadow above, and only from
      // level 2 up so list rows do not glow.
      if (l >= 2)
        BoxShadow(
          color: (isDark
                  ? LiquidGlass.ambientShadowDark
                  : LiquidGlass.ambientShadowLight)
              .withValues(alpha: isDark ? 0.16 : 0.10),
          blurRadius: blur * 1.6,
          spreadRadius: 1,
          offset: Offset(h * _dx * 0.5, h * _dy * 0.5),
        ),
    ];
  }

  /// The lit rim: a hairline highlight on the edge FACING the light
  /// (top-left). Pair this with [shadow] — a raised surface needs both, or it
  /// reads as a cut-out rather than a panel.
  static Border rim(BuildContext context, {int level = 1}) {
    final isDark = AppColors.isDark(context);
    if (level <= 0) {
      return Border.all(color: AppColors.borderOf(context), width: 0.6);
    }
    return Border(
      top: BorderSide(color: LiquidGlass.rimHighlight(isDark), width: 1),
      left: BorderSide(
          color: LiquidGlass.rimHighlight(isDark).withValues(alpha: 0.6),
          width: 1),
      right: BorderSide(color: AppColors.borderOf(context), width: 0.6),
      bottom: BorderSide(color: AppColors.borderOf(context), width: 0.6),
    );
  }

  /// The corner radius that BELONGS to an elevation level.
  ///
  /// Radius is not a taste setting. A flush row, a raised card and a floating
  /// sheet are three different distances from the user, and the radius says
  /// which one you are looking at. These route through
  /// [LiquidGlass.signatureRadius] so the top-right corner cut — the AFOS
  /// silhouette — survives.
  static BorderRadius radius(int level) => switch (level.clamp(0, 4)) {
        0 => BorderRadius.circular(LiquidGlass.radiusCut),        //  8  flush
        1 => LiquidGlass.signatureRadius(LiquidGlass.radiusControl), // 14 control
        2 => LiquidGlass.signatureRadius(LiquidGlass.radiusCard),    // 22 card
        3 => LiquidGlass.signatureRadius(LiquidGlass.radiusSheet),   // 28 sheet
        _ => LiquidGlass.signatureRadius(LiquidGlass.radiusSheet),
      };

  /// Everything a raised surface needs, in one call, consistent with the light.
  static BoxDecoration surface(
    BuildContext context, {
    int level = 2,
    Color? color,
  }) {
    final isDark = AppColors.isDark(context);
    return BoxDecoration(
      color: color ?? AppColors.surfaceOf(context),
      borderRadius: radius(level),
      border: rim(context, level: level),
      boxShadow: shadow(level, isDark: isDark),
    );
  }
}
