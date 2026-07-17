import 'liquid_glass_tokens.dart';

/// Unified spacing scale — the single source for gaps/padding across the app.
/// (Radius now lives in one place too: [AppRadius] aliases the [LiquidGlass]
/// tokens so there is exactly one radius vocabulary, not two competing ones.)
class AppSpacing {
  AppSpacing._();
  static const double xs  = 4;  static const double sm  = 8;
  static const double md  = 16; static const double lg  = 24;
  static const double xl  = 32; static const double xxl = 48;
}

/// Radius vocabulary — thin semantic aliases over [LiquidGlass] so the glass
/// tokens remain the single numeric source of truth. Use these names in
/// widget code; they always resolve to the Liquid Glass ladder.
class AppRadius {
  AppRadius._();
  static const double tight   = LiquidGlass.radiusCut;      // 8  — tiny tiles / the signature cut
  static const double control = LiquidGlass.radiusControl;  // 14 — buttons, inputs, small chips
  static const double card    = LiquidGlass.radiusCard;     // 22 — cards, panels, headers
  static const double sheet   = LiquidGlass.radiusSheet;    // 28 — bottom sheets
  static const double pill    = LiquidGlass.radiusPill;     // 999 — fully-rounded chips/pills
}
