# AFOS — Project Constitution

Read this file at the start of every session. It is what stops session 8 from
contradicting session 1.

## Stack
Flutter (Dart, package `afos_v7`), Supabase (Postgres + Auth + Realtime + Storage).
Ships as: Android APK + web (Vercel). iOS/macOS/linux/windows folders exist but
see PLATFORM REALITY below before claiming any of them work.

## PROJECT REALITY (measured 2026-08-15 — do not guess these numbers)
- 188 Dart files, 43,355 LOC in `lib/`, 62 routes, 62 `*_screen.dart` files.
- 13 repository files exposing 53 public methods — BUT **33 of the 62 screens
  query Supabase directly** (`SupabaseConfig.client.from(...)`) instead of going
  through a repository. The data contract is therefore much wider than the
  repository layer, and "presentation-only" changes must respect inline queries
  too.
- 87 TextEditingControllers, 26 shared widgets already exist in
  `lib/shared/widgets/` — a primitive set is PRESENT. Do not build a second one.
- Existing design system is "Liquid Glass": `lib/config/theme/` holds
  `app_colors.dart`, `app_text_styles.dart`, `liquid_glass_tokens.dart`,
  `dark_theme.dart`, `light_theme.dart`. `AppColors.*` has ~2000 call sites.

## PLATFORM REALITY
- **Android**: builds. Primary target.
- **Web**: builds (`flutter build web`), deploys on Vercel. Chrome is NOT on the
  PATH of this machine, so `flutter run -d chrome` fails — use `build web`.
- **Windows/Linux/macOS/iOS: OUT OF SCOPE — decided 2026-08-15.**
  `windows/` is an 18-file bare scaffold and **Visual Studio is not installed**,
  so a Windows build cannot be produced or verified here at all. Several
  dependencies (`mobile_scanner`, `webview_flutter`, `local_auth`,
  `geolocator`) have no Windows support, so the app would not function even if
  it compiled. **Never claim desktop support, and never spend a phase on it.**
  Ship targets are Android APK and web only.

## HARD RULES — violating any of these fails the task
1. NEVER modify database schema, migrations, RLS policies, or auth flow during a
   redesign phase. Needed SQL goes to `/db/proposed/NNN_description.sql`,
   unapplied, and you tell me.
2. NEVER change a repository/service method signature or return type, and never
   change an inline Supabase query's shape. UI adapts to existing data.
3. NEVER touch `.env`, API keys, service role keys, or CI secrets.
   **This repo is PUBLIC** (github.com/rakibhassanrh66/AFOS) — weigh every
   "is this safe to commit" question against that.
4. NEVER delete a file without listing it and receiving explicit approval.
5. NEVER claim something is fixed without running the build/analyze command and
   showing the output.
6. Work only inside the file scope declared for the current phase.
7. If a change would require touching something outside scope, STOP and report.

## DESIGN CONSTITUTION
- Single light source: top-left, 20 degrees. All shadows, highlights, bevels obey it.
- Depth = occlusion + directional shadow + scale. Not blur radius.
- Blur/glass: maximum ONE surface per screen, only for genuinely floating layers.
- Radius scale ONLY: 4 / 10 / 20 / full. Radius encodes elevation class.
- Spacing scale ONLY: 4 / 8 / 12 / 16 / 24 / 32 / 48.
- Type roles: display / body / tabular-numeric. Three faces maximum.
- Colour: defined tokens only. No inline `Color(0x...)` outside the theme file.
- Motion tokens ONLY (`lib/theme/motion.dart` once Phase 1 creates it):
  instant 90 / tight 160 / base 240 / slow 380 / hero 620. Springs, not linear
  curves. Nothing exceeds 620ms.
- Animate on first mount or explicit user action only. Never on rebuild.
- Every interactive element: press-down scale 0.97 within one frame, haptic on
  COMMIT (not on press).
- Respect reduced motion (`MediaQuery.disableAnimationsOf`) everywhere.
- Touch targets >= 48dp. Contrast >= 4.5:1. Responsive down to 320px.
- Skeleton loaders must match final layout geometry exactly (zero layout shift).

### RESOLVED 2026-08-15 — Liquid Glass STAYS
The generic rule "max ONE blur per screen" was raised against this codebase and
**explicitly overruled by the project owner.** Do not re-open it.

Why it was raised: `BackdropFilter` appears 21 times and is stacked in the
SHELL — `app_shell.dart` (2), `slide_menu.dart` (3), `glass_bottom_nav.dart` (3),
`glass_card.dart` (3) — so every screen inherits 2-3 blurs before drawing
anything. Honouring the rule literally meant retiring Liquid Glass, rewriting
26 shared widgets and ~2000 `AppColors` call sites.

**The decision: keep Liquid Glass as the visual language.** The blur rule is
amended to "blur belongs to the SHELL; a content surface does not add another".
What we fix instead is what actually reads as machine-made, all of it measured:
52 emoji toasts, 66 raw `Duration`s, 21 stray hex colours, 3 `HapticFeedback`
calls across 62 screens, zero `EdgeInsetsDirectional`, and near-zero
reduced-motion support. Phase 1 formalises the scales (radius / spacing / motion
/ depth) that the existing tokens imply but never declared.

## BANNED (treat as build errors)
- Purple/blue or teal/indigo gradients as a default surface treatment
- Glassmorphism applied to multiple surfaces on one screen
- Three equal cards in a row with outline icons as filler layout
- Emoji in UI copy or headings
- Symmetric 2-stop gradients faking metal (use asymmetric stops: 0/42/46/100)
- Hardcoded colours, durations, radii, or spacing outside the theme
- Motion added "for polish" with no interaction meaning
- `setState` in build, unbounded ListView, images without `cacheWidth`

## PERFORMANCE BUDGET (hard fail if exceeded)
- Android cold start to first interactive frame: < 1800ms (mid-range device)
- Web FCP < 1800ms, TTI < 2800ms on 4G
- Frame budget: raster < 8ms, UI < 8ms. Zero jank frames on scroll/nav in profile mode.
- APK per-ABI (split-per-abi, release): < 28 MB
- No single new dependency over 2 MB without asking first

## WORKFLOW
- Plan first, wait for approval, then implement. One phase per session, `/clear`
  between phases, one git branch per phase (`redesign/pN-name`). Never commit to
  main without asking.
- Append every change to `REDESIGN_LOG.md`: phase, files, reason, verification.
- Run `flutter analyze` before declaring a phase complete. Zero new warnings.
- Report honestly. If something cannot be done safely, say so.

## PROJECT-SPECIFIC GOTCHAS (learned the hard way — do not rediscover)
- **Flutter binary is `C:\RakibFlutter\bin\flutter.bat`.** Plain `flutter` may
  not resolve.
- **Never bulk-rewrite Dart source with PowerShell** `Get-Content`/`Set-Content`
  — it mojibakes every non-ASCII char and adds a BOM while `analyze` stays green.
  Use the Edit tool.
- **`flutter build web` never compiles `android/`.** Anything touching native
  Android needs a real `flutter build apk`.
- **Migration filenames must match the remote ledger version**, not local wall
  clock. Apply, then read
  `select version from supabase_migrations.schema_migrations order by version desc limit 1`
  and name the file with that.
- **PostgREST embeds** (`staff(designation)`) may return an object OR a list.
  `UserModel` handles both — copy that pattern.
- **A blank STRING is not null.** `department = ''` defeated `?? 'default'` and
  rendered an empty chip. Normalise to NULL at the boundary.
- **Adding a table column does not add it to a VIEW.** PostgREST then omits it
  and `?? 'default'` hides the omission.
- Test the real widget, never a copy of it — a copied widget cannot regress.
