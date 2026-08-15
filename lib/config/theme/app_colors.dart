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

  // --- The metal ramp (Design Constitution, Law 2) -------------------------
  //
  // WHY A RAMP AND NOT A GRADIENT PAIR. "Metallic" is not two colours blended
  // evenly — that is plastic. Metal is a **specular response**: a dark body, a
  // narrow bright band where the surface normal points at the light, a warmer
  // bounce on the opposite edge, and a hard edge line. The band being NARROW
  // and OFF-CENTRE is the whole effect; a symmetric two-stop gradient is the
  // banned "fake metal" the constitution names by name.
  //
  // These four are consumed by [AppDepth.metal], which places them at stops
  // 0 / 42 / 46 / 100 — a 4% highlight band, biased toward the light at
  // top-left. Derived from the app's own canvas rather than from neutral greys,
  // so the metal reads as the same material as the rest of AFOS rather than as
  // a chrome sticker dropped onto it.

  /// The unlit body of the metal.
  static const Color metalBase      = Color(0xFF16233A);

  /// The specular band. Deliberately only a few percent of the sweep wide.
  static const Color metalHighlight = Color(0xFF5E7CA8);

  /// The side turned away from the light.
  static const Color metalShadow    = Color(0xFF0A1120);

  /// The hard 1px terminator at the lit edge. Metal has an *edge*, not a fade —
  /// this is what stops the surface looking like painted card.
  static const Color metalEdge      = Color(0xFF8FB4DC);

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

  // --- Auth surfaces --------------------------------------------------------
  //
  // The signed-out screens (login, register, complete-profile) paint their own
  // canvas rather than the app's, because there is no shell behind them yet.
  // These stops lived as raw hex in `login_screen.dart` and
  // `auth_brand_panel.dart`, which share the first stop and drifted apart in
  // the rest.
  //
  // RESOLVED 2026-08-15 — [authDeep] WAS #0B1220, one hex digit from the app's
  // declared dark canvas #0B1120. It was carried forward unchanged for four
  // phases because snapping it is a visible change to every signed-out screen
  // and the chat 'midnight' background, and that needed a decision plus a
  // device. Both now exist: the owner chose to snap them.
  //
  // So this is no longer an independent colour — it IS the canvas, and it says
  // so by construction rather than by repeating the literal. Two names for one
  // value is how they drifted apart in the first place.
  static const Color authDeep = LiquidGlass.canvasDark;

  /// Login / register page background. Theme-aware.
  static const List<Color> authCanvasDark = [
    authDeep, Color(0xFF102035), Color(0xFF121B2E),
  ];
  static const List<Color> authCanvasLight = [
    Color(0xFFF0F4FF), Color(0xFFFFFFFF), Color(0xFFE8EEFC),
  ];

  /// The wide-viewport brand panel beside the auth form. Deliberately dark in
  /// BOTH themes — it is a marketing surface, not a content surface, so it does
  /// not invert with the rest of the app.
  static const List<Color> authBrandDark = [
    authDeep, Color(0xFF16233D), Color(0xFF0F1B30),
  ];
  static const List<Color> authBrandLight = [
    Color(0xFF0F1B30), Color(0xFF1B2E52), Color(0xFF16233D),
  ];

  /// Hairline grid behind the auth form.
  static const Color authGridDark = Color(0xFF1A2840);
  static const Color authGridLight = Color(0xFF0A1628);

  // --- Splash -------------------------------------------------------------
  // The one screen that paints before any theme applies, so its colours are
  // absolute rather than theme-aware. They were raw hex in splash_screen.dart.

  /// The white flash at the peak of the hand-off punch. Warm-tinted, not pure
  /// white, so it reads as light rather than as a missing frame.
  static const Color splashSheen = Color(0xFFEAFFF6);

  /// Ambient corner glows behind the lockup — brand teal and brand blue, each
  /// fading to fully transparent.
  static const List<Color> splashGlowTeal = [Color(0x1A3ECF8E), Color(0x003ECF8E)];
  static const List<Color> splashGlowBlue = [Color(0x1A5AB8FF), Color(0x005AB8FF)];

  /// The four chat-room canvases a user can pick in Settings → Chat Background.
  ///
  /// WHY THIS IS HERE. These four values previously existed as raw hex in TWO
  /// places — `settings_screen.dart` (which offers the swatches) and
  /// `dept_chat_screen.dart` (which paints the chosen one) — with no link
  /// between them. Editing one and not the other would have made the swatch a
  /// lie: you would pick a colour and get a different one. They are also the
  /// only surface colours in the app the USER chooses, so they cannot be
  /// theme-aware helpers; the key is persisted in `user_settings.chat_background`
  /// and the value must resolve identically on both screens.
  ///
  /// `transparent` is deliberate for 'default': it means "no override", and
  /// both call sites fall back to the scaffold background when they see it.
  static const Map<String, Color> chatBackgrounds = {
    'default': Colors.transparent,
    // Snapped to the app canvas with [authDeep], 2026-08-15 — 'midnight' was
    // the third copy of the #0B1220 near-miss, so picking it gave you a chat
    // background one hex digit off the canvas behind every other screen.
    'midnight': authDeep,
    'forest': Color(0xFF0E1F16),
    'plum': Color(0xFF1F0E1B),
  };

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

  /// The user's chosen accent colour — Settings → Appearance → Accent.
  ///
  /// WHY THIS EXISTS. The accent picker was fully wired and had no effect that
  /// anyone could see. `SetAccentColor` saves to Hive AND to
  /// `user_settings.accent_color`, `_loadSaved` reads it back, and main.dart
  /// hands it to `buildLightTheme(accent:)` / `buildDarkTheme(accent:)`, which
  /// puts it on `ColorScheme.primary`. All of that works.
  ///
  /// Nothing read it. There were **zero** references to `colorScheme` anywhere
  /// under `lib/features`, against 2051 hardcoded `AppColors.*` constants — so
  /// the only things that changed colour were the handful Material styles
  /// implicitly, and the feature looked broken because in every place a user
  /// actually looks, it was.
  ///
  /// USE THIS FOR BRAND, NOT FOR MEANING. A primary action, a selected tab, an
  /// active indicator, a focus ring — those are the app expressing its accent
  /// and should follow the user's choice. [red] for destructive, [green] for
  /// success and [amber] for pending are carrying INFORMATION; if those track
  /// the accent then a "Remove student" button turns teal and the colour stops
  /// telling the truth. Leave them alone.
  static Color accentOf(BuildContext context) =>
      Theme.of(context).colorScheme.primary;

  /// Readable foreground for [accentOf], chosen by luminance rather than
  /// assuming white — several pickable accents (teal, amber) are light enough
  /// that white text on them fails contrast. Mirrors the `onPrimary` logic in
  /// dark_theme.dart/light_theme.dart so a call site cannot disagree with the
  /// theme about it.
  static Color onAccentOf(BuildContext context) =>
      Theme.of(context).colorScheme.onPrimary;

  /// The dark ink used on a light-coloured surface.
  ///
  /// WHY THIS IS A TOKEN. `afos_button` and `glass_chip` each ran the same
  /// luminance test (`> 0.45 ? dark : white`) to pick a foreground — and each
  /// used a DIFFERENT dark: `#072A1C` in the button, `#0B1220` in the chip.
  /// Two answers to one question, neither of them named. They are now one
  /// value behind one helper.
  static const Color inkOnLight = Color(0xFF072A1C);

  /// Readable foreground for an ARBITRARY background colour.
  ///
  /// Distinct from [onAccentOf], which answers for the THEME's accent by
  /// reading `colorScheme.onPrimary`. This one answers for a colour handed in
  /// at the call site — a button tinted to its module's hue, a chip carrying a
  /// status colour — where the theme has no opinion.
  static Color foregroundOn(Color background) =>
      background.computeLuminance() > 0.45 ? inkOnLight : Colors.white;

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
