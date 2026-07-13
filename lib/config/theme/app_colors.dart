import 'package:flutter/material.dart';
import 'liquid_glass_tokens.dart';

/// Liquid Glass palette. Member NAMES are frozen API — 1,500+ call sites
/// reference them — so the re-theme moves VALUES only. Several names are now
/// historical ("gold", "pink", "coral"): the Liquid Glass spec caps
/// decorative accents at two hues (brand teal #3ECF8E + brand blue), so
/// every legacy decorative hue folds into a teal/blue-family tint. Three
/// exceptions are semantic, not decorative, and keep their hue identity:
///   red   — errors/destructive actions
///   amber — warnings/pending states (and the folded "orange")
///   purple/holoviolet — the super-admin/oversight signal, one muted violet
/// Do not reintroduce rainbow accents through new constants.
class AppColors {
  AppColors._();

  // Canvas/depth ladder (dark). Ordering background < surface < card <
  // cardHover is load-bearing for every screen's layering.
  static const Color background    = LiquidGlass.canvasDark; // #0B1120
  static const Color surface       = Color(0xFF101A2D);
  static const Color card          = Color(0xFF152238);
  static const Color cardHover     = Color(0xFF1B2B46);
  static const Color border        = Color(0xFF25384F);
  static const Color borderLight   = Color(0xFF32506E);

  // Capped accent duo (+ tonal family).
  static const Color blue          = Color(0xFF4AA3E8);
  static const Color blueLight     = LiquidGlass.accentBlueLight; // #5AB8FF
  static const Color green         = LiquidGlass.accentTeal;      // #3ECF8E — brand primary, doubles as success
  static const Color teal          = Color(0xFF35B8C8); // cyan bridge between the duo
  static const Color indigo        = Color(0xFF3D7BC8); // deep blue (name legacy)
  static const Color gold          = Color(0xFF6FC3E8); // folded to soft sky (name legacy)
  static const Color coral         = Color(0xFF62B8E0); // folded to muted sky (name legacy)
  static const Color pink          = Color(0xFF4FC9B0); // folded to teal tint (name legacy)
  static const Color orange        = Color(0xFF2FA394); // folded to deep teal (name legacy)

  // Semantic status — keep their hues, tuned to sit on glass.
  static const Color red           = Color(0xFFE25C74);
  static const Color amber         = Color(0xFFE0A83C);

  // Functional role signal: super-admin/oversight violet. Decoration must
  // never use this — it is how admin tooling stays recognizable at a glance.
  static const Color purple        = Color(0xFF8B7CD8);

  static const Color textPrimary   = Color(0xFFEAF0F8);
  static const Color textSecondary = Color(0xFF9DB2C9); // 8:1-class contrast on surface, keep AA
  static const Color textMuted     = Color(0xFF7E93AB);

  static const Color lightBg       = LiquidGlass.canvasLight; // #F4F6FB
  static const Color lightCard     = Color(0xFFFFFFFF);
  static const Color lightBorder   = Color(0xFFD3DFEC); // blue-tinted hairline
  static const Color lightText     = Color(0xFF0E1729);
  static const Color lightMuted    = Color(0xFF4A5D74);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF0B1120), Color(0xFF0F2440)]);
  static const LinearGradient blueGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [blue, LiquidGlass.accentBlueDeep]);
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [gold, blueLight]);
  static const LinearGradient cardGlass = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0x14FFFFFF), Color(0x05FFFFFF)]);
  static const LinearGradient pinkGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [pink, orange]);

  // Module identity is now tonal (teal↔blue steps), not rainbow — modules
  // differentiate by icon + label + lightness, which is the deliberate
  // Liquid Glass look, not a regression.
  static const Map<String, Color> moduleColors = {
    'schedule': blue, 'hall': green,
    'transport': teal, 'payment': gold,
    'library': indigo, 'lost_found': coral,
    'clubs': pink, 'mentorship': blueLight,
    'exam_seat': orange, 'dept_chat': indigo,
    'vr_id': green, 'notices': red,
  };

  // --- Liquid Glass accent trio (glass border/glow signature) ---
  // holoviolet keeps the violet ONLY because it is the admin signal; the
  // general-purpose glass gradient below deliberately excludes it.
  static const Color holoBlue   = blueLight;
  static const Color holoviolet = purple;
  static const Color holoTeal   = green;

  static const LinearGradient holoGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [holoBlue, teal, holoTeal],
  );

  static Color glowBlue(double opacity)   => holoBlue.withValues(alpha: opacity);
  static Color glowPurple(double opacity) => holoviolet.withValues(alpha: opacity);
  static Color glowTeal(double opacity)   => holoTeal.withValues(alpha: opacity);

  // --- Theme-aware helpers: use these instead of raw hex so light/dark both read correctly ---
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color textPrimaryOf(BuildContext context) =>
      isDark(context) ? textPrimary : lightText;
  static Color textSecondaryOf(BuildContext context) =>
      isDark(context) ? textSecondary : lightMuted;
  static Color textMutedOf(BuildContext context) =>
      isDark(context) ? textMuted : lightMuted.withValues(alpha: 0.7);
  static Color surfaceOf(BuildContext context) =>
      isDark(context) ? surface : lightCard;
  static Color borderOf(BuildContext context) =>
      isDark(context) ? border : lightBorder;

  /// Liquid glass fill — translucent white over the dark canvas; light mode
  /// needs a much stronger white so the frost reads against near-white.
  static Color glassFill(BuildContext context) => isDark(context)
      ? LiquidGlass.glassFillDark
      : LiquidGlass.glassFillLight;

  /// Tinted glass border (teal in dark, deep blue in light) — the Liquid
  /// Glass spec never uses grey borders on glass.
  static Color glassBorder(BuildContext context) => isDark(context)
      ? LiquidGlass.glassBorderDark
      : LiquidGlass.glassBorderLight;
}
