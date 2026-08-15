import 'dart:ui';
import 'package:flutter/material.dart';
import 'motion.dart';

/// Liquid Glass design tokens — the single source of numeric truth for the
/// translucent depth system (blur strengths, radii, tints, motion timings).
///
/// Two deliberate identity rules live here and must not drift:
///  1. The signature silhouette: every glass panel rounds three corners at
///     the large radius and cuts ONE corner (top-right) to [radiusCut] — a
///     small consistent quirk that keeps the look recognizably AFOS instead
///     of a generic symmetric glassmorphism template.
///  2. Accents are capped at two hues (brand teal + brand blue). Red/amber
///     remain purely as status colors, and one muted violet survives solely
///     as the super-admin/oversight signal — those are semantics, not
///     decoration, and don't count against the cap.
class LiquidGlass {
  LiquidGlass._();

  // --- Capped accent duo ---
  static const Color accentTeal = Color(0xFF3ECF8E);
  static const Color accentBlueLight = Color(0xFF5AB8FF); // dark-mode secondary
  static const Color accentBlueDeep = Color(0xFF02569B); // light-mode secondary

  // --- Canvas ---
  static const Color canvasDark = Color(0xFF0B1120);
  static const Color canvasLight = Color(0xFFF4F6FB);

  // --- Glass fills ---
  // Kept intentionally low so the BackdropFilter blur genuinely shows through
  // (a translucent frosted panel, not a flat solid block). Dark canvas needs
  // only a whisper of white; light canvas needs a bit more to read against
  // near-white, but well below the old near-opaque 55%.
  static const Color glassFillDark = Color(0x14FFFFFF); // white ~8%
  static const Color glassFillLight = Color(0x40FFFFFF); // white ~25%

  // --- Glass borders (tinted, not grey) ---
  static const Color glassBorderDark = Color(0x333ECF8E); // teal 20%
  static const Color glassBorderLight = Color(0x2E02569B); // deep blue 18%

  // --- Ambient shadows: glass casts tinted glow, never black drop shadow ---
  static const Color ambientShadowDark = Color(0x333ECF8E);
  static const Color ambientShadowLight = Color(0x2902569B);

  // --- Blur sigmas per depth tier ---
  // Base stays cheap enough for list rows; floating is reserved for modals /
  // sheets / the VR-ID card where a heavy BackdropFilter is a one-off, not a
  // per-row cost (this app has a real jank history around app-wide blur).
  static const double blurBase = 10;
  static const double blurRaised = 18;
  static const double blurFloating = 24;
  static const double saturationBoost = 1.6;

  // --- Radii (single source of truth for the whole app) ---
  static const double radiusCard = 22;
  static const double radiusCut = 8; // the signature corner
  static const double radiusSheet = 28;
  static const double radiusControl = 14;
  static const double radiusPill = 999; // fully-rounded chips/pills

  // --- Glossy sheen ("wet glass" top highlight) ---
  // A thin white gradient painted over the fill, inside the clip, so the
  // surface reads as light catching glass rather than a flat translucent box.
  static const Color glossHighlightDark = Color(0x1FFFFFFF); // white ~12%
  static const Color glossHighlightLight = Color(0x40FFFFFF); // white ~25%

  /// Diagonal top-left → transparent sheen overlay for glass surfaces.
  static LinearGradient sheen({required bool isDark}) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          isDark ? glossHighlightDark : glossHighlightLight,
          const Color(0x00FFFFFF),
          const Color(0x00FFFFFF),
        ],
        stops: const [0.0, 0.42, 1.0],
      );

  /// A crisp 1px inner top highlight line (the lit rim of the glass).
  static Color rimHighlight(bool isDark) =>
      isDark ? const Color(0x1FFFFFFF) : const Color(0x59FFFFFF);

  // --- Motion: ALIASES ONTO AppMotion, which is now the source of truth ---
  //
  // These names stay because ~60 call sites use them and churning those is not
  // what Phase 1 is for. What changed is that they no longer DEFINE anything —
  // each one now points at a rung of the ladder in `motion.dart`, so the app
  // has one motion system instead of two that can drift apart.
  //
  // The re-basing, stated plainly because it is a real (small) change in feel:
  //   motionFast      200ms -> AppMotion.tight   160ms
  //   motionStandard  280ms -> AppMotion.base    240ms
  //   pressDuration   120ms -> AppMotion.instant  90ms
  //   motionCurve / pressScale / entranceScaleFrom: identical values, no change.
  //
  // DELIBERATELY NOT DONE HERE. `motionStandard` is currently used for two
  // different things: small movement (tab indicator, card fades, app-shell
  // chrome) AND large movement (every page route in page_transitions.dart, and
  // glass_sheet). The ladder says those are different rungs — base 240 for the
  // small ones, slow 380 for pages and sheets. Retiming every page transition
  // from 280ms to 380ms makes navigation 36% slower, which is a decision that
  // has to be SEEN on a device, not asserted in a token file. Phase 4
  // (interaction physics) moves page routes and sheets to AppMotion.slow after
  // it can be felt. Until then they follow base, exactly as they do today.
  //
  // New code should import AppMotion directly and, critically, read durations
  // through `AppMotion.durationOf(context, …)` so reduced-motion works.
  static const Curve motionCurve = AppMotion.standard;
  static const Duration motionFast = AppMotion.tight;
  static const Duration motionStandard = AppMotion.base;
  static const Duration pressDuration = AppMotion.pressDuration;
  static const Duration entranceDuration = motionFast;
  static const double pressScale = AppMotion.pressScale;
  // Standardized entrance scale-from for page/sheet/card entrances.
  static const double entranceScaleFrom = AppMotion.entranceScaleFrom;

  /// The signature AFOS silhouette: three corners large, top-right cut
  /// tight. Radii at or below the cut stay symmetric (chips, tiny tiles).
  static BorderRadius signatureRadius(double radius) {
    if (radius <= radiusCut) return BorderRadius.circular(radius);
    return BorderRadius.only(
      topLeft: Radius.circular(radius),
      topRight: const Radius.circular(radiusCut),
      bottomLeft: Radius.circular(radius),
      bottomRight: Radius.circular(radius),
    );
  }

  /// blur + saturate(160%) — saturation keeps content behind the glass
  /// looking liquid instead of washed grey. ColorFilter composes as the
  /// inner filter so the saturation applies to the already-blurred backdrop.
  static ImageFilter frost(double sigma) => ImageFilter.compose(
        outer: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        inner: const ColorFilter.matrix(<double>[
          // Rec.709 luminance-weighted saturation matrix, s = 1.6
          // (each row sums to 1.0 so greys pass through unchanged).
          1.47244, -0.42912, -0.04332, 0, 0,
          -0.12756, 1.17088, -0.04332, 0, 0,
          -0.12756, -0.42912, 1.55668, 0, 0,
          0, 0, 0, 1, 0,
        ]),
      );
}
