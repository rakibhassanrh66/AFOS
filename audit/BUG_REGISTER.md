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
| P1-02 | `feedback_screen.dart`, `grades_screen.dart`, `join_requests_screen.dart`, `room_availability_screen.dart` | Controller/subscription leak | The State holds a `TextEditingController` / `ScrollController` / stream but has **no `dispose()` at all**. Verified — these four are the real subset of 24 files that lack dispose; the other 20 hold nothing that needs releasing. | S each |
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
