import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  // Lifted a step from near-black -- the previous values (#060D1F down to
  // #111827) sat close enough to pure black that several feature accent
  // colors lost visible separation from their own background, reading as
  // "too dark to make things out" rather than a deliberate dark theme. Kept
  // the same relative ordering (background < surface < card < cardHover)
  // so every screen's existing layering still reads correctly, just softer.
  static const Color background    = Color(0xFF0B1220);
  static const Color surface       = Color(0xFF121B2E);
  static const Color card          = Color(0xFF182236);
  static const Color cardHover     = Color(0xFF1D2A42);
  static const Color border        = Color(0xFF283A54);
  static const Color borderLight   = Color(0xFF34496A);
  // Recalibrated from the original fully-saturated "neon sign" set
  // (#1E6FFF, #FFD700, #00D084...) to muted jewel tones -- Material's own
  // dark-theme guidance specifically recommends desaturating colors placed
  // on dark surfaces (a saturated hue at full strength against near-black
  // produces much more simultaneous-contrast glare than the same hue does
  // on a light surface), which is exactly the "too funky, hurts my eyes in
  // a dark room" symptom being fixed here. Kept the same hue identity per
  // color (blue is still recognizably blue) so nothing keyed off "the blue
  // one" / "the gold one" elsewhere in the app needs to change.
  static const Color blue          = Color(0xFF3E6FE0);
  static const Color blueLight     = Color(0xFF6F94EE);
  static const Color gold          = Color(0xFFD4AF37);
  static const Color green         = Color(0xFF2FA876);
  static const Color red           = Color(0xFFD9576D);
  static const Color amber         = Color(0xFFD68A34);
  static const Color purple        = Color(0xFF7C6FD1);
  static const Color teal          = Color(0xFF2E9CB0);
  static const Color coral         = Color(0xFFD97690);
  static const Color pink          = Color(0xFFC65C93);
  static const Color indigo        = Color(0xFF5B5FCF);
  static const Color orange        = Color(0xFFD97A3D);
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
    colors: [Color(0xFF0B1220), Color(0xFF13284A)]);
  static const LinearGradient blueGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [blue, Color(0xFF2C4FAE)]);
  static const LinearGradient goldGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [gold, amber]);
  static const LinearGradient cardGlass = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0x14FFFFFF), Color(0x05FFFFFF)]);
  // Clubs' flat AppColors.pink fill (a fully-saturated magenta) read as
  // harsh/gaudy on large areas (the club-card banner, the Join button) --
  // pairing it toward violet gives the same accent family the rest of the
  // app's gradients use, without touching the many small icon/border
  // accents elsewhere that were fine at full saturation.
  static const LinearGradient pinkGradient = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [pink, Color(0xFFA84A78)]);

  // Was hardcoding its own duplicate hex value per module instead of
  // referencing the constants above -- silently drifted out of sync the
  // moment those constants were recalibrated, so every module icon on the
  // Dashboard kept showing the old fully-saturated color even after this
  // whole pass.
  static const Map<String, Color> moduleColors = {
    'schedule': blue, 'hall': amber,
    'transport': teal, 'payment': gold,
    'library': purple, 'lost_found': coral,
    'clubs': pink, 'mentorship': blueLight,
    'exam_seat': orange, 'dept_chat': indigo,
    'vr_id': green, 'notices': red,
  };

  // --- Holographic accent set (sci-fi glass signature) ---
  static const Color holoBlue   = blue;
  static const Color holoviolet = purple;
  static const Color holoTeal   = teal;

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
