# AFOS fix-pass report — branch `afos/fix-pass`

Base: `d4c66df` (local main, 1.1.1+10). Version bumped to **1.1.2+11** (unreleased).
Commits, one per phase: `2a24b8c` (P1) → `aeeaa6f` (P2) → `95db4ad` (P2 follow-up) → `e90b26d` (P4).
Phase 3 produced no commit by design (flag only, see below). All claims below were
verified against the live Supabase project / a real test run, not inferred from reading code.

## Phase 1 — dead code (`2a24b8c`)

Removed: `shared/presentation/placeholder_screen.dart` (0 refs), `flutter_riverpod`
(declared, never imported), `lottie` package + 3 of 4 bundled JSON assets (0 Dart call
sites). Kept `assets/lottie/success.json` for a future success animation — **note: it is
an empty-layers stub and needs a real animation file before any use**.

Dead-end inventory (reported, not deleted):
- No `TODO`/`FIXME`/`HACK`/stub markers in `lib/` (matches were `toDouble` false positives).
- No `onPressed: null` dead buttons; every `app_router.dart` route is reachable; every
  slide-menu item lands on a screen with real content.
- **One real dead end: `lib/features/academic/`** — `MarksRepository`,
  `GradeChangeRepository` (marks_entry) and `TranscriptGenerator` (results) have zero
  references anywhere in `lib/`, `test/`, `integration_test/`, `tool/`; not even DI
  registration. Backing DB tables (`marks`, `grade_change_requests`) exist and are
  RLS-covered. Decision needed: delete, or keep as scaffolding for a marks-entry feature.

## Phase 2 — known bugs (`aeeaa6f`, follow-up `95db4ad`)

- **Login regression**: login/forgot-password used a stricter email regex than
  registration; plus-addressed emails (real admin/super_admin QA accounts) were rejected
  as "Invalid email". Split shape-only login validators from the registration
  (domain+complexity) validator. Verified by live sign-in on web.
- **The reported yellow/black overflow was two distinct bugs**:
  1. `ShimmerList` was a rigid Column that overflowed any bounded parent (e.g. a
     TabBarView tab: ~243px). Now a clipping shrink-wrapped ListView.
  2. A residual "10px on /home" every role: the dashboard module grid derived tile height
     from width (`childAspectRatio: 1.1`) while tile content is a constant ~122px —
     narrow layouts or taller fallback font metrics (runtime Google-Fonts fetch failing)
     under-provide. Now a fixed `mainAxisExtent` scaled by the user's text size.
     Found only this session: the overnight verification run's **exit code was 0 while
     its log said "Some tests failed"** — the result was never read before the session
     died. Do not trust this suite's exit code alone.
- **Test harness fix** (`integration_test/overflow_smoke_test.dart`): `takeException()`
  attributed errors thrown during post-login dashboard layout to whichever route polled
  first and dropped the culprit-widget info. Harness now taps `FlutterError.onError`
  across the whole role walk, tags each error with its phase, and keeps the "relevant
  error-causing widget" file:line block. It also now fails on login-phase layout errors
  it previously swallowed.
- Silent `catch {}` in hall / manage-users / notification-center / notification-tray load
  paths now surface `ErrorView`/`friendlyError` with Retry instead of fake empty states.
- Light mode visually verified for the first time — screenshots across all 5 roles'
  dashboards, no contrast/overflow issues found.
- `configureDependencies()` made idempotent (GetIt double-registration crash blocked the
  integration suite). App version now read from `PackageInfo` at boot (was a hardcoded,
  stale `1.0.0` constant).

## Phase 3 — UI consistency (no commit; flag for decision)

`AppSpacing`/`AppRadius` tokens (4/8/16/24/32/48) have **zero references in the entire
codebase**, while the app's real spacing scale is fine-grained (12, 10, 6, 20, 14
dominate — 129/57/54/52/45 uses). A mechanical token sweep would either leave the
majority untokenized (no consistency gained) or shift layout by inventing mappings —
forbidden by the pass's own guardrail. The app is already visually consistent (checked
across 9 screenshots). Decision needed: re-base the token classes on the real scale, or
delete them as dead weight.

## Phase 4 — security re-audit (`e90b26d`)

Fixed in code:
- `payment_webview_screen` injected the live Supabase JWT + user id into
  `window.afosToken` on **every** `onPageFinished`, with no origin check and no
  navigation delegate — any off-origin redirect would hand the session token to another
  site. Now: navigation blocked to any host other than the trusted payment host, and the
  token only injected when the finished page's origin is that host.
- `parse-routine` edge function had no size bound (role + extension were already checked
  server-side): now 15 MB cap on Excel, 20 000-line cap on extracted-PDF JSON, both 413.
  **Not yet live — requires** `supabase functions deploy parse-routine --project-ref dtsptjallznnvattadlu`.

Verified clean against the live DB (queried, not assumed):
- 71/71 public tables have RLS enabled; the 7 zero-policy tables are exactly the known
  intentional deny-all set; all 25 SECURITY DEFINER functions have pinned `search_path`.
- `user_locations` (most sensitive table) readable only by self + admin/super_admin/staff.
- No forbidden role vocabulary in policies; no service-role or OneSignal key patterns
  anywhere in the tree **or full git history**.
- Exam-seat PDF parsing is entirely client-side (no edge function); its real server
  boundary is RLS on the write path — there is no unvalidated server upload to harden.
- FK deletion rules on the newer tables (sos_alerts, sos_responses, user_locations,
  staff, feedback, payment_records) follow the established cascade/set-null split.
- `flutter pub outdated`: no pub.dev security advisories on any dependency. Transitive
  `js` package is discontinued (harmless). Staleness worth a separate planned upgrade:
  syncfusion_flutter_pdf 27→34, go_router 14→17, flutter_bloc 8→9, flutter_map 7→8.

**Flagged — needs a migration, deliberately not applied in this pass:**
1. **CRITICAL — signup role escalation.** `handle_new_user()` copies
   `raw_user_meta_data->>'account_type'` verbatim into `profiles.role`/`role_id` via a
   `roles` lookup. Signup metadata is fully client-controlled, so a crafted signup with
   `account_type: 'super_admin'` (with an allowed email domain) creates a real
   super_admin. Compounding it, **zero RLS policies reference `is_verified`** — the
   pending-approval gate exists only in the Flutter router. Fix: whitelist
   self-assignable roles in `handle_new_user()` (student/teacher/staff) and add
   verification gating to sensitive policies.
2. Auth rate limiting is a Supabase dashboard setting (Auth → Rate Limits), not code —
   was not verifiable from this machine; confirm limits are non-default there.

## Baseline vs final

| Check | Baseline (at `d4c66df`) | Final (`95db4ad`) |
|---|---|---|
| `flutter analyze` | 94 issues, all info-level (lib) | 91 issues, all info-level (lib + integration_test) |
| Test suite | only a placeholder widget test existed; overflow suite blocked by GetIt crash | placeholder passes; full 5-role overflow suite (~90 route visits) passes under the stricter harness |
| `supabase db diff` | not runnable on this machine (needs Docker Desktop, absent) | same; substituted: migration list Local=Remote in sync, no schema changes made by this pass |

## Handed to the user / open decisions

- Deploy: `supabase functions deploy parse-routine --project-ref dtsptjallznnvattadlu`
- Push (user always pushes): `afos/fix-pass` has no upstream; local `main` is 1 commit
  ahead of `origin/main` (`d4c66df`).
- Decide: signup-escalation migration (item 1 above — recommend doing this first),
  `lib/features/academic/` dead folder, AppSpacing/AppRadius token fate.
