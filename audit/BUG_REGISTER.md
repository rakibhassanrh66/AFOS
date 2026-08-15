# BUG_REGISTER — AFOS

Static analysis pass, 2026-08-15. 62 screens, 188 Dart files, 43,355 LOC.

**Baseline:** `flutter analyze` = **0 issues**, 282 tests pass. So none of the
below is caught by the compiler or the current suite — that is precisely why the
register exists.

**Honesty note on method.** Everything here is static analysis. Where a count is
a heuristic that will contain false positives, it says so and gives the reason.
Nothing is reported as confirmed unless it was verified by reading the code.

---

## P1 — visible defect or crash path

| ID | File:line | Symptom | Suspected cause | Effort |
|---|---|---|---|---|
| P1-01 | 20 sites, listed below | `setState() called after dispose` exception | `setState` runs after an `await` with no `mounted` guard. If the user leaves the screen while the await is in flight, Flutter throws. | S each |
| P1-02 | ~~4 files~~ — **see correction below** | Controller leak | Originally recorded as "the State holds a controller but has no `dispose()`". That diagnosis was wrong in shape and partly wrong in fact. **Corrected 2026-08-15 (Phase 2 batch 9).** | S each |

### CORRECTION to P1-02 — recorded 2026-08-15, Phase 2 batch 9

The Phase 0 pass keyed on "file has a controller AND no `dispose()` override"
and drew the wrong conclusion from it. Re-verified against the source:

**None of the four names a State-level controller.** In every case the
controller is a **local**, created inside a method that opens a dialog or
sheet — so a `dispose()` override was never the fix, and its absence was not
the defect. The real leak is one controller per dialog *open*, which a user can
repeat many times in a session.

| file | actual finding | status |
|---|---|---|
| `room_availability_screen.dart` | Real. Local `purposeCtrl`, never released. | **Fixed, batch 3** |
| `feedback_screen.dart` | Real, and the worst of them: `_showSubmitSheet` was `void`, did not await the modal, and leaked **two** controllers per open. | **Fixed, batch 9** |
| `join_requests_screen.dart` | **False positive.** Its local `reasonCtrl` is already disposed in a `finally`. | No action |
| `grades_screen.dart` | **False positive.** `_askReason` already calls `ctrl.dispose()`. | No action |

Two of the four were real, both are now fixed, and the group is closed. The
lesson for the remaining register entries: *"no `dispose()` override" is not
evidence of a leak* — it is only a prompt to go and read the file. Two further
leaks of the identical local-controller shape were found this way in files the
register never flagged (`lost_found_screen.dart` batch 3,
`hall_screen.dart` batch 5), which is the same defect the heuristic was aimed at
and missed.
| P1-03 | 18 of 62 screens | Layout jumps when data arrives | No loading skeleton, so the screen renders at one geometry then re-renders at another. Violates the zero-layout-shift rule. | M |
| P1-04 | 28 of 62 screens | Empty result reads as "app is broken" | No empty state. A user with no clubs / no results / no notifications sees blank space with no explanation and no call to action. | M |

**P1-01 confirmed sites** (`setState` after `await`, no `mounted` in scope):

```
admin/manage_course_offerings_admin_screen.dart:215, :269
conference_room/conference_room_screen.dart:168, :174, :199
exam_seat/manage_exam_seats_screen.dart:42
grades/grades_screen.dart:486
grades/marks_entry_screen.dart:178
lost_found/lost_found_screen.dart:327
portal/diu_portal_screen.dart:145
schedule/admin_upload_routine_screen.dart:133, :161
schedule/join_requests_screen.dart:258
schedule/module_leader_screen.dart:215
sos/sos_alert_detail_screen.dart:129
sos/sos_floating_button.dart:231
transport/transport_import_preview_screen.dart:68
shared/widgets/avatar_picker.dart:29
```

Two of the 20 (`join_requests_screen.dart:393`, `manage_course_offerings_screen.dart:292`)
are callback bodies rather than post-await code — **false positives, do not
"fix" them.** The remaining 18 are real.

---

## P2 — robustness, accessibility, architecture

| ID | Scope | Symptom | Cause | Effort |
|---|---|---|---|---|
| P2-01 | Whole app | **No RTL support anywhere.** | `EdgeInsetsDirectional` is used **0 times** across 188 files; everything uses left/right padding. Bengali is LTR so this is latent, but the doctrine requires it and it is cheap now, expensive later. | L |
| P2-02 | Whole app | Reduced-motion mostly ignored | Only **9** references to `disableAnimations` in the entire codebase, against ~66 hardcoded animation durations. Users who set "reduce motion" still get most animations. Accessibility defect. | M |
| P2-03 | Whole app | Almost no tactile feedback | **3** `HapticFeedback` calls across 62 screens. The doctrine requires haptic on commit for every interactive element. | M |
| P2-04 | 33 of 62 screens | Data contract is undocumented and fragile | Screens call `SupabaseConfig.client.from(...)` inline instead of via a repository. A "presentation-only" refactor can silently break a query, and RLS-dependent calls are the ones that fail quietly. See `CONTRACT_MAP.md` Part B. | XL |
| P2-05 | 5 sites | Nested scroll cost | `shrinkWrap: true` in `notification_popover.dart:246`, `transport_import_preview_screen.dart:452`, `transport_screen.dart:250`, `offline_banner.dart:125`, `shimmer_card.dart:48`. Forces full-list layout. Acceptable for short lists; confirm each is bounded. | S |
| P2-06 | 6 sites | Avoidable image memory | `CachedNetworkImage` without `memCacheWidth`/`memCacheHeight` in `library_screen.dart:466`, `lost_found_screen.dart:264`, `slide_menu.dart:740`, `vr_id_screen.dart:171`. Full-resolution decode for a thumbnail. | S |

---

## P3 — quality floor / doctrine violations

| ID | Count | Symptom | Effort |
|---|---:|---|---|
| P3-01 | 52 | Emoji in UI copy — all sampled are a trailing `✓` in success toasts (`'Membership approved ✓'`). The chatbot-voice tell. | S |
| P3-02 | 66 | Raw `Duration(milliseconds:)` outside the theme — no motion token system exists yet. Phase 1 creates it; this is the migration backlog. | M |
| P3-03 | 21 | Hardcoded `Color(0x..)` outside `lib/config/theme/`. | S |
| P3-04 | 292 / ~1249 | No radius scale and no spacing scale. **Counts are inflated** — many `BorderRadius.circular()` calls already pass a token, and the spacing regex counts every numeric argument. Read as "unsystematised", not as N discrete defects. | L |

---

## Platform findings (not bugs — constraints)

| Finding | Detail |
|---|---|
| **Windows desktop cannot be built or verified here** | Visual Studio is not installed (`flutter doctor`: "Visual Studio not installed"). `windows/` is an 18-file bare scaffold. `mobile_scanner`, `webview_flutter`, `local_auth` and `geolocator` have no Windows support, so the app would not function even if it compiled. **Scoped out** by decision on 2026-08-15: Android + web only. |
| Chrome not on PATH | `flutter run -d chrome` fails on this machine. `flutter build web` works — use that. |
| iOS / macOS / linux | Scaffolds present, never built, no signing set up. Same treatment as Windows: out of scope. |

---

## What this register deliberately does NOT claim

- It does not list runtime bugs. No device run, profile-mode trace, or manual
  walkthrough was performed in Phase 0 — that is Phase 7 (performance) and
  Phase 8 (parity). Anything only visible at runtime is absent by design.
- The "7 screens with no states at all" figure from the raw scan is **not**
  included as a defect: those are `forgot_password`, `reset_password`,
  `unlock`, `pending_approval`, `splash`, `payment_webview` and
  `diu_portal_hub` — forms and static hubs that legitimately have no data
  states to render.
- Nothing here was fixed. Phase 0 writes documentation only.

## Totals

**4 P1 groups (22 concrete sites) · 6 P2 · 4 P3.**

---

# RUNTIME FINDINGS — added 2026-08-15 (Phase 8, device pass)

The register above states plainly that it "does not list runtime bugs... no
device run, profile-mode trace, or manual walkthrough was performed." This
section is that gap being closed. Device: **motorola edge 60 pro, Android 16,
wireless ADB**, running a profile build of this branch.

## R1 — P0. `flutter build apk --release` FAILS. No release could be built at all.

```
android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java:84:
  error: package dev.flutter.plugins.integration_test does not exist
```

`integration_test` is a **dev_dependency**. Release builds exclude dev
dependencies' native plugins, but the generated registrant on disk was stale and
still registered `IntegrationTestPlugin`, so `assembleRelease` failed at javac.

**Why nothing caught it.** This is the CLAUDE.md gotcha in its purest form —
*`flutter build web` never compiles `android/`*. Web built green through twelve
redesign batches, `flutter analyze` was 0, 310 tests passed, and the app could
not have been shipped. The only thing that surfaces it is a real
`flutter build apk`.

**Fix:** deleted the stale generated file (gitignored build artifact, backed up
first) and let the tool regenerate it. Release then built.

**Worth automating:** a CI job that runs `flutter build apk --release`, since
nothing else in the loop touches Gradle.

## R2 — P1. APK per-ABI is OVER the performance budget.

| ABI | size | budget | over by |
|---|---:|---:|---:|
| `armeabi-v7a` | 31.4 MB | 28 MB | **+3.4 MB** |
| `arm64-v8a` | 34.6 MB | 28 MB | **+6.6 MB** |
| `x86_64` | 37.0 MB | 28 MB | **+9.0 MB** |

Split-per-abi release, tree-shaking on (icons reduced 97–99%). `arm64-v8a` is
the one that matters for real devices and it is **24% over**.

The budget is not adjusted to fit the measurement. Reducing this means looking
at dependencies — the app carries `mobile_scanner`, `webview_flutter`,
`geolocator`, `record`, `audioplayers`, OneSignal and a passkeys stack — which is
a dependency-audit phase, not a redesign one.

## R3 — P2. Web FCP/TTI cannot meet the budget, and the reason is arithmetic.

Critical-path payload, gzipped, measured from `build/web`:

| file | raw | gzip |
|---|---:|---:|
| `main.dart.js` | 5.58 MB | **1.64 MB** |
| `canvaskit.wasm` | 6.89 MB | **2.77 MB** |
| `canvaskit/chromium/canvaskit.wasm` | 5.49 MB | 2.08 MB |

That is **~3.7–4.4 MB before first paint**. The budget is FCP < 1800 ms on 4G.
No 4G connection delivers 4 MB in 1.8 s, so the budget is missed by construction,
independent of any code in `lib/`.

**Not verified in a browser, and that is a limitation, not a claim:** Chrome is
not on PATH on this machine (already documented), Playwright's Chrome is not
installed, and the browser extension is not connected. The payload numbers are
real; the resulting FCP is inferred from them.

The lever is the renderer (CanvasKit vs the lighter path) and deferred wasm
loading — a rendering decision with visual consequences, so it is flagged, not
taken.

## R4 — P3. The 404 page's button ran edge-to-edge. **Fixed.**

Found by deep-linking a route that does not exist. The app theme sets a button
`minimumSize` of `Size(double.infinity, 52)`, so the unconstrained
`ElevatedButton` in `errorBuilder` spanned the full screen width and touched
both bezels. Nothing overflowed, so no test could see it. Now inset 32.

## What the device pass CONFIRMED working

| | result |
|---|---|
| Cold start to first frame rasterized | **664 ms** (budget < 1800 ms) — `timeToFirstFrame` 499 ms, framework init 271 ms |
| `am start -W` TotalTime, cold, 3 runs | 1065 / 1049 / 1027 ms |
| Reduced motion skips the splash arc | **Confirmed.** At 1.6 s with animations on the splash is still mid-wipe; with `transition_animation_scale=0` the app is already past it. |
| `EmptyState` on device (VR-ID access log) | Renders correctly, and the AFOS top-right corner cut is visible on the icon badge |
| Card-tier signature radius | Visible on My Results' CGPA card and course cards |
| Themed 404 | Now takes the app canvas instead of a hardcoded dark slab |
| Screens walked without error | dashboard, browse courses, clubs, lost & found, transport, hall, payment, VR-ID (3 tabs), results, assignments, my attendance, slide menu, login |

**Note on the measurement:** `animator_duration_scale` is NOT what Flutter reads
for `MediaQuery.disableAnimations` on Android — it reads
`transition_animation_scale`. Testing the wrong one showed a false failure. All
three scales were restored to 1 afterwards.

## Not covered

Roles other than `student` and `super_admin`; the teacher/admin-only screens
(marks entry, attendance register, module leader, join requests, the manage_*
admin screens) were not walked with a role that can reach them.
