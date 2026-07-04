import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const Color background    = Color(0xFF060D1F);
  static const Color surface       = Color(0xFF0C1526);
  static const Color card          = Color(0xFF111827);
  static const Color cardHover     = Color(0xFF162035);
  static const Color border        = Color(0xFF1E2D42);
  static const Color borderLight   = Color(0xFF2A3F5A);
  static const Color blue          = Color(0xFF1E6FFF);
  static const Color blueLight     = Color(0xFF5294FF);
  static const Color gold          = Color(0xFFFFD700);
  static const Color green         = Color(0xFF00D084);
  static const Color red           = Color(0xFFFF4D6A);
  static const Color amber         = Color(0xFFFF9D00);
  static const Color purple        = Color(0xFF8B5CF6);
  static const Color teal          = Color(0xFF06B6D4);
  static const Color coral         = Color(0xFFFF6B8A);
  static const Color pink          = Color(0xFFEC4899);
  static const Color indigo        = Color(0xFF6366F1);
  static const Color orange        = Color(0xFFF97316);
  // textSecondary/textMuted were previously #6B7E99 (4.4:1 contrast against
  // the dark surface — just under the 4.5:1 WCAG AA minimum for normal
  // text) and #3D5070 (2.24:1 — badly failing). Brightened to comfortably
  // clear AA (8.1:1 / 5.7:1 respectively) while keeping the secondary <
  // muted-tier hierarchy (muted stays dimmer than secondary).
  static const Color textPrimary   = Color(0xFFE8EDF5);
  static const Color textSecondary = Color(0xFF9BAEC7);
  static const Color textMuted     = Color(0xFF7E92AC);
  static const Color lightBg       = Color(0xFFF0F4FF);
  static const Color lightCard     = Color(0xFFFFFFFF);
  static const Color lightBorder   = Color(0xFFD1DCF0);
  static const Color lightText     = Color(0xFF0A1628);
  static const Color lightMuted    = Color(0xFF4B5E75);

  static const LinearGradient heroGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF060D1F), Color(0xFF0D1E3A)]);
  static const LinearGradient blueGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF1E6FFF), Color(0xFF1455CC)]);
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFFFFD700), Color(0xFFFF9D00)]);
  static const LinearGradient cardGlass = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0x14FFFFFF), Color(0x05FFFFFF)]);

  static const Map<String, Color> moduleColors = {
    'schedule': Color(0xFF1E6FFF), 'hall': Color(0xFFFF9D00),
    'transport': Color(0xFF06B6D4), 'payment': Color(0xFFFFD700),
    'library': Color(0xFF8B5CF6), 'lost_found': Color(0xFFFF6B8A),
    'clubs': Color(0xFFEC4899), 'mentorship': Color(0xFF60A5FA),
    'exam_seat': Color(0xFFF97316), 'dept_chat': Color(0xFF6366F1),
    'vr_id': Color(0xFF00D084), 'notices': Color(0xFFFF4D6A),
  };

  // --- Holographic accent set (sci-fi glass signature) ---
  static const Color holoBlue   = Color(0xFF1E6FFF);
  static const Color holoviolet = Color(0xFF8B5CF6);
  static const Color holoTeal   = Color(0xFF06B6D4);

  static const LinearGradient holoGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [holoBlue, holoviolet, holoTeal],
  );

  static Color glowBlue(double opacity)   => holoBlue.withOpacity(opacity);
  static Color glowPurple(double opacity) => holoviolet.withOpacity(opacity);
  static Color glowTeal(double opacity)   => holoTeal.withOpacity(opacity);

  // --- Theme-aware helpers: use these instead of raw hex so light/dark both read correctly ---
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color textPrimaryOf(BuildContext context) =>
      isDark(context) ? textPrimary : lightText;
  static Color textSecondaryOf(BuildContext context) =>
      isDark(context) ? textSecondary : lightMuted;
  static Color textMutedOf(BuildContext context) =>
      isDark(context) ? textMuted : lightMuted.withOpacity(0.7);
  static Color surfaceOf(BuildContext context) =>
      isDark(context) ? surface : lightCard;
  static Color borderOf(BuildContext context) =>
      isDark(context) ? border : lightBorder;

  /// Frosted glass fill — light, translucent white in dark mode; translucent
  /// white-on-white reads as near-solid in light mode, so light mode uses a
  /// darker-tinted translucent fill instead to keep the frosted contrast.
  static Color glassFill(BuildContext context) => isDark(context)
      ? Colors.white.withOpacity(0.06)
      : Colors.white.withOpacity(0.55);

  static Color glassBorder(BuildContext context) => isDark(context)
      ? Colors.white.withOpacity(0.14)
      : const Color(0xFF0A1628).withOpacity(0.08);
}
