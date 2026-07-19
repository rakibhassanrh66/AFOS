# AFOS — Project Status (living file)

> Session-continuity log. Updated continuously, after every meaningful chunk of work — not just at session end. A fresh Claude Code session with no prior context should be able to read this and know exactly what's done, what's mid-flight, and what remains. Convert relative dates to absolute.

**Last updated:** 2026-07-19
**Current version:** **2.3.0+19** — code on branch `fixround-nav-glass-transport-admin` (not yet committed/pushed; user pushes).
**Branch:** `fixround-nav-glass-transport-admin` off `main` (`48dcd0f`).
**DB state (checked live):** one NEW migration this round — `20260719160000_transport_stop_offsets.sql` — **already applied to production** via the Supabase MCP and verified: 8 columns, RLS on, 2 policies, in `supabase_realtime`, 0 rows. RLS was proven by a **role-simulated probe in a rolled-back transaction**: student can read ✓ / student cannot write ✗ / admin can write ✓, no probe rows left behind. Everything older (SOS-gate `app_config`, delegated-admin RBAC) was already live.
**Outstanding to go fully live:** on-device tactile checks only. `flutter analyze lib` clean, **54/54 tests pass**, `flutter build web` ✓, `flutter build apk --debug` ✓.
**Platform note:** Windows host, no Xcode (iOS can't be built here). A motorola edge 60 pro (Android 16 / API 36) is connected wirelessly for on-device checks.

---

## This round — 2.3.0+19 (planet nav, per-stop bus times, header, splash)

Continuation of the 2.2.0+18 round after a usage-limit cutoff. `flutter analyze lib` clean, **54/54 tests** (up from 29), web + debug APK both green.

| # | Item | Status |
|---|------|--------|
| 1 | **Planet navbar** rebuilt to the user's reference geometry (bar 75, planet 50, lift −24, corner 35, valley 55/42) | ✅ |
| 2 | Valley path **self-intersection bug** at the first/last tab fixed + locked by tests | ✅ |
| 3 | Nav **glass restored** (`ClipPath` + `BackdropFilter` on the same valley path); `drawShadow` → real `MaskFilter` glow | ✅ |
| 4 | **Slide menu now moves the nav indicator** (`context.push` → `context.go`) | ✅ |
| 5 | Back-button collateral bug (offered app-exit instead of popping) fixed | ✅ |
| 6 | **Radial burst logout menu** replacing both stock `AlertDialog`s | ✅ |
| 7 | **Per-stop bus times**: new table + admin entry screen + honest rider-facing answer | ✅ |
| 8 | Upload Schedule given the canonical `AfosAppBar` + `FeatureHeader` | ✅ |
| 9 | Splash scaled up (dial 200 / AFOS 56px w900) + harder exit (4.5× + roll + flash) | ✅ |

### Root causes found this round (all verified, not guessed)

- **Slide menu didn't move the bottom-nav planet.** `_MenuTile.onTap` used `context.push`. Confirmed against the **actually installed go_router 12.1.3** source (not a remembered version): `RouteMatchList.push` carries the comment *"Imperative route match doesn't change the uri and path parameters"* and `_copyWith` keeps the old `uri`. `app_shell.dart` derives `navIndex` from `matchedLocation`, so it never updated. The desktop rail always used `go` — which is exactly why the rail highlighted correctly and the bottom nav did not. **Fix:** `go` for menu destinations; `navIndex` now also matches sub-routes.
- **Same root cause, second symptom:** `_handleBack` read that stale location *before* checking `canPop()`, so backing out of a pushed screen from `/home` offered to **exit the app** instead of popping. Reordered to ask `canPop()` first — version-agnostic and strictly more correct.
- **Navbar valley folded into the rounded corner.** `_buildPath` clamped the valley's *shoulders* to the corner arc but not its *cubic control points*. On a 360 dp phone Home's control point landed at x ≈ 15.7, left of the corner at 26 → non-monotonic x → the dip bulged into the corner. Home and Settings are the two edge tabs, i.e. the most-used. **Fix:** control points are now fractions of the real shoulder→centre span (0.64 / 0.58 — the reference's exact proportions when unclamped), so a clamped shoulder drags its controls with it. `navValleyXs()` is exposed for testing and asserted non-decreasing across 8 widths × every tab.
- **Per-stop bus times didn't exist — at all.** Not a display bug: `TransportRoute.stops` is `List<String>` persisted as `[{"name": …}]`, and the sheet's two time columns are route-level (`to_dsc_trips` = start time at the route's FIRST stop; `from_dsc_trips` = departure from campus). For R4, "7:00 AM / 10:00 AM" are **ECB Chattor's** departures and Mirpur 10 is the 4th stop, so the requested phrasing was not derivable from any data in the system. `transport_stops.estimated_minutes_from_diu` has existed since `001_init.sql` but **nothing has ever written it**. **Fix:** a new `transport_stop_offsets` table (deliberately NOT the `stops` jsonb, which the importer rewrites on every upload; keyed by route_number/schedule_type/stop_name so timings survive semester rollovers), **two** offsets per stop because the inbound and outbound legs are different durations, an admin entry screen, and a rider-facing card that shows real per-stop times when recorded and otherwise states only what is true ("Mirpur 10 is stop 4 of 9; the bus starts from ECB Chattor at 7:00 AM and 10:00 AM"). `StopTimeCalculator` returns **null**, never zero, for a missing offset — enforced by a dedicated "never fabricates a time" test group.

### Key files touched
`glass_bottom_nav.dart` (rebuilt), `app_shell.dart` (navIndex + back order), `slide_menu.dart` (`go` + radial menu), `settings_screen.dart` (radial menu), **new** `radial_logout_menu.dart`, **new** `stop_time_calculator.dart` / `stop_offsets_repository.dart` / `manage_stop_times_screen.dart`, **new** migration `20260719160000_transport_stop_offsets.sql`, `transport_screen.dart` (stop answer card + admin entry point), `admin_upload_routine_screen.dart` (header), `splash_screen.dart`. **New tests:** `transport_stop_times_test.dart`; `glass_bottom_nav_test.dart` rewritten.

---

## This round — 2.2.0+18 (UI + transport + admin fix-round)

Branch `fixround-nav-glass-transport-admin`. All items below implemented; `flutter analyze lib` clean, **29/29 tests pass** (incl. new R4/R13/R15 enforcement tests), web build in progress.

| # | Item | Status |
|---|------|--------|
| 1 | Bottom nav: revert cut-corner shape → clean rounded floating bar; **raised active disc** (lifts above bar, springs onto the tapped tab) | ✅ |
| 2 | Nav sliding indicator was multi-hue "funky" → **single solid teal** disc; icons single-color, outline→**filled** on select | ✅ |
| 3 | Glass too solid → lowered fill alpha (nav 0.82→0.55, sheet 0.86→0.6, drawer 0.88→0.62, light glass token 55%→25%, dark 6%→8%) so blur shows through | ✅ |
| 4 | Bottom-padding overshoot → trimmed `barSpace` 68+22 → 66+14 | ✅ |
| 5 | Transport parsing (R4/R13/R15) + **enforced tests** | ✅ |
| 6 | Coming-Soon → friendly "Time being updated — check back soon" | ✅ |
| 7 | DSC / Daffodil Smart City normalized in route names + dedup | ✅ |
| 8 | Single-stop → parent-route resolution; Friday schedule surfaced on Fridays | ✅ |
| 9 | Upload notification: now reports the real outcome to the admin | ✅ |
| 10 | Super-admin SOS toggle actually hides/shows the bar (for everyone) | ✅ |
| 11 | **New: super-admin role-change UI** (Manage Users → user → Change role) | ✅ |
| 12 | Splash: dramatic letter-by-letter logo punch-in + huge exit pop | ✅ |

### What was wrong before vs. what's different now (the repeat items)

- **Transport parsing (was "fixed" before, still wrong):** the parser already handled the malformed time forms (`4.20.00 PM` etc.) — those were never the bug. The real defect, found by dumping the raw fixture cells: route **R4**'s `6:10 PM` cell is `"6:10 PM\nWill go upto Mirpur-1,10&Pallabi   (Only 1 Bus Assigned For ECB)"`. The internal `\n` made `parseTripColumn` split the time from its note, then `parseTrip` **dropped** the non-parenthetical text and left an **orphan time-less trip** → R4 showed 4 from-DSC entries instead of 3, with the note detached. **Fix (`transport_time_parser.dart`):** (a) `parseTrip` now keeps descriptive text beside a time as part of the note (`_combineNote`); (b) `parseTripColumn` merges a note-only continuation line into the preceding trip. R13/R15 were already correct (their notes are verbatim; the missing space in "Mirpur-1only" is a source-sheet typo we don't fabricate over). Also: `_parseStops` now dedups **all** DSC (was consecutive-only). **New `test/transport_routes_spec_test.dart` hardcodes R4/R13/R15's exact expected stops/times/notes and passes.**
- **Upload notification (reported broken before too):** re-traced the full pipeline. The edge function **does** insert `user_notifications` rows and returns `{inAppInserted, insertError, pushError}` — but `NotificationService.broadcast` **discarded that result**, so the admin got a "routes imported" message with zero delivery signal; a silent push/insert failure looked like "nothing happened." **Fix:** `broadcast` now returns the result, and `_importTransport` appends the real outcome ("🔔 N users notified" / a specific ⚠ failure). `inAppInserted` is the definitive "row created in DB" confirmation, now surfaced. Root cause was **observability**, not a missing notify call (that was fixed last round).
- **SOS super-admin toggle (reported invisible):** the migration is actually applied live (see DB state), so the table exists. The real bug: `SosGate` **always** showed the button for super_admin, so flipping the switch appeared to do nothing for the person testing it. **Fix:** the gate now follows `sosEnabled` for everyone (super_admin included) — OFF visibly hides the bar; super_admin keeps the "Manage SOS Alerts" menu entry + the toggle.

### Key files touched
`glass_bottom_nav.dart` (rewritten — raised disc), `app_shell.dart` (padding), `liquid_glass_tokens.dart`/`glass_sheet.dart`/`slide_menu.dart` (glass alpha), `splash_screen.dart` (logo punch-in + bigger exit), `transport_time_parser.dart` + `transport_grid_parser.dart` (parse fixes), `transport_screen.dart` (coming-soon message, DSC display, single-stop, Friday), `notification_service.dart` + `admin_upload_routine_screen.dart` (notify outcome), `sos_floating_button.dart` + `manage_sos_screen.dart` (SOS gate), `manage_users_screen.dart` (role-change UI). New test: `transport_routes_spec_test.dart`.

---

## Shipped and live (recent history)
- **2.0.2+16** — modern transport DETAIL UI (route timeline, time-pill schedules, live next-bus hero). Pushed.
- **2.0.1+15** — transport upload dept-scoping, Google-Sheets `.xlsx` parse fallback (`spreadsheet_decoder`), fingerprint-in-password-field login, splash camera-punch, 90Hz (`flutter_displaymode`), Android `compileSdk 36` for app + all plugin modules. Pushed.
- Transport v2 schema (`to_dsc_trips`/`from_dsc_trips` etc.) is live on production (applied prior session).

---

## This round (9-item combined fix) — status

| # | Item | Status |
|---|------|--------|
| 1 | Transport screen visual modernization (glass route cards, grouped, motion, map) | ✅ done |
| 2 | Stray `<`/`>` separators leaking into route details | ✅ done |
| 3 | Search doesn't filter live + keyboard flicker | ✅ done |
| 4 | Bottom nav bespoke cut-corner shape | ✅ done |
| 5 | Border/edge misalignment — consolidate onto one shared `SignatureBorder` | ✅ done |
| 6 | Bottom nav covers content (Settings Log Out) — systemic bottom padding | ✅ done |
| 7 | No notification after transport upload | ✅ done |
| 8 | SOS super-admin visibility gate (feature flag) | ✅ done (⚠ needs `supabase db push`) |
| 9 | This PROJECT_STATUS.md (living file) | 🟩 maintained |

**All 9 items implemented; `flutter analyze lib` clean (2 pre-existing infos only). Pending: build/test verification, version bump, commit, push, and the Item-8 migration `supabase db push` (user runs).**

### What's done so far (detail)
- **Item 6:** `app_shell.dart` — routed content now gets central physical bottom padding (`barSpace + safe-area`) replacing the inset-only reservation. Every screen clears the nav.
- **Item 5:** new `lib/shared/widgets/signature_shape.dart` `SignatureBorder` (OutlinedBorder). `glass_card.dart` migrated to it (fill+border+clip from one path — fixes the clipped-hairline artifact). `surface_card.dart`/`notification_popover.dart` still use `LiquidGlass.signatureRadius` (same shape) — consistent; migrate later only if needed.
- **Item 4:** `glass_bottom_nav.dart` — pill replaced with `SignatureBorder(radius: 26)` (bespoke cut-corner slab); spring blob/haptics kept.
- **Item 2:** `transport_grid_parser.dart` `_parseStops` splits on `[<>]+` and strips residual delimiters; `transport_screen.dart` `_cleanStop()` applied at stop-name display sites (fixes existing DB rows too). PDF parser hands off to the grid parser — covered. Regression test green.
- **Item 7:** `admin_upload_routine_screen.dart` `_importTransport` now calls `NotificationService.broadcast(...)` (no filter = all users) after a successful write. Root cause was: the notification was never attempted (not DB, not UI).
- **Item 1:** `transport_screen.dart` `_routeCard` rebuilt on `SurfaceCard` (app glass language, `blur:false` list-safe) with a per-schedule-type accent (`_accentFor`: Regular=teal / Shuttle=blue / Friday=amber) + staggered entrance motion. `_FindRouteTab` already used SurfaceCard; detail sheet/timeline/pills/tabs already modern from 2.0.2.
- **Item 3:** `schedule_screen.dart` search now filters live via a debounced `onChanged` (`_onSearchChanged`, 300ms) + tap-outside-to-dismiss; controllers were already stable (no remount-per-keystroke). `global_search_screen.dart` was already correct.
- **Item 8 (SOS gate):** new `supabase/migrations/20260719120000_app_config_sos_gate.sql` (`app_config.sos_enabled`, RLS select-all / update-super_admin, realtime). New `lib/core/services/app_config_service.dart` (cached `ValueNotifier<bool>` + realtime + `setSosEnabled`, fails closed). `SosGate` in `sos_floating_button.dart` wraps the button (`RoleSession.role=='super_admin' || sosEnabled`); `app_shell.dart` mounts `SosGate`. `slide_menu.dart` filters the `/sos/nearby` item on the same gate + live listener. `manage_sos_screen.dart` has the super-admin Switch. Logout clears via `AppConfigService.reset()` in `bootstrap.dart`. **`supabase db push` required before the gate works live** — until then reads fail closed (SOS hidden for all but super-admin).

### Root causes confirmed (from live code)
- **Item 2:** `transport_grid_parser.dart:174` splits on `RegExp(r'\s*<?>\s*')` — a lone `<` (no `>`) never matches and leaks. Fix split to `[<>]+` and strip residual delimiters; also strip at display time so existing DB rows are covered.
- **Item 3:** `schedule_screen.dart` `_SearchBar` uses `onSubmitted` only (no live `onChanged`). `global_search_screen.dart` is the correct reference (stable controller + debounced onChanged).
- **Item 6:** `app_shell.dart:134` reserves nav space only via a `MediaQuery.padding.bottom` inset; naive screens (`settings_screen.dart:287` fixed `EdgeInsets.all(16)`) ignore it. Fix = central physical bottom padding on shell content.
- **Item 7:** notification is **never attempted** (neither DB nor UI). `_importTransport`/`TransportImportService.write` never call `NotificationService`. Fix = `NotificationService.broadcast(broadcastAll: true, ...)` after a successful write.
- **Item 8:** no existing app-config table; add a minimal `app_config(sos_enabled)` with RLS + realtime, gate `SosFloatingButton` (`app_shell.dart:147`) and the `'Nearby SOS Alerts'` slide-menu item (`slide_menu.dart:73`) on `sos_enabled || isSuperAdmin`; toggle in `manage_sos_screen.dart`.

### Remaining across all prior plans (carried, not part of this round's code)
- On-device confirmation of the biometric OS prompt, splash punch, and 90Hz engagement (needs the phone).
- Item 8 migration requires `supabase db push` (user runs).

---

## How to resume
Work top-to-bottom through the table. After each item: `flutter analyze` clean, then flip its row to ✅ here. At the end: `flutter test`, `flutter build web` + `apk --debug`, bump to 2.1.0+17, commit, push. Hand the user `supabase db push` (Item 8) + optional `gh release`.
