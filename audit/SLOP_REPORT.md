# SLOP_REPORT — baseline violation count

Measured 2026-08-15 against the BANNED list in `CLAUDE.md`.
This is the number Phase 9 measures against. **Every count is a real grep, not an estimate.**

| # | Violation | Count | Where the weight sits |
|---|---|---:|---|
| 1 | Hardcoded `Color(0x..)` outside the theme | 21 | see breakdown below |
| 2 | Raw `BorderRadius.circular(` outside theme | 292 | radius applied by habit, not as a scale |
| 3 | Raw `Duration(milliseconds:)` outside theme | 66 | no motion token system exists yet |
| 4 | `LinearGradient` uses | 66 | 6 in app_colors, rest scattered |
| 5 | `BackdropFilter` (glass) uses | 21 | STRUCTURAL — see below |
| 6 | Emoji in UI string literals | 53 | mostly trailing check-marks in toasts |

## The finding that matters most: glass is structural, not per-screen

The doctrine allows one blurred surface per screen. AFOS cannot satisfy that by
editing screens, because the blurs are in the **shell**:

| file | BackdropFilter count | inherited by |
|---|---:|---|
| `lib/features/shell/presentation/slide_menu.dart` | 3 | every screen |
| `lib/shared/widgets/glass_bottom_nav.dart` | 3 | every screen with the nav bar |
| `lib/shared/widgets/glass_card.dart` | 3 | every screen using GlassCard |
| `lib/features/shell/presentation/app_shell.dart` | 2 | every screen |
| `lib/shared/widgets/surface_card.dart` | 2 | most screens |

A screen showing one card already renders 2–3 blurs before its own content.
**Honouring "one blur per screen" means retiring Liquid Glass as the app's
visual language** — a product decision, not a refactor. Do not start Phase 1
until that is answered.

## Where the hardcoded colours actually are

```
lib/config/routes/app_router.dart  Color(0xFF0B1220),
lib/config/routes/app_router.dart  Color(0xFFD9576D), size: 48),
lib/features/auth/presentation/login_screen.dart  Color(0xFF121B2E)]
lib/features/auth/presentation/login_screen.dart  Color(0xFFE8EEFC)],
lib/features/auth/presentation/login_screen.dart  Color(0xFF0A1628)).withValues(alpha: isDark ? 1 : 0.05)
lib/features/auth/presentation/widgets/auth_brand_panel.dart  Color(0xFF0F1B30)]
lib/features/auth/presentation/widgets/auth_brand_panel.dart  Color(0xFF16233D)],
lib/features/auth/presentation/widgets/auth_brand_panel.dart  Color(0xFF0B1220),
lib/features/dept_chat/presentation/dept_chat_screen.dart  Color(0xFF0B1220),
lib/features/dept_chat/presentation/dept_chat_screen.dart  Color(0xFF0E1F16),
lib/features/dept_chat/presentation/dept_chat_screen.dart  Color(0xFF1F0E1B),
lib/features/settings/presentation/settings_screen.dart  Color(0xFF0B1220),
lib/features/settings/presentation/settings_screen.dart  Color(0xFF0E1F16),
lib/features/settings/presentation/settings_screen.dart  Color(0xFF1F0E1B),
lib/features/shell/presentation/slide_menu.dart  Color(0xFF60A5FA)),
lib/features/splash/presentation/splash_screen.dart  Color(0xFFEAFFF6)),
lib/features/splash/presentation/splash_screen.dart  Color(0x003ECF8E)]))),
lib/features/splash/presentation/splash_screen.dart  Color(0x005AB8FF)]))),
lib/features/transport/presentation/transport_screen.dart  Color(0x593ECF8E); // teal @ ~0.35, connector
lib/shared/widgets/afos_button.dart  Color(0xFF072A1C) : Colors.white;
lib/shared/widgets/glass_chip.dart  Color(0xFF0B1220) : Colors.white)
```

## Honest caveats on these numbers

- `BorderRadius.circular(` at 292 is inflated as a "violation": many calls pass
  a token (`LiquidGlass.signatureRadius(16)`). The real violation is the
  **absence of a radius scale**, not each call site. Phase 1 must define the
  scale before Phase 2 can judge which calls are wrong.
- Spacing was measured at 1,249 EdgeInsets values off the 4/8/12/16/24/32/48
  scale, but that regex counts every numeric argument including `0.5` opacity-ish
  values and multi-arg `fromLTRB`. Treat it as "spacing is unsystematised",
  not as 1,249 discrete defects.
- Emoji: all sampled instances are a trailing `✓` in success toasts
  (`'Membership approved ✓'`). Low severity, trivially fixed, but it is exactly
  the chatbot-voice tell the doctrine names.
