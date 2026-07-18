# AFOS — Project Status (living file)

> Session-continuity log. Updated continuously, after every meaningful chunk of work — not just at session end. A fresh Claude Code session with no prior context should be able to read this and know exactly what's done, what's mid-flight, and what remains. Convert relative dates to absolute.

**Last updated:** 2026-07-19
**Current version:** 2.0.2+16 (shipped) → in progress toward **2.1.0+17**
**Branch:** `main` (origin/main up to date through `7d5d694`). All work this round is on `main` (the previously-named feature branches are already merged in).
**Platform note:** Windows host, no Xcode (iOS can't be built here). A motorola edge 60 pro (Android 16 / API 36) is connected wirelessly for on-device checks.

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
