# PARITY_REPORT — Phase 8

What was checked, how, and — the part that matters — what could not be.

---

## Method, and its limits stated up front

Three passes, of decreasing strength:

1. **On device.** motorola edge 60 pro, Android 16, profile build, signed in as
   a **student** and separately as a **super_admin**. Screens opened and looked
   at.
2. **In the layout harness.** `test/layout_overflow_test.dart` and
   `test/support/layout_probe.dart` drive the real shared widgets at
   **6 viewport sizes x 4 text scales** (320/360/400/412/768/1280 at
   1.0/1.3/1.6/2.0x), failing on RenderFlex overflow, vertical one-glyph-per-line
   text, and text starved to an ellipsis inside a sliver.
3. **By source audit.** Every `*_screen.dart` classified for loading / empty /
   error / RTL-safe padding.

**What this report does NOT contain: a screen-by-screen Android-vs-web visual
comparison.** The doctrine asks for one. It was not possible here: Chrome is not
on this machine's PATH (already recorded in CLAUDE.md), Playwright's Chrome is
not installed, and the browser extension is not connected. The web build
compiles and its payload was measured, but nobody has looked at it side by side
with the APK. **That is the single biggest hole in this report and it should not
be read as a pass.**

---

## Per-screen states — 62 screens

| axis | result |
|---|---:|
| Loading state | 54 / 62 |
| Empty state | 50 / 62 |
| Error state | 55 / 62 |
| **RTL-safe padding** | **62 / 62** |

Every screen without one of the first three was then **read**, because a count
is not a finding. The result: **no real gaps.**

### My own audit produced four false positives, and they are worth recording

The heuristic looked for `_loading` / `_error` / `catch` in the file. It missed
every screen that delegates its states to a bloc:

| flagged | reality |
|---|---|
| `forgot_password_screen` | `loading: state is AuthLoading` on the button; `AuthError` → snackbar in a `BlocListener`. **Both states present.** |
| `login_screen` | same pattern. **Present.** |
| `manage_exam_seats_screen` | 12 error paths, 7 loading paths, all local. **Present.** |
| `diu_portal_screen` | 7 error paths; the webview supplies its own progress. **Present.** |

This is the same lesson the Phase 0 register learned about `dispose()`: *the
absence of a keyword is not evidence of a defect, only a prompt to go and read
the file.* Filing those four as bugs would have sent someone "fixing" screens
that were already correct.

### Legitimately stateless (verified by reading, not assumed)

`splash`, `pending_approval`, `payment_webview`, `diu_portal_hub`,
`transport_import_preview`, `join_request_detail` — static screens, webviews, or
views rendered from data the parent already fetched. None performs a load of its
own that could fail or be empty.

---

## Layout — passes at every size and scale tested

All **335 tests** pass, including the 6x4 sweep over every shared widget with
adversarial content (a full Bangladeshi name, a real course title, a spelled-out
department). Nothing overflows, nothing renders one glyph per line, nothing is
starved to an ellipsis.

RTL: `EdgeInsetsDirectional` is used **239** times and there are **zero**
horizontally asymmetric `EdgeInsets.only(left:/right:)` left in `lib/`. The two
remaining `EdgeInsets.fromLTRB` calls are horizontally symmetric, so they have no
reading direction to respect.

---

## Verified on the device

| | result |
|---|---|
| Cold start | 664 ms to first frame rasterized |
| Reduced motion | Splash arc skipped — confirmed by comparing 1.6 s captures with `transition_animation_scale` at 1 and 0 |
| `EmptyState` rendering | VR-ID → Access Log: correct, and the AFOS top-right corner cut is visible on the icon badge |
| Card-tier signature radius | Visible on My Results and the course cards |
| Themed 404 | Now takes the app canvas instead of a hardcoded dark slab |
| Screens opened without error | dashboard, browse courses, clubs, lost & found, transport, hall, payment, VR-ID (3 tabs), results, assignments, my attendance, slide menu, login |

One defect was found this way and fixed: the 404's "Go Home" button ran
edge-to-edge, because the app theme sets a button `minimumSize` of
`Size(double.infinity, 52)` and nothing constrained it. No test could see it —
nothing overflowed, it just looked broken.

---

## NOT verified — read this before treating the app as signed off

1. **Android vs web, side by side.** No browser available on this machine. The
   web build compiles; nobody has looked at it.
2. **Roles beyond student and super_admin.** The teacher, staff, dept_admin and
   exam_controller screens — marks entry, attendance register, module leader,
   join requests, the `manage_*` tools — were never opened by a role that can
   reach them. Their permission logic is covered by
   `staff_menu_permissions_test.dart`; their *rendering* is not.
3. **The map's new road geometry, on screen.** Phase 5 is verified by unit tests
   and a live OSRM request returning a correct 21 km Dhaka route, but the phone
   locked before the line could be looked at.
4. **The command palette, in a browser.** Its ranking is unit-tested and the APK
   was measured to prove it does not ship to Android; the keyboard behaviour has
   not been exercised by a human.

Each of these needs about ten minutes with the app in front of you. None of them
is blocked by anything except access.
