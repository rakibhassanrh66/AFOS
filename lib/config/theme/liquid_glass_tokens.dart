import 'dart:ui';
import 'package:flutter/material.dart';

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
  static const Color glassFillDark = Color(0x0FFFFFFF); // white 6%
  static const Color glassFillLight = Color(0x8CFFFFFF); // white 55%

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

  // --- Radii ---
  static const double radiusCard = 22;
  static const double radiusCut = 8; // the signature corner
  static const double radiusSheet = 28;
  static const double radiusControl = 14;

  // --- Motion ---
  static const Duration pressDuration = Duration(milliseconds: 120);
  static const Duration entranceDuration = Duration(milliseconds: 200);
  static const double pressScale = 0.97;
  static const double entranceScaleFrom = 0.96;

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
