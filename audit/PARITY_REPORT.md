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

## Second device pass — the three items that were owed

An earlier revision of this file listed four things as unverified. Three of them
now are.

### 1. The map's road geometry — VERIFIED

Route **R4, ECB Chattor → Daffodil Smart City, 13 stops**, on the device. The
line bends and turns with the streets between every pair of stops instead of
cutting straight across blocks, and it renders **solid** — which is the code's
own signal that the OSRM fetch succeeded, since an unsnapped fallback draws
dashed. No "Approximate route" note appeared, which is the same fact stated a
second way.

This is the Phase 5 root cause seen fixed, not inferred from a passing test.

### 2. Admin and teacher screens — VERIFIED

The session for this pass was a **super_admin**, so the screens that no role had
opened now have been:

| screen | state seen |
|---|---|
| My Course Offerings | empty state, correct copy |
| Join Requests | a real pending request, Decline/Accept side by side, batch-match notice |
| Teaching Load | a real allocation (CSE321 — Masuk, LIVE) |
| Manage Users | stat row + empty state |

The **AFOS top-right corner cut** from the Phase 3 radius pass is plainly visible
on the join-request and allocation cards — the change verified on real data
rather than on a fixture.

### 3. The command palette — VERIFIED BY TEST, not by hand

There is no browser on this machine to press Ctrl+K in. That is not a reason to
ship it unverified, so it is driven by **8 widget tests** that send real key
events: arrow-key movement, wrap-around at both ends of the list, Enter
navigating *and* closing, Escape closing **without** navigating, an unmatched
query handing itself to `/search` rather than dead-ending, and the fail-closed
case where permissions have not resolved.

That is stronger evidence than one manual click, because it runs again on every
change.

---

### 4. Android vs web, side by side — PARTLY VERIFIED

The blocker was that no browser on this machine can be driven. The way round it
was to stop trying to drive a browser here: `flutter build web` output was served
locally, `adb reverse tcp:8899 tcp:8899` mapped the port onto the phone, and the
web app was opened **in the phone's own browser** — same panel, same viewport,
same pixel density as the native app it is being compared against. That is a
better comparison than a desktop window would have given.

**Login screen, web vs native, at 1220x2712:** the card, the DIU logo, the
gradient canvas (including the snapped `authDeep` → `canvasDark`), field
styling, type scale, radius, the green CTA gradient and every string are
**identical**. The only difference is that the browser's own chrome takes
vertical space, which is the browser, not the app.

The build also **boots clean in Edge** — `flutter run -d edge --profile`
compiled and launched with no runtime errors or exceptions in the output.

---

## STILL not verified

1. **Authenticated screens on web.** The login screen matches; everything behind
   it was not compared, because signing in on the web build means entering a
   password, which I do not do. The shell, the nav rail at ≥1024px, and the
   command palette in a real browser are all still unseen. The palette's
   behaviour is covered by widget tests, but its *appearance* on web is not.
2. **Roles between student and super_admin** — `teacher`, `staff`, `dept_admin`,
   `exam_controller`. Both extremes of the role matrix have now been walked, so
   the shared shell and the admin tools are covered; the middle roles differ only
   in *which* of those already-seen screens they are granted, and that grant
   logic is pinned by `staff_menu_permissions_test.dart`. Lower risk than it was,
   not zero.
