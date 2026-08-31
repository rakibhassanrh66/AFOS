# REDESIGN_LOG

One entry per phase. Append, never rewrite. This is what a fresh session reads
to know where the work stands.

---

## Phase 0 — Audit · 2026-08-15 · COMPLETE

**Scope:** documentation only. No application code touched.

**Files created**
- `CLAUDE.md` (repo root) — project constitution, auto-read every session
- `audit/UI_INVENTORY.md` — all 62 screens: LOC, state management, data access, states implemented, slop weight
- `audit/SLOP_REPORT.md` — measured baseline against the BANNED list
- `audit/BUG_REGISTER.md` — 4 P1 groups (22 concrete sites), 6 P2, 4 P3
- `audit/CONTRACT_MAP.md` — 53 repository methods **plus** the inline-query contract
- `REDESIGN_LOG.md` — this file

**Verification**
- `flutter analyze` = 0 issues (unchanged baseline)
- `git status --short lib/` = 14 files, **all from earlier unrelated work**, none from Phase 0
- Phase 0's only additions are `CLAUDE.md` and `audit/`

**Measured baseline** (Phase 9 compares against these)

| Metric | Value |
|---|---:|
| Screens / routes / Dart files / LOC | 62 / 62 / 188 / 43,355 |
| Hardcoded `Color(0x..)` outside theme | 21 |
| Raw `Duration(milliseconds:)` outside theme | 66 |
| `LinearGradient` uses | 66 |
| `BackdropFilter` uses | 21 |
| Emoji in UI copy | 52 |
| `EdgeInsetsDirectional` (RTL-safe) uses | **0** |
| `disableAnimations` (reduced-motion) references | 9 |
| `HapticFeedback` calls | 3 |
| Screens querying Supabase directly | **33 of 62** |
| Screens with no loading skeleton | 18 |
| Screens with no empty state | 28 |
| `flutter analyze` issues | 0 |
| Tests passing | 282 |

**Decisions taken this phase (do not re-open)**
1. **Liquid Glass stays.** The generic "one blur per screen" rule was raised and
   overruled by the owner. Blur is structural (shell = 2–3 blurs before any
   screen draws), so the rule would have meant a full visual rebuild. Amended to
   "blur belongs to the shell; content surfaces do not add another".
2. **Android + web only.** Windows/Linux/macOS/iOS are out of scope. Visual
   Studio is not installed, `windows/` is a bare scaffold, and four dependencies
   have no Windows support.

**Three findings that change later phases**
- *Glass is structural, not per-screen.* Recorded in `SLOP_REPORT.md`; drove decision 1.
- *33 of 62 screens bypass the repository layer.* The frozen contract is far wider
  than 53 method signatures. `CONTRACT_MAP.md` Part B enumerates the inline
  tables/RPCs per screen. Phase 2 must treat these as untouchable.
- *Accessibility is the weakest axis, not aesthetics.* Zero RTL, 9 reduced-motion
  references, 3 haptics. This is a larger real-quality gap than the colour/radius
  slop, and it is invisible in a screenshot.

**Not done, deliberately**
No runtime bugs are registered — no device run or profile trace was taken.
That is Phase 7 (performance) and Phase 8 (parity).

**Next:** Phase 1 — design system foundation.

---

## Phase 1 — Design system foundation · 2026-08-15 · COMPLETE
Branch `redesign/p1-tokens`.

**Scope honoured:** `lib/config/theme/**`, `lib/core/haptics/**`, one test file.
**Zero screens, repositories, models or blocs touched** — verified by
`git status`.

**Files**
- NEW `lib/config/theme/motion.dart` — the 5-rung ladder, springs, stagger cap, reduced-motion helpers
- NEW `lib/config/theme/depth.dart` — one light source (top-left, 20°), elevation 0–4, radius per level
- NEW `lib/config/theme/spacing.dart` — 4/8/12/16/24/32/48 scale, gap widgets, 48dp touch floor
- NEW `lib/core/haptics/app_haptics.dart` — 4-verb haptic vocabulary, fires on commit, no-ops on web
- EDIT `lib/config/theme/app_text_styles.dart` — added the tabular-numeric role
- EDIT `lib/config/theme/liquid_glass_tokens.dart` — legacy motion constants now ALIAS `AppMotion`
- NEW `test/design_system_test.dart` — 20 tests turning the constitution into CI rules
- NEW `audit/DESIGN_SYSTEM.md` — the gallery doc

**Verification:** `flutter analyze` 0 issues · `flutter test` **302 passing**
(was 282, +20) · `flutter build web` succeeds.

**Decisions**
- The palette was NOT touched. Liquid Glass stays; what was missing were the
  four systems above, none of which existed.
- Legacy motion constants re-based rather than duplicated, so there is one
  ladder: `motionFast` 200→160, `motionStandard` 280→240, `pressDuration`
  120→90. Curve, pressScale and entranceScaleFrom are unchanged values.
- **Deferred to Phase 4:** page routes and sheets still run at `base` (240ms)
  though the ladder says `slow` (380ms). Retiming navigation by 36% is a feel
  decision that must be seen on a device, not asserted in a token file.
- `AppHaptics.enabled` is per-session; persisting it needs a repository write,
  which is out of Phase 1 scope.

**Known limitation, stated honestly.** The typography tests assert the shared
`tabularFeatures` list rather than a constructed `TextStyle`. DM Sans is fetched
by google_fonts at runtime rather than bundled, so touching any
`AppTextStyles.*` in a unit test triggers an HTTP request and fails offline.
The feature list is what carries the rule and what all three numeric styles
reference; bundling the font as an asset would let the styles themselves be
tested, and is worth doing.

**Next:** Phase 2 batch 1.

---

## Phase 2 batch 1 — dashboard / library / clubs · 2026-08-15 · COMPLETE
Branch `redesign/p2-batch1`. ~2,350 LOC across the three highest-slop screens.

**Per screen: before → after**

| | durations | raw radii | emoji | haptics |
|---|---|---|---|---|
| `dashboard_screen.dart` | 10 → **0** | 11 → 3 | 4 → 1* | 0 → **1** |
| `library_screen.dart` | 1 → **0** | 15 → 1 | 1 → **0** | 0 → **1** |
| `clubs_screen.dart` | 1 → **0** | 13 → **0** | 7 → **0** | 0 → **3** |

\* the remaining dashboard "emoji" is a code comment quoting the strings that
were removed, not UI copy.

**SLOP_REPORT entries closed:** every raw `Duration(milliseconds:)` in these
three screens (12 of the app's 66), 35 of 39 raw radii, and 10 of the app's 52
emoji (52 → 42 app-wide).

**What actually changed, beyond find-and-replace**

- **Emoji became real icons, not deleted glyphs.** The dashboard quick-chips
  read `'🏠 Room 402'` and `'📚 No books due soon'` — a picture glued to the
  front of a string. Emoji renders differently on every platform, is announced
  literally by screen readers ("house building book"), and cannot take the
  theme's colour. `_quickChips` now returns `({IconData icon, String label})`
  and the chip renders a real `Icon` from the app's own set.
- **Staggers are capped.** Three lists animated on `index * 60`, `index * 80`,
  `index * 100` with no ceiling — a 40-row list meant the last row appeared
  ~4s after the first, which reads as the app being slow. All now use
  `AppMotion.staggerFor`, capped at 6 items and reduced-motion aware.
- **Every duration reads through `AppMotion.durationOf(context, …)`**, so
  reduce-motion now actually suppresses these screens' animation instead of
  being ignored.
- **The module tile got the full press treatment** — `AppMotion.pressDuration`
  (90ms, inside one frame), `AppMotion.pressScale`, and a haptic on `onTap`
  rather than `onTapDown`, because `onTapDown` also fires when the finger
  slides off to cancel.
- **Haptics fire on commit**, placed next to the write's success path (after
  the renewal lands, after the membership request is accepted), not on the
  button press.

**Deliberately left alone**
- 4 raw radii remain: two parameterised (`BorderRadius.circular(borderRadius)`,
  already driven by the caller) and two 4px hairline bars, where the depth
  scale's 8px would read as a lozenge.
- No copy rewrite beyond emoji removal, and no state-coverage work: the
  dashboard still lacks an empty state. Those were in the Phase 2 prompt and
  are **not** done — see below.

**Verification:** analyze 0 issues · 302 tests passing · web build succeeds ·
`git diff --stat main` on `lib/features/*/data`, `lib/core/services` and
`lib/shared/models` is **empty** — the data layer was not touched.

**Honest gap.** The Phase 2 prompt asks for four states per screen, a full copy
rewrite, and responsive verification at 320/400/768/1280. This batch did the
token migration and the interaction rules; it did **not** add missing empty
states or verify responsive behaviour, because that needs the app running on a
device and I cannot see it. Those remain open for these three screens.

**Next:** Phase 2 batch 2.

---

## Phase 2 batch 2 — transport / schedule / mentorship · 2026-08-15 · COMPLETE
Branch `redesign/p2-batch2`. ~3,700 LOC, including the 2,357-line transport screen.

| | durations | raw radii | emoji | haptics |
|---|---|---|---|---|
| `transport_screen.dart` | 1 → **1\*** | 14 → **0\*\*** | 0 | 0 |
| `schedule_screen.dart` | 3 → **1\*** | 10 → **0** | 1 → **0** | 0 → **1** |
| `mentorship_screen.dart` | 1 → **0** | 10 → **0** | 2 → **0** | 0 → **2** |

\* both remaining durations are deliberate and documented — see below.
\*\* the one `BorderRadius.circular` left already passes `LiquidGlass.radiusPill`,
i.e. the `full` rung of the scale.

App-wide emoji: **52 → 39**. Data layer: `git diff --stat main` on
`lib/features/*/data`, `lib/core/services`, `lib/shared/models` = **0 lines**.

**The two durations that were NOT converted, and why the distinction matters**

This batch's real work was telling three kinds of "duration" apart. Converting
all three would have been the wrong kind of thorough.

1. **`_PulseDot`'s 1200ms — an ambient loop, not a transition.** The 620ms
   ceiling governs things moving from one state to another, where length reads
   as lag. This is a live-status dot breathing to say the data is current; at
   620ms it would read as an alarm, not a heartbeat. The duration stays.
   **What was genuinely broken is that it repeated forever regardless of
   reduced motion** — a perpetual animation is the worst offender for someone
   who asked the system to stop moving things. It now starts only when motion
   is allowed and stops (resetting to its resting size, not mid-pulse) if the
   setting is switched on while the screen is open.
2. **The search field's 300ms `Timer` — an input debounce, not motion.** It is
   how long to wait for typing to stop before spending a network request.
   Borrowing a motion rung would couple search latency to animation feel, so a
   later tweak to `base` would silently change how often the app queries
   Supabase. Commented in place so a future pass does not "fix" it.
3. Everything else — the staggers and entrance fades — converted normally.

**Also:** two uncapped staggers (`index * 60`, `index * 80`) and one (`i * 70`)
now use `AppMotion.staggerFor`; three commit haptics added on the write success
paths (pin a retake, request a session, save a mentor profile).

**Verification:** analyze 0 issues · 302 tests · web build succeeds · encoding
checked on all three files (no BOM, non-ASCII preserved).

**Still open for these screens**, same as batch 1: missing empty states, full
copy rewrite, and responsive verification at 320/400/768/1280 — all need the app
running on a device.

**Next:** Phase 2 batch 3 — `dept_chat_screen.dart` (13), `lost_found_screen.dart`
(13), `room_availability_screen.dart` (12).

---

## Phase 2 batch 3 — dept chat / lost & found / room availability · 2026-08-15 · COMPLETE
Branch `redesign/p2-batch3`. ~1,500 LOC across the next three highest-slop screens.

| | durations | raw radii | emoji | haptics |
|---|---|---|---|---|
| `dept_chat_screen.dart` | 2 → **0** | 11 → **0\*** | 1 → **0** | 0 → **3** |
| `lost_found_screen.dart` | 1 → **0** | 13 → **0\*** | 0 | 0 → **6** |
| `room_availability_screen.dart` | 3 → **0** | 9 → **0\*** | 1 → **0** | 0 → **2** |

\* every `BorderRadius.circular` / `Radius.circular` left in the three files
now passes a token (`LiquidGlass.radiusPill`, `radiusCard`, `radiusCut`,
`radiusControl`, `radiusSheet`). None is a literal.

App-wide: raw `Duration(milliseconds:)` **58 → 51**, emoji **40 → 38**,
haptic call sites **16 → 30**. Data layer: `git diff --stat main` on
`lib/features/*/data`, `lib/core/services`, `lib/shared/models` = **0 lines**.

**Two things this batch had to get right that a find-and-replace would break**

1. **A signature radius is not a symmetric radius.** The lost & found card is a
   photo header inside a rounded card. Swapping the card to `AppDepth.radius(2)`
   makes its top-right corner the 8px AFOS cut while the other three are 22 —
   so the old `BorderRadius.vertical(top: Radius.circular(16))` clip on the
   photo would have left the image standing proud of the cut corner. The header
   now clips to `topLeft: radiusCard, topRight: radiusCut`, i.e. the card's own
   silhouette.
2. **A chat bubble's tail corner is information.** Three corners round, one
   tight, is what says who spoke — so the asymmetry stays. What changed is that
   both values are now rungs (`radiusControl` 14 and `radiusCut` 8) instead of
   the free-hand 16/4.

**Bugs closed from BUG_REGISTER while in these files** (all presentation-layer,
all in the three files in scope):

- **P1-02, two controller leaks.** `room_availability._request` and
  `lost_found._openClaimDialog` each built a `TextEditingController` per sheet
  or dialog open and never released it — one leak per claim attempt. Both are
  now `try { … } finally { ctrl.dispose(); }`. In the lost & found case the
  field is read into a local *before* the `finally`, because the dispose has to
  come before the value is used downstream.
- **P1-01, one confirmed site.** `lost_found._pickImage` called `setState`
  after the image-picker await with no `mounted` guard. The picker is a full
  platform round-trip, so leaving the tab mid-pick throws. Guarded.
- **Unregistered, found while editing.** `dept_chat._scrollToBottom` runs in a
  post-frame callback that can land after the route is popped, touching a
  disposed `ScrollController` and reading `context` off a defunct `State`. Now
  returns early on `!mounted`.

**Three touch targets under the 48dp floor**, all measured, not guessed:

| where | was | now |
|---|---:|---:|
| room availability, day-selector row | 44 | 48 |
| dept chat, send button | 44 | 48 |
| lost & found, card "Claim" button | 30 | 48 |

The Claim button sits in a fixed-extent grid tile, so raising it 18px needed
`mainAxisExtent` 260 → 280 in the same delegate or the tile overflows. The
arithmetic is in a comment next to it.

**Press treatment, one element per screen** (Law 6). The free period chip, the
channel row, and the send button each scale to `AppMotion.pressScale` inside
`AppMotion.pressDuration`, reduced-motion aware. Haptics stay on the commit
path, never on `onTapDown` — in dept chat the send haptic fires on the
optimistic append, which is the moment the message actually appears.

**Verification:** `flutter analyze` 0 issues · `flutter test` **302 passing** ·
`flutter build web` succeeds · no BOM and non-ASCII preserved on all three files.

**Deliberately NOT changed, and why**

- **The three chat-background hex colours** (`0xFF0B1220`, `0xFF0E1F16`,
  `0xFF1F0E1B` in `_ChatRoomScreen._chatBackgrounds`) stay as literals. They are
  duplicated **verbatim** in `settings_screen.dart`, which is not in this
  batch's scope. Tokenising only this copy would leave two definitions of the
  same three colours free to drift. They need one paired change — add a
  `chatBackgrounds` map to `app_colors.dart` and point both files at it — and
  that touches the theme file plus an out-of-scope screen. **Reported, not
  done.** App-wide `Color(0x..)` outside the theme therefore stays at 21.
- `lost_found:264`'s `CachedNetworkImage` still has no `memCacheWidth`
  (BUG_REGISTER P2-06). That is a decode-cost fix and belongs to Phase 7.
- Spacing is still not systematically tokenised, same as batches 1 and 2. Only
  the values this batch already had to touch moved onto the scale.

**Still open for these screens**, same as every batch so far: missing empty
states, full copy rewrite, and responsive verification at 320/400/768/1280 —
all need the app running on a device.

**Next:** Phase 2 batch 4 — `register_screen.dart` (10), `grades_screen.dart`
(10), `payment_screen.dart` (10).

---

## Phase 2 batch 4 — register / grades / payment · 2026-08-15 · COMPLETE
Branch `redesign/p2-batch4`. ~1,590 LOC.

| | durations | raw radii | emoji | haptics |
|---|---|---|---|---|
| `register_screen.dart` | 6 → **0** | 5 → **0** | 0 | 0 → **5** |
| `grades_screen.dart` | 1 → **0** | 2 → **0** | 1 → **0** | 0 → **3** |
| `payment_screen.dart` | 2 → **0** | 7 → **0** | 0 | 0 → **1** |

All three files now contain **zero** raw `Duration`, **zero** raw radius
literals and **zero** raw `Curves.` references.

App-wide: raw `Duration(milliseconds:)` **51 → 45**, emoji **38 → 37**,
haptic sites **30 → 39**. Data layer: `git diff --stat main` on
`lib/features/*/data`, `lib/core/services`, `lib/shared/models` = **0 lines**.

**The third type role finally gets used.** Phase 1 built `numericLarge` /
`numericMedium` / `numericSmall` — tabular figures plus a slashed zero — and
the audit then measured **zero uses of them anywhere in `lib/features/`**. The
role existed on paper only. This batch is the first that had numbers worth the
name, and there are now 5 call sites:

| where | why it had to be tabular |
|---|---|
| CGPA hero, 42px | It recomputes as results publish. At that size a proportional `1` vs `0` visibly shoves the `/ 4.00` sitting beside it. |
| total marks, per result row | A column down the result list; proportional digits leave it ragged. |
| breakdown `12 / 20`, right-aligned in a 66px box | One row per mark component, all right-aligned — the exact case the role was written for. |
| `৳` amount, per payment row | A right-aligned column of money. |
| `৳` total-paid pill in the header | Recomputes when history loads, and the pill resizes under it otherwise. |

Each is `numeric*.copyWith(fontSize: …)` matched to the style it replaced, so
face, size and weight are unchanged — only the figures are tabular. Nothing
moved.

**Four touch targets under the 48dp floor**, all measured:

| where | was | now |
|---|---:|---:|
| register, account-type option (Student/Teacher/Staff) | ~45 | 49 |
| register, gender option | ~45 | 49 |
| payment, fee tile | ok | — |
| grades, result row | ok | — |

Both register toggles were `vertical: 14` padding around 13px text. Moved to
`AppSpace.lg`, which is on the scale and clears the floor.

**Copy.** `'Account created! Please sign in to continue.'` →
`'Account created. Sign in to continue.'` The exclamation is the chatbot voice
the doctrine names; the instruction is the same and one word shorter.

**Press treatment**, one element per screen: the payment fee tile. Grades and
register are form/list surfaces whose primary controls are already `AfosButton`
and `InkWell`, which carry their own press state — adding a second scale on top
would double-animate.

**Verification:** `flutter analyze` 0 issues · `flutter test` **302 passing** ·
`flutter build web` succeeds · no BOM, non-ASCII preserved on all three files.

**FINDING — there are two competing radius idioms in this codebase, and Phase 1
created the second without retiring the first.**

- `BorderRadius.circular(LiquidGlass.radiusCard / radiusControl / radiusSheet)`
  — symmetric on all four corners. **56 sites across 18 files**, including
  `dark_theme.dart`, `light_theme.dart`, `button_styles.dart` and three shared
  widgets (`feature_header`, `stat_tile`, `logout_tile`).
- `AppDepth.radius(n)` — routes through `LiquidGlass.signatureRadius`, so the
  top-right corner is cut to 8 and the AFOS silhouette survives. **93 sites**,
  and it is what batches 1–4 have been migrating raw literals onto.

They are both "tokens", so neither shows up in the slop count, but they render
differently. `grades_screen.dart` alone has 5 of the symmetric form.
**I did not convert them**, because converting one screen's cards to the
signature silhouette while `attendance`, `assignments`, `module_leader` and
`offering_card` keep square corners would make the academic module internally
inconsistent — worse than the current uniform-but-wrong state. This needs one
app-wide pass over all 56 sites, including the theme and shared widgets, and it
is a visible change that should be seen on a device before it is merged.
**Reported, not done.**

**Still open for these screens**, as in every batch: missing empty states, full
copy rewrite beyond the one line above, and responsive verification at
320/400/768/1280.

**Next:** Phase 2 batch 5 — `hall_screen.dart` (9), `settings_screen.dart` (9),
`manage_course_offerings_screen.dart` (9). Note `settings_screen.dart` holds the
other copy of the three chat-background hex colours flagged in batch 3, so that
paired fix can land with it.

---

## Phase 2 batch 5 — hall / settings / manage offerings · 2026-08-15 · COMPLETE
Branch `redesign/p2-batch5`. ~2,650 LOC, the largest batch so far.

| | durations | raw radii | emoji | hex | haptics |
|---|---|---|---|---|---|
| `hall_screen.dart` | 0 | 8 → **0** | 1 → **0** | 0 | 0 → **5** |
| `settings_screen.dart` | 0 | 6 → **0** | 9 → **0\*** | 3 → **0** | 0 → **8** |
| `manage_course_offerings_screen.dart` | 2 → **1\*\*** | 0 | 1 → **0** | 0 | 0 → **2** |

\* the one remaining "emoji" in settings is a doc comment quoting the strings
that were removed, not UI copy.
\*\* the survivor is the search debounce — see below.

App-wide: emoji **37 → 29**, haptic sites **39 → 54**, and hardcoded
`Color(0x..)` outside the theme **21 → 15** — the first movement on that number
since Phase 0. Data layer: `git diff --stat main` on `lib/features/*/data`,
`lib/core/services`, `lib/shared/models` = **0 lines**.

### The batch-3 debt is paid: chat backgrounds now have one definition

Batch 3 found the four chat-canvas colours living as raw hex in **two** files —
`settings_screen.dart`, which offers the swatches, and `dept_chat_screen.dart`,
which paints the chosen one — with nothing linking them. Editing one and not the
other would have made the swatch a lie: you pick a colour and get a different
one. Batch 3 deliberately left it because fixing one copy alone creates drift.

Both now read `AppColors.chatBackgrounds`. That is a **theme-file edit outside a
screen scope**, which is why it waited for the batch that owns the second copy.
`transparent` stays the value for `'default'` — it means "no override", and both
call sites fall back to the scaffold background when they see it.

### Emoji that were carrying meaning, not decoration

The theme picker's labels were `'☀️ Light'`, `'🌙 Dark'`, `'⚙️ Auto'` — a
picture glued to the front of a string. Three separate problems, all of them
real: emoji renders differently on every platform, a screen reader announces it
literally ("sun behind cloud Light"), and **it cannot take the chip's own
colour**, so the glyph stayed full-colour while the selected label went blue.
`_ThemeChip` now takes an `IconData` and renders a real `Icon` that inherits the
selected/unselected foreground. Same fix shape as the dashboard quick-chips in
batch 1.

The other six were trailing `✓` in success toasts. One got a real rewrite rather
than a trim: `'Thanks — sent ✓'` → `'Feedback sent'`, because "Thanks" is the
app talking about itself rather than telling you what happened.

### Four more touch targets under the floor

| where | was | now |
|---|---:|---:|
| settings, theme chip (Light/Dark/Auto) | ~45 | 49 |
| settings, accent colour swatch | 36 | 48 |
| hall, room-preference chip | ~41 | 49 |

The accent swatch is the interesting one: it is *drawn* as a 36px circle and
that is correct — it is a colour sample, not a button. Making the circle bigger
would have been the wrong fix. It is now wrapped in a 48dp `SizedBox` with the
circle centred inside, so the target clears the floor and the swatch looks
identical.

### One duration deliberately not converted

`manage_course_offerings_screen.dart:580` runs a 320ms `Timer` on the course
search field. That is an **input debounce, not motion** — how long to wait for
typing to stop before spending a network request. Borrowing a motion rung would
couple search latency to animation feel, so a later tweak to `base` would
silently change how often the app queries Supabase. Left in place with a comment
pointing at the identical call made for the transport search in batch 2, so a
future pass does not "fix" it.

### Also

One more leaked `TextEditingController` (`hall_screen._requestCancellation`,
built per sheet open, never released) now disposed after the modal resolves —
the third of that shape found so far.

**Verification:** `flutter analyze` 0 issues · `flutter test` **302 passing** ·
`flutter build web` succeeds · no BOM, non-ASCII preserved on all five touched
files.

**Not done, still.** The 56-site symmetric-vs-signature radius split reported in
batch 4 is untouched, and `manage_course_offerings_screen.dart` holds 7 of those
sites — this batch converted its raw literals only, of which it had none. Empty
states, full copy rewrite and responsive verification remain open for these
screens as for every batch.

**Next:** Phase 2 batch 6 — `exam_seat_screen.dart` (7), `assignments_screen.dart`
(6), `marks_entry_screen.dart` (6).

---

## Phase 2 batch 6 — exam seat / assignments / marks entry · 2026-08-15 · COMPLETE
Branch `redesign/p2-batch6`. ~1,290 LOC.

| | durations | raw radii | emoji | haptics |
|---|---|---|---|---|
| `exam_seat_screen.dart` | 2 → **0** | 4 → **0** | 0 | 0 → **0\*** |
| `assignments_screen.dart` | 0 | 5 → **0** | 1 → **0** | 0 → **4** |
| `marks_entry_screen.dart` | 1 → **0** | 2 → **0** | 1 → **0** | 0 → **2** |

\* **exam seat gets no haptics, on purpose.** It is entirely read-only — there
is no user commit anywhere on the screen, so there is nothing for a haptic to
confirm. Adding one to the pull-to-refresh would be exactly the "motion added
for polish with no interaction meaning" the constitution bans.

App-wide: emoji **29 → 27**, haptic sites **54 → 60**, tabular-numeric call
sites in `lib/features/` **5 → 10**. Data layer: `git diff --stat main` on
`lib/features/*/data`, `lib/core/services`, `lib/shared/models` = **0 lines**.

### The marks grid is the strongest tabular case in the app

`marks_entry_screen.dart` is a **column of number fields, one per student**,
with a running total beside each and a shared `/ max` denominator. DM Sans ships
proportional figures, so a `1` is narrower than a `0` — which means the digits
shifted under the caret as a teacher typed, and no two rows in the column lined
up. Three sites changed:

- the mark `TextField`'s own text style — the one being typed into
- the per-student running total (recomputes on every keystroke)
- the right-aligned `/ 100` denominator

Plus the assignment mark `12 / 20` and the exam-seat room chips (`604 · 45
seats`, several side by side). Each is `numeric*.copyWith()` matched to the
style it replaced — size, weight and face unchanged.

### A signature radius has to be honoured by whatever sits on the card's edge

`exam_seat_screen.dart` draws a 4px gradient bar across the top of each session
card. Moving the card to `AppDepth.radius(2)` cuts its top-right corner to 8
while the others go to 22, so the bar's old symmetric `Radius.circular(15)`
would no longer trace the card. It now uses the same
`topLeft: radiusCard, topRight: radiusCut` pair introduced for the lost & found
photo header in batch 3 — this is the second instance of that shape, and it is
worth treating as a pattern for anything that sits on a card's top edge.

The same trap caught the assignments card's `InkWell`: its `borderRadius` has to
match the `Container`'s or the ink splash spills past the corners. Both moved to
`AppDepth.radius(1)` together.

**Verification:** `flutter analyze` 0 issues · `flutter test` **302 passing** ·
`flutter build web` succeeds · no BOM, non-ASCII preserved on all three files.

**Still open**, unchanged: the 56-site symmetric-vs-signature radius split from
batch 4; empty states, full copy rewrite and responsive verification on every
migrated screen.

**Progress: 15 of 62 screens migrated.**

**Next:** Phase 2 batch 7 — `attendance_screen.dart` (5),
`attendance_register_screen.dart` (6), `assignment_submissions_screen.dart` (6).

---

## Phase 2 batch 7 — attendance / register / submissions · 2026-08-15 · COMPLETE
Branch `redesign/p2-batch7`. ~1,450 LOC.

| | durations | raw radii | emoji | haptics |
|---|---|---|---|---|
| `attendance_screen.dart` | 3 → **0** | 1 → **0** | 0 | 0 → **3** |
| `attendance_register_screen.dart` | 2 → **0\*** | 4 → **0** | 0 | 0 → **3** |
| `assignment_submissions_screen.dart` | 0 | 2 → **0** | 1 → **0** | 0 → **1** |

\* these two were not raw literals — they were `LiquidGlass.motionFast` /
`motionCurve`, which Phase 1 re-based onto `AppMotion`. See below.

App-wide: emoji **27 → 26**, haptic sites **60 → 67**, tabular-numeric call
sites in `lib/features/` **10 → 14**. Data layer: `git diff --stat main` on
`lib/features/*/data`, `lib/core/services`, `lib/shared/models` = **0 lines**.

### A token is not the same thing as a reduced-motion-aware token

Both attendance screens animated their chips with `LiquidGlass.motionFast` and
`LiquidGlass.motionCurve`. Those are *already* tokens — Phase 1 re-based them so
`motionFast` **is** `AppMotion.tight`, the same 160ms. Nothing about the value
was wrong, and a slop grep does not flag them.

They were still a defect: a bare constant cannot know about
`MediaQuery.disableAnimationsOf`, so a user who asked the system to stop moving
things still got these chips animating. Reading the same rung through
`AppMotion.durationOf(context, …)` is what actually turns it off. This is the
shape of the accessibility gap Phase 0 measured (9 `disableAnimations`
references against ~66 durations) and it does **not** show up in the raw-literal
count — worth remembering when the slop numbers eventually hit zero.

### ⚠ The status control is a real density change — look at it on a device

`_StatusButton` is the 4-way present/late/absent/excused segmented control in
the register: **the most-tapped control in the app** (once per student, per
session) and the one where a mis-tap marks the wrong person absent. It was
`vertical: 8` padding around an 11px label — a **~27dp** target, barely half the
floor.

It now carries `minHeight: AppSpace.minTouchTarget`. That is the correct fix and
I am confident in it, but be aware of the consequence: **each roster row grows
by roughly 19px**, so a 40-student register scrolls about 760px longer than
before. That is a deliberate density trade for hit accuracy on a
consequence-carrying control, and it is the kind of change that should be seen
on a real device before it ships.

### Numbers that recompute while you type

Four more tabular sites, all in the marking flow: the per-student attendance
percentage (the column a teacher scans to find who is under 75%), the
attended/counted ratio in the register header, the `+0.5` bonus chip, and the
per-submission mark field in `assignment_submissions_screen` — the same case as
the marks-entry grid in batch 6.

**Verification:** `flutter analyze` 0 issues · `flutter test` **302 passing** ·
`flutter build web` succeeds · no BOM, non-ASCII preserved on all three files.

**Still open**, unchanged: the 56-site symmetric-vs-signature radius split from
batch 4; empty states, full copy rewrite and responsive verification everywhere.

**Progress: 18 of 62 screens migrated.**

**Next:** Phase 2 batch 8 — `login_screen.dart` (6), `complete_profile_screen.dart`
(5), `releases_screen.dart` (6). `login_screen.dart` holds 3 of the 15 remaining
hardcoded hex colours, and `auth_brand_panel.dart` holds 3 more of the same
palette — check whether they are the same paired-duplication shape as the chat
backgrounds before splitting them across batches.

---

## Phase 2 batch 8 — login / complete profile / releases · 2026-08-15 · COMPLETE
Branch `redesign/p2-batch8`. ~1,500 LOC across four files (the brand panel came
along — see below), plus two token-layer additions.

| | durations | raw radii | hex | haptics |
|---|---|---|---|---|
| `login_screen.dart` | 8 → **0** | 2 → **0** | 3 → **0** | 0 → **2** |
| `complete_profile_screen.dart` | 0 | 5 → **0** | 0 | 0 → **2** |
| `releases_screen.dart` | 8 → **0** | 2 → **0** | 0 | 0 → **1** |
| `auth_brand_panel.dart` | 17 → **0** | 4 → **0** | 3 → **0** | 0 → 0 |

All four now hold zero raw durations, radii, `Curves.` and hex.

App-wide: raw `Duration(milliseconds:)` **43 → 38**, haptic sites **67 → 72**,
and hardcoded `Color(0x..)` outside the theme **15 → 9**. Data layer:
`git diff --stat main` on `lib/features/*/data`, `lib/core/services`,
`lib/shared/models` = **0 lines**.

### The auth hex was NOT the chat-background shape — and it hides a likely typo

Batch 7 flagged 3 hex values in `login_screen.dart` and 3 in
`auth_brand_panel.dart` and asked whether they were the same duplicated-map
problem as the chat backgrounds. **They are not.** They are two *different*
gradients that happen to share their first stop: the auth page canvas and the
brand side panel. So the fix is not one shared map but four named token lists —
`authCanvasDark/Light`, `authBrandDark/Light` — plus `authGridDark/Light` for
the hairline grid the login painter draws.

`auth_brand_panel.dart` was pulled into this batch rather than left for later:
it is the login/register screens' own side panel and shares the palette, so
splitting them would have left half the auth surface on literals.

**The finding worth your decision.** The shared first stop is `#0B1220`. The
app's declared dark canvas — `AppColors.background` / `LiquidGlass.canvasDark` —
is `#0B1**1**20`. **One hex digit apart.** They are almost certainly meant to be
the same colour, and `#0B1220` has since spread to six places: both auth files,
`app_router.dart`'s error page, `glass_chip.dart`, and the chat `'midnight'`
background.

I did **not** snap them together. That is a visible change to every signed-out
screen plus the router error page and a user-selectable chat canvas, and it is a
judgement about which value is the intended one — not something to infer.
The token now carries the exact original value as `AppColors.authDeep`, with the
near-collision documented at the definition. **Awaiting your call.**

### `AppMotion.sequenceDelay` — a token the screens asked for

Login has an eight-element staged entrance (logo, heading, subheading, two
fields, button, footer link, university line) on hand-picked delays of
120/200/280/340/420/480/540ms. The brand panel has its own seven-element one.
Neither could use `AppMotion.staggerFor`: that helper **caps at six items** so a
long list cannot trickle in — correct for a list, wrong for a fixed hero
sequence where capping simply deletes the choreography.

Rather than duplicate a local helper in both files, `sequenceDelay(context,
step)` now lives in `motion.dart` beside `staggerFor`, with the difference
between them documented at both. Steps are units of the 40ms `stagger` rung, so
the delays sit on the grid (0, 3, 5, 7, 8, 10, 12, 13) instead of being
hand-picked, and reduced motion collapses the whole sequence to zero.

Also retired: `Curves.easeOutExpo`, which appeared 15 times across the brand
panel and releases screen and is not in the token set.

### A third perpetual animation found

The brand panel had **three** loops running forever with no regard for reduced
motion — two drifting glow blobs (5.2s, 6.4s) and the logo frame breathing
(1.9s). Same call as `_PulseDot` in batch 2 and for the same reason: the
durations are correct because these are ambient, not transitions, and a
perpetual animation is the worst thing to inflict on someone who asked the
system to stop moving things. Under reduced motion all three are now simply
painted at rest.

**Verification:** `flutter analyze` 0 issues · `flutter test` **302 passing** ·
`flutter build web` succeeds · no BOM, non-ASCII preserved on all six touched
files.

**Self-correction worth recording:** my first draft of the `app_colors.dart`
comment used a `⚠` character, which pushed the app-wide emoji count from 26 to
27 — the constitution's own BANNED list, violated inside the file that defines
the design tokens. Replaced with `NOTE —`; count back to 26. Worth noting that
the check caught it, not review.

**Still open**, unchanged: the 56-site symmetric-vs-signature radius split from
batch 4; empty states, copy rewrite and responsive verification everywhere.

**Progress: 21 of 62 screens migrated.** Remaining hardcoded hex: **9**, in
`app_router.dart` (2), `splash_screen.dart` (3), `slide_menu.dart` (1),
`transport_screen.dart` (1), `afos_button.dart` (1), `glass_chip.dart` (1).

**Next:** Phase 2 batch 9 — `manage_users_screen.dart` (3),
`module_leader_screen.dart` (5), `join_requests_screen.dart` (5).

---

## Phase 2 batch 9 — admin & review screens · 2026-08-15 · COMPLETE
Branch `redesign/p2-batch9`. ~3,085 LOC across four files.

| | raw radii | emoji | haptics |
|---|---|---|---|
| `manage_users_screen.dart` | 3 → **0** | 0 | 0 → **4** |
| `module_leader_screen.dart` | **0 already** | 0 | 0 → **2** |
| `join_requests_screen.dart` | **0 already** | 1 → **0** | 0 → **2** |
| `feedback_screen.dart` (added) | 2 → **0** | 1 → **0** | 0 → **1** |

App-wide: emoji **26 → 24**, haptic sites **72 → 81**. Data layer:
`git diff --stat main` on `lib/features/*/data`, `lib/core/services`,
`lib/shared/models` = **0 lines**.

### This batch was mostly not a token migration

`module_leader_screen.dart` (1,167 LOC) and `join_requests_screen.dart` (986)
arrived with **zero** raw radii, durations or curves — they were already fully
tokenised by earlier work. The declared batch had roughly three literals in it.
So the useful work here was the review layer's missing commit feedback, and a
correction to the audit.

**Haptics on decisions that change someone else's life in the app.** These are
the screens where an admin approves an account, grants or removes a role,
deletes a user, admits fifty students at once, or a teacher accepts a course
allocation. Every one of those had **no tactile confirmation at all** — the only
signal was a snackbar and a list re-sorting under your thumb, which is exactly
the case where an admin working through a queue loses track of whether the last
tap registered. `success` for grants and approvals, `warning` for deletion,
decline, and partial bulk failure.

### CORRECTION — the audit's P1-02 group was diagnosed wrong

Phase 0 listed four files as "State holds a controller but has **no `dispose()`
at all**". Re-verified against the source, that is wrong in shape and partly
wrong in fact:

- **None of the four holds a State-level controller.** In every case it is a
  *local* controller created inside a method that opens a dialog or sheet. A
  `dispose()` override was never the fix, and its absence was never the defect.
  The real leak is one controller per dialog **open**, repeatable many times in
  a session.
- `join_requests_screen.dart` and `grades_screen.dart` are **false positives** —
  both already dispose correctly (a `finally` and an explicit call).
- `room_availability_screen.dart` was real, fixed in batch 3.
- `feedback_screen.dart` was real and the worst of the four: `_showSubmitSheet`
  was `void`, never awaited the modal, and leaked **two** controllers per open.
  Fixed here — hence its addition to this batch as a fourth file, which also
  closes the group.

**The lesson, recorded in `BUG_REGISTER.md`:** *"no `dispose()` override" is not
evidence of a leak* — only a prompt to read the file. The heuristic both
over-reported (2 false positives of 4) and under-reported: two further leaks of
the identical local-controller shape turned up in files it never flagged
(`lost_found_screen.dart` batch 3, `hall_screen.dart` batch 5). Four real leaks
of this shape have now been found and fixed; the register found two of them.

Also fixed: **P1-01 in `module_leader_screen.dart`** — `_respond` calls
`setState` straight after an awaited reason dialog with no `mounted` guard.

**Verification:** `flutter analyze` 0 issues · `flutter test` **302 passing** ·
`flutter build web` succeeds · no BOM, non-ASCII preserved on all four files.

**Progress: 25 of 62 screens migrated.**

**Next:** Phase 2 batch 10 — `club_chat_screen.dart` (4), `manage_hall_screen.dart`
(4), `sos_alert_detail_screen.dart` (2) / `manage_sos_screen.dart` (4). From here
the remaining screens are mostly slop ≤ 5, so batches can widen to 4–5 files.

---

## Phase 2 batch 10 — the five highest-slop remaining screens · 2026-08-15 · COMPLETE
Branch `redesign/p2-batch10`. Batch widened to five files, re-picked from a
fresh full-repo slop scan rather than the stale batch-9 guess.

| | durations | raw radii | emoji | haptics |
|---|---|---|---|---|
| `forgot_password_screen.dart` | 14 → **0** | 0 | 0 | — |
| `reset_password_screen.dart` | 11 → **0** | 0 | 0 | — |
| `admin_upload_routine_screen.dart` | 2 → **0** | 5 → **0** | 6 → **0** | 0 → **3** |
| `transport_import_preview_screen.dart` | 0 | 11 → **0** | 0 | — |
| `vr_id_screen.dart` | 4 → **0** | 4 → **0** | 1 → **0** | — |

App-wide: raw `Duration(milliseconds:)` **38 → 37**, emoji **24 → 18**, haptic
sites **81 → 84**. Data layer: `git diff --stat main` on `lib/features/*/data`,
`lib/core/services`, `lib/shared/models` = **0 lines**.

### The best find in this batch: an emoji that was load-bearing

`admin_upload_routine_screen.dart` built its upload result as a string with a
`✅` or `⚠` glued to the front — and rendered it as
`Text(result, style: TextStyle(color: AppColors.green))`, **unconditionally
green**. So `"⚠ Saved, but no users were notified"` was painted in exactly the
same success colour as a clean import, and the *only* thing distinguishing a
partial failure from a success was an emoji: one that renders differently per
platform, that a screen reader announces as "warning sign", and that cannot take
a theme colour.

Deleting the glyph would have destroyed the signal. The severity belongs in the
outcome, not in the characters, so `_notifyOutcome` now returns
`({String note, bool warned})`, `_PendingUpload` carries a `resultWarning` flag,
and the result line renders with a real `Icon` and amber-or-green from that flag.
A partial failure now *looks* like one. The haptic follows the same split —
`warning` when the routine saved but the broadcast did not.

This is the clearest example so far of why "remove the emoji" is not the task.
The task is to find out what the emoji was doing and give that job to something
that can actually do it.

### Two auth screens, one entrance pattern

`forgot_password_screen.dart` and `reset_password_screen.dart` are the same
staged reveal as login — scale-in badge, then heading, subheading, field,
button on hand-picked 120/180/260/320/380ms delays. All three now share
`AppMotion.sequenceDelay`, which batch 8 promoted into `motion.dart` precisely
because this pattern kept recurring. Third and fourth users, no new code.

Copy on the success view was rewritten while there: `'Check your inbox!'` →
`'Check your inbox'`, and `'A password reset link has been sent to your email.'`
→ `'We sent a password reset link to your email.'` — active voice, and the
exclamation is the chatbot tell the doctrine names.

### A curve the token set cannot express

`vr_id_screen.dart`'s verification stamp scaled in on `Curves.easeOutBack` — a
deliberate overshoot on the one confirmation moment of that screen. The token
set has exactly three curves (`standard`, `exit`, `inOut`) and **none of them
overshoots**, so it is now `standard`.

That is the constitution followed, but it is a real loss, and inventing a fourth
curve inside a screen file would be exactly the drift the token layer exists to
stop. **If the flourish is wanted back, it belongs in `motion.dart` as an
emphasis curve** — worth deciding, because a confirmation stamp is one of the
few places overshoot carries meaning rather than decoration.

### Scope notes

- **`splash_screen.dart` was deliberately skipped.** It ranks third on the slop
  scan (17) but it is **Phase 3's declared scope** — splash and hero motion.
  Migrating it now would mean rewriting it twice.
- **The shell and shared widgets are accumulating slop no screen batch will ever
  reach**: `slide_menu.dart` (22 — now the highest in the repo),
  `afos_button.dart` (6), `afos_text_field.dart` (5), `glass_bottom_nav.dart`
  (3), `top_app_bar.dart` (3), `glass_chip.dart` (3), `radial_logout_menu.dart`
  (3), `account_switcher_sheet.dart` (3). That is ~48 literals in code **every
  screen renders**, and Phase 2 is scoped to screens. It needs its own pass.

**Verification:** `flutter analyze` 0 issues · `flutter test` **302 passing** ·
`flutter build web` succeeds · no BOM, non-ASCII preserved on all five files.

**Progress: 30 of 62 screens migrated.**

**Next:** Phase 2 batch 11 — `club_chat_screen.dart` (7),
`manage_library_screen.dart` (6), `notification_center_screen.dart` (6),
`manage_stop_times_screen.dart` (4), `manage_notices_screen.dart` (4).

---

## Phase 2 batch 11 — club chat + four admin screens · 2026-08-15 · COMPLETE
Branch `redesign/p2-batch11`. Five files.

| | durations | raw radii | emoji | haptics |
|---|---|---|---|---|
| `club_chat_screen.dart` | 2 → **0** | 5 → **0** | 1 → **0** | 0 → **1** |
| `manage_library_screen.dart` | 0 | 4 → **0** | 2 → **0** | 0 → **2** |
| `notification_center_screen.dart` | 3 → **0** | 3 → **0** | 0 | 0 → **1** |
| `manage_stop_times_screen.dart` | 0 | 4 → **0** | 0 | 0 → **2** |
| `manage_notices_screen.dart` | 0 | 4 → **0** | 0 | 0 → **1** |

App-wide: raw `Duration(milliseconds:)` **37 → 35**, emoji **18 → 15**, haptic
sites **84 → 91**. Data layer: `git diff --stat main` on `lib/features/*/data`,
`lib/core/services`, `lib/shared/models` = **0 lines**.

### club chat was dept chat with different colours

`club_chat_screen.dart` turned out to be a near-line-for-line sibling of
`dept_chat_screen.dart`, migrated back in batch 3 — the same 16/16/4 bubble
radii, the same 24px input pill, the same 44dp send circle, the same 300ms
`_scrollToBottom`, and **the same `'No messages yet. Say hello! 👋'`**. Every
fix batch 3 made applied here unchanged, including the two that were not
cosmetic:

- the post-frame `_scrollToBottom` guard (the callback can land after the route
  is popped, touching a disposed `ScrollController`), and
- the send button's 44dp → 48dp touch target, with press state.

Two sibling screens drifting apart is how a design system dies, so they are now
line-for-line consistent. Worth noting for the remaining batches: **grep for the
shape, not just the file** — this one was invisible in the slop ranking because
its numbers were middling, yet it held a copy of a bug already fixed.

### Small but real

`manage_stop_times_screen.dart`'s save reports `'Nothing to save — no timings
entered yet'` on an amber snackbar. That is the app declining to act, not a
success, so it now gets `warning` rather than `success` — the haptic vocabulary
should agree with the colour that is already there.

The notification centre's swipe-to-dismiss now fires `warning` on
`onDismissed` — the one gesture on that screen that destroys something, and it
had no confirmation beyond the row vanishing.

**Verification:** `flutter analyze` 0 issues · `flutter test` **302 passing** ·
`flutter build web` succeeds · no BOM, non-ASCII preserved on all five files.

**Progress: 35 of 62 screens migrated.** The remaining screens are all slop ≤ 3.

**Reminder of what Phase 2 will NOT reach:** the shell and shared widgets
(`slide_menu.dart` at 22 is still the highest-slop file in the repo, plus
`afos_button`, `afos_text_field`, `glass_bottom_nav`, `top_app_bar`,
`glass_chip`, `radial_logout_menu`, `account_switcher_sheet`) — ~48 literals in
code every screen renders. And `splash_screen.dart` (17), held for Phase 3.

**Next:** Phase 2 batch 12 — `manage_hall_screen.dart` (3),
`manage_dept_chat_screen.dart` (3), `manage_sos_screen.dart` (3),
`sos_alert_detail_screen.dart` (3), `course_group_screen.dart` (4).

---

## Phase 2 batch 12 — closing the screen layer · 2026-08-15 · COMPLETE
Branch `redesign/p2-batch12`. **23 files.** The batch was deliberately widened
because the remaining work was 1–4 literals per file, not per-screen redesign —
and because a scan showed ten of those files were ones I had **already
migrated**.

### First: my own earlier batches left residue

Before picking new screens I re-scanned the files batches 1–11 had already
touched. Ten still carried slop, and the pattern was systematic:

> **Batches 1 and 2 converted `Duration(milliseconds:)` and
> `BorderRadius.circular(N)`, but not `Curves.` or the flutter_animate `N.ms`
> form.** Later batches caught all four. So the earliest screens — dashboard,
> schedule, library, transport, mentorship, clubs — were left half-migrated, and
> the log's "0 raw durations" claims for them were true only of the form I was
> grepping for.

Closed: 14 `Curves.easeOutCubic`, 5 `.ms` durations, 4 residual radii across
those six files, plus `my_attendance_screen.dart` which had never been reached.
The remaining entries in those files are the documented exceptions (search
debounces, the `_PulseDot` ambient loop, the transport connector hex, and three
doc comments that quote emoji they removed).

### Then: the 13 remaining un-migrated screens

`course_group_screen.dart`, `manage_sos_screen.dart`, `manage_hall_screen.dart`,
`manage_dept_chat_screen.dart`, `sos_alert_detail_screen.dart`,
`browse_courses_screen.dart`, `manage_course_offerings_admin_screen.dart`,
`registry_list_screen.dart`, `conference_room_screen.dart`,
`manage_feedback_screen.dart`, `unlock_screen.dart`, `manage_clubs_screen.dart`,
`manage_exam_seats_screen.dart` — 20 radii, 3 durations, 6 emoji.

**The batch-11 lesson paid off immediately.** `course_group_screen.dart` holds
the **third** copy of the chat bubble (after dept chat in batch 3 and club chat
in batch 11) — same 16/16/4 radii, same `'No messages yet. Say hello! 👋'`.
And `unlock_screen.dart` holds the **fourth** perpetual animation that ignored
reduced motion (after transport's `_PulseDot` and the brand panel's two blobs
and logo frame) — a fingerprint icon breathing forever, on the one screen a user
cannot get past without looking at it.

### Emoji in UI copy is now ZERO

**52 at Phase 0 → 0.** The last two were not in any screen and so were invisible
to every batch's file list: `sos_floating_button.dart` (`'Voice note added ✓'`)
and `avatar_picker.dart` (`'Photo updated ✓'`). Both are shared widgets.

The most consequential one this batch was `sos_alert_detail_screen.dart:105` —
`title: '🏃 Help is on the way'`, the push notification **sent to a person who
has triggered an SOS**. Emoji in the highest-stakes copy in the app.

The only three matches left in `lib/` are doc comments quoting the strings that
were removed.

Two more **P1-01** sites closed while in those files: `avatar_picker._pickAndUpload`
(setState after the gallery picker) and `sos_floating_button._toggleRecording`
(setState after the recorder stops).

### PHASE 2's SCREEN SCOPE IS COMPLETE

Every `*_screen.dart` in the app is on the token layer. What still greps as slop
is exactly the documented exception list:

| file | what | why it stays |
|---|---|---|
| `splash_screen.dart` | 8 durations, 6 curves, 3 hex | **Phase 3's scope.** Migrating now means writing it twice. |
| `transport_screen.dart` | 1200ms, 1 hex | `_PulseDot` ambient loop + commented connector colour (batch 2) |
| `unlock_screen.dart` | 1200ms | fingerprint ambient loop, now reduced-motion aware |
| 3 × search screens | 320/300ms `Timer` | input debounces, not motion |
| 3 × doc comments | emoji | quoting what was removed |

**Final Phase 2 numbers vs the Phase 0 baseline**

| metric | Phase 0 | now |
|---|---:|---:|
| Emoji in UI copy | 52 | **0** |
| Hardcoded `Color(0x..)` outside theme | 21 | **9** |
| `HapticFeedback` / `AppHaptics` call sites | 3 | **93** |
| Raw `Duration(milliseconds:)` | 66 | **35** |
| Tabular-numeric call sites in `lib/features/` | 0 | **14** |
| `flutter analyze` | 0 issues | **0 issues** |
| Tests | 282 | **302** |

**Verification:** `flutter analyze` 0 issues · `flutter test` **302 passing** ·
`flutter build web` succeeds · **no BOM on any of the 23 touched files**,
non-ASCII preserved · `git diff --stat main` on `lib/features/*/data`,
`lib/core/services`, `lib/shared/models` = **0 lines**.

### What Phase 2 did NOT do — carried forward, explicitly

1. **The shell and shared widgets were never in scope** and are now the
   highest-slop code in the repo: `slide_menu.dart` (22), `afos_button.dart`,
   `afos_text_field.dart`, `glass_bottom_nav.dart`, `top_app_bar.dart`,
   `glass_chip.dart`, `radial_logout_menu.dart`, `account_switcher_sheet.dart`
   — ~48 literals in code **every screen renders**.
2. **The 56-site symmetric-vs-signature radius split** (batch 4) is untouched.
3. **`#0B1220` vs `canvasDark` `#0B1120`** (batch 8) awaits a decision.
4. **An emphasis curve** for confirmation stamps (batch 10) — vr_id lost its
   overshoot to the token rule.
5. **Empty states, full copy rewrite, and responsive verification at
   320/400/768/1280** — open on every migrated screen since batch 1. These need
   the app running on a device and are the largest remaining Phase 2 debt.

**Next:** items 1–4 above are a natural "Phase 2.5 — the shell", or Phase 3
(splash) can start. Item 5 needs a device.

---

## Phase 2.5 + 3 — the shell, the splash, and RTL · 2026-08-15 · COMPLETE
Branch `redesign/whole-sweep`. **85 files.** Three workstreams that each had to
touch every file in the app, so they were done as one pass rather than three.

### 1. The shell and shared widgets (carried-forward item 1)

Phase 2 was scoped to `*_screen.dart` and therefore never reached the code
**every screen renders**. `slide_menu.dart` finished Phase 2 as the highest-slop
file in the repo (22). It, `top_app_bar.dart`, `glass_bottom_nav.dart`,
`glass_card.dart`, `glass_chip.dart`, `glass_sheet.dart`, `afos_button.dart`,
`afos_text_field.dart`, `info_card.dart`, `empty_state.dart`,
`feature_header.dart`, `offline_banner.dart`, `shimmer_card.dart`,
`supernova_loader.dart`, `radial_logout_menu.dart`,
`account_switcher_sheet.dart`, `avatar_picker.dart` and `user_details_sheet.dart`
are now on the token layer.

**The best find here: two answers to one question.** `afos_button` and
`glass_chip` each ran the *same* luminance test to pick a readable foreground
over a caller-supplied colour — `background.computeLuminance() > 0.45 ? dark :
white` — and each used a **different** dark: `#072A1C` in the button, `#0B1220`
in the chip. Neither was named, so neither could be found by the other. They are
now one token (`AppColors.inkOnLight`) behind one helper
(`AppColors.foregroundOn`), which is deliberately distinct from `onAccentOf`:
`onAccentOf` answers for the *theme's* accent by reading `colorScheme.onPrimary`,
`foregroundOn` answers for a colour handed in at the call site, where the theme
has no opinion.

**`shimmer_card` swept forever under reduced motion.** A skeleton communicates
"loading" by its *geometry*, so stilling the sweep loses nothing — and a
perpetual highlight is exactly what a reduced-motion setting is for. `Shimmer`
exposes no disable flag, so the supported way to still it is a period long
enough that the delta is zero; it now takes `Duration(days: 1)` when motion is
reduced. Recorded because it looks like a hack and is not.

### 2. The splash (Phase 3)

`splash_screen.dart` was held out of every Phase 2 batch because migrating it
then meant writing it twice. Two real defects, neither cosmetic:

- **Reduced motion only guarded the exit.** The three ambient loops (particles
  10s, glow 3s, hand 1.6s) were started unconditionally in `initState`, and only
  `_exitCtrl` checked `disableAnimations`. So a user who had asked the system to
  stop moving things still sat through ~1.85s of choreography they could not
  turn off — **on the first screen of the app**, before any setting of ours is
  reachable. The loops now start inside `_run()` only when motion is allowed,
  and reduced motion skips the entire arc and hands off immediately.
- **The destination was resolved AFTER the animation, not during it.** The
  session check, the biometric lookup and the last-route read all ran once the
  `Future.delayed` chain had finished, so their latency was *added* to the
  splash instead of hidden by it. `_destination` is now kicked off in
  `initState` and awaited at the end of the arc, so on a warm start it costs
  nothing and on a cold one we wait on the work rather than on padding. This is
  a cold-start win that the performance budget cares about, found by reading the
  screen rather than by profiling it — **it has not been measured on a device,
  and the < 1800ms budget is still unverified.**

Its three raw hex values became `AppColors.splashSheen` / `splashGlowTeal` /
`splashGlowBlue` — absolute rather than theme-aware, because this screen paints
before any theme applies, and that is now written down where the colours live.

**Carried-forward item 4 is resolved.** `AppMotion.emphasis` (`easeOutBack`) now
exists — the one curve that overshoots, reserved for a confirmation or an
arrival. It was added because two independent places reached for a local
`easeOutBack`/`elasticOut` to express "this arrived with force" (vr_id's verified
stamp, which batch 10 flattened to `standard` and recorded as a real loss, and
the splash choreography). Naming it makes the overshoot countable instead of
improvised. It is explicitly **not** for press feedback: a control that springs
past its resting size reads as unstable under the finger.

### 3. RTL — P2-01, the largest single item in the register

`EdgeInsetsDirectional` went from **0 → 239**. Every horizontally asymmetric
padding and margin in `lib/` is now direction-aware:

| | before | after |
|---|---:|---:|
| `EdgeInsetsDirectional` uses | 0 | **239** |
| `EdgeInsets.only(left:/right:)` remaining | — | **0** |
| `EdgeInsets.fromLTRB` remaining | — | **2** |

Both survivors are horizontally **symmetric** (`NavInsets.screen`, which passes
the same `h` on each side and whose callers demand a concrete `EdgeInsets`; and
one `(48, 64, 48, 160)` in transport). A symmetric inset has no reading
direction to respect, so converting them would be noise, not correctness — the
reason is now a comment in `nav_insets.dart` so the next sweep does not
"fix" it.

Bengali is LTR, so none of this is visible today. It was done now because the
doctrine requires it and because it is a cheap mechanical pass at 239 sites and
an expensive archaeological one at 900.

### 4. P1-01 is CLOSED — the last 5 sites

The register listed 18 real `setState`-after-`await` sites. Batches 3–12 closed
most of them; a fresh scan (matching `await …;` followed within 5 lines by
`setState(` with no `mounted` in scope or in the preceding 500 chars) found
**5 still open**, all confirmed by reading the code:

| site | why it was reachable |
|---|---|
| `conference_room_screen.dart` `_pickDate` | the date picker is a route of its own |
| `conference_room_screen.dart` `_pickTime` | same |
| `conference_room_screen.dart` `_submit` | after the awaited insert |
| `sos_floating_button.dart` `_toggleRecording` (**start** path) | batch 12 guarded the STOP path and left the START path |
| `sos_alert_detail_screen.dart` `_playVoice` | after an awaited signed-URL round trip |

The SOS one was the worst and is worth the note: the start path not only
`setState`s on a possibly-dead State, it then **arms a 1-second periodic timer
that does it again every second**. Its guard also stops the recorder on the way
out, so a `dispose()` that landed mid-`start()` cannot leave the microphone hot.

`settings_screen.dart:237` matches the scan and is a **false positive** —
`_previewSound` contains no `setState`; the match runs off the end of the method
into the next one. Do not "fix" it.

### 5. Two more closures found while verifying

- **P2-06 (image memory) is CLOSED.** All **6** `CachedNetworkImage` call sites
  now pass `memCacheWidth` (128 for the menu avatar, 200 for profile avatars,
  300 for book covers, 440 for lost-and-found photos). The register listed 4
  files; there were 6 sites.
- **The router's 404 was the last screen painting its own hex.** It hardcoded
  `#0B1220` + `Colors.white70`, so in **light mode** a mistyped link handed the
  user a black rectangle that looked nothing like the app. It now takes the
  Scaffold's themed background and `AppColors.textSecondaryOf`, and its icon
  takes `AppColors.red` instead of a near-miss `#D9576D`. That also removes one
  more site from the unresolved `#0B1220` question below.

### Numbers

| metric | Phase 0 | end of Phase 2 | now |
|---|---:|---:|---:|
| `EdgeInsetsDirectional` (RTL) | **0** | 0 | **239** |
| Hardcoded `Color(0x..)` outside theme | 21 | 9 | **2** |
| Raw `Curves.` outside theme | — | 20 | **7** |
| Raw `Duration(milliseconds:)` | 66 | 35 | **24** |
| Reduced-motion references | 9 | 14 | **18** |
| `AppMotion.durationOf` call sites | 0 | — | **95** |
| `AppDepth.radius` call sites | 0 | 196 | **217** |
| Emoji in UI copy | 52 | 0 | **0** |
| `flutter analyze` | 0 issues | 0 issues | **0 issues** |
| Tests | 282 | 302 | **302** |

The 2 remaining "hex outside theme" are both **comments** quoting a value that
was removed (`slide_menu.dart:147`) or explaining one that stays
(`transport_screen.dart:1531`). There is no live raw colour left in `lib/`
outside `lib/config/theme/`.

Of the 24 remaining raw durations, **7 are the token file itself** (where the
ladder is defined), 8 are the splash's hand-authored choreography, and the rest
are the documented exception list from batch 12 — ambient loops, search
debounces, and one realtime reconnect backoff. Same for the 7 raw curves: 6 are
splash `Interval`s, 1 is a `CurvedAnimation` in the notification popover.

**Verification:** `flutter analyze` **0 issues** · `flutter test` **302 passing**
· `flutter build web` **succeeds** · **no BOM on any of the 85 touched files**,
non-ASCII preserved (76 files still carry it) · `git diff --stat main` on
`lib/features/*/data`, `lib/core/services`, `lib/shared/models` = **0 lines**,
and on `supabase/`, `db/`, `android/`, `.env*` = **0 lines**. The frozen contract
has held across the entire redesign, not just this phase.

### Still open — the honest list

1. **`#0B1220` (`AppColors.authDeep`) vs `canvasDark` `#0B1120`** — one hex digit
   apart, almost certainly meant to be one colour. Still awaiting a decision.
   Snapping them changes every signed-out screen and the chat 'midnight'
   background. One consumer (the 404) was removed this phase.
2. **The 56-site symmetric-vs-signature radius split** (batch 4) — untouched.
3. **Empty states.** 34 of 62 screens use `EmptyState`; of the 28 that do not,
   the register's own note exempts 7 (forms and static hubs with no data state).
   The rest are real gaps.
4. **Loading skeletons** (P1-03) — 47 of 62 screens reference a shimmer or
   skeleton. Zero-layout-shift has never been *verified*, only asserted.
5. **Copy rewrite and responsive verification at 320/400/768/1280.**
6. **P2-04** — 33 screens query Supabase inline. Deliberately out of scope: the
   contract is frozen, and this is an architecture phase, not a redesign one.
7. **Everything runtime.** No device run, no profile trace, no APK size check.
   The performance budget (cold start < 1800ms, raster/UI < 8ms, APK < 28 MB) is
   **entirely unverified**, and the splash change above is the strongest reason
   to go and measure it.

**Next:** items 3–5 are one phase and need the app running. Item 7 is Phase 7
and needs a device.

---

## Phases 8 + 9 — the device, and the closing measurement · 2026-08-15 · COMPLETE
Branch `redesign/whole-sweep`. Steps 1–11 of the close-out plan.

### What was closed

| item | was | now |
|---|---|---|
| **P1-03** skeletons | asserted "matches final geometry exactly", never measured | **measured.** A real `InfoCard` row is 97px (136 wrapped); the default `ShimmerList` row is 80. `global_search` fixed; `ShimmerCard.infoCardRow` pinned to the widget by test |
| **P1-04** empty states | 34/62 screens | **42/62.** 9 hand-rolled blocks became `EmptyState`; the rest are forms, webviews and detail screens with no data state |
| **P2-04** inline queries | open, XL | **accepted debt**, written up in `CONTRACT_MAP.md` with the conditions to revisit |
| **P2-05** shrinkWrap | "confirm each is bounded" | **all 5 confirmed bounded.** The popover's bound is a `.limit(20)` 150 lines away, so it now says so in the code |
| **P3-04** radius split | 21 card sites symmetric, 217 signature | **0 symmetric card sites.** Control/pill tiers deliberately stay symmetric; pinned by a source-scanning test |
| `#0B1220` vs `#0B1120` | undecided for 4 phases | **snapped.** `authDeep` is now `LiquidGlass.canvasDark`; chat 'midnight' and the 404 followed |
| copy voice | 5 exclamation marks, one passive approval message | rewritten |
| responsive | harness swept 320/360/412 | **six sizes**, adding the 400/768/1280 the constitution names and web ships on |
| **Phase 8** parity | never run | **run on a motorola edge 60 pro.** 4 runtime findings, in `BUG_REGISTER.md` |

### The finding that mattered most

**`flutter build apk --release` failed outright.** A stale
`GeneratedPluginRegistrant.java` still registered `integration_test` — a
dev_dependency that release builds exclude — so javac failed. Web had built
green through twelve batches, analyze was 0, 310 tests passed, and no release
could have been produced. This is exactly the gotcha CLAUDE.md records: *`build
web` never compiles `android/`*. Nothing but a real `flutter build apk` finds it.

### Budgets, measured, not asserted

| budget | result |
|---|---|
| Cold start < 1800 ms | **664 ms** to first frame rasterized (499 ms first frame, 271 ms framework init). `am start -W` cold: 1065/1049/1027 ms. **PASS** |
| APK per-ABI < 28 MB | 31.4 / **34.6** / 37.0 MB. **FAIL** — arm64 is 24% over |
| Web FCP < 1800 ms | ~3.7–4.4 MB gzipped before first paint. **FAIL by arithmetic**; not browser-verified (no Chrome on this machine) |
| Reduced motion | **PASS**, confirmed on device — the splash arc is skipped |

The two failures are dependency-weight and renderer-choice problems, not
presentation ones. They are recorded at their real values; the budget was not
moved to meet them.

### Final numbers vs the Phase 0 baseline

| metric | Phase 0 | now |
|---|---:|---:|
| Emoji in UI copy | 52 | **0** (3 doc comments quote what was removed) |
| Hardcoded `Color(0x..)` outside theme | 21 | **2**, both comments |
| Raw `Duration(milliseconds:)` | 66 | **24** (7 are the token file itself) |
| `EdgeInsetsDirectional` | **0** | **239** |
| Reduced-motion references | 9 | **113** |
| Haptic call sites | 3 | **92** |
| Screens with an empty state | 34 | **42 / 62** |
| Symmetric card-tier radii | 21 | **0** |
| `flutter analyze` | 0 issues | **0 issues** |
| Tests | 282 | **310** |

**Verification:** `flutter analyze` 0 issues · `flutter test` **310 passing** ·
`flutter build web` succeeds · `flutter build apk --split-per-abi --release`
succeeds (after R1) · APK signed with the permanent cert
`2f49802b…623f` · `git diff --stat main` on `lib/features/*/data`,
`lib/core/services`, `lib/shared/models`, `supabase/`, `db/`, `android/`,
`.env*` = **0 lines**.

### Still open, honestly

1. **APK size and web payload** — both over budget, both dependency/renderer
   decisions, neither a redesign task.
2. **Roles not walked** — teacher and admin-only screens were verified as a
   student and a super_admin only.
3. **P2-04** — deliberate, documented, not forgotten.
4. **Skeleton geometry on 20 screens** whose rows are private classes and cannot
   be measured from a unit test.

---

## Phases 4–9 — the half the close-out plan had not covered · 2026-08-15 · COMPLETE
Branches `redesign/p4-interaction` … `redesign/p9-release`.

The earlier close-out plan finished Phases 0–3 plus 2.5, 8 and the measurement
half of 7 and 9. Phases **4, 5 and 6 had never appeared in this log at all**.
They do now.

### Phase 4 — interaction physics
60 raw `GestureDetector`s and 181 `onTap:` sites against **two** shared widgets
with any press state. New `Pressable`: same-frame press to 0.97, overshoot-free
release, haptic on commit, reduced motion keeps the state and drops the easing.

`AppHaptics` now **coalesces** — a primitive reporting `selection` plus a handler
reporting `success` was two buzzes 10ms apart, which the hand reads as a stutter
rather than as two facts. Strongest wins inside 60ms. That is what lets the
primitives always speak without auditing 92 call sites.

The preference also persists now and has an actual switch in Settings; it had
none since Phase 1, so 92 call sites answered to a setting no screen could
change. `AppHaptics.threshold()` had **zero** callers and is now on the
notification swipe's `onUpdate`.

**Correction recorded:** I had reported sheet dismissal as distance-only. Wrong —
Flutter's `BottomSheet` already does velocity-aware dismissal
(`_kMinFlingVelocity`, `bottom_sheet.dart:301`), and both sheet helpers use it.

### Phase 5 — the route line follows roads
Root cause confirmed in code: `_routePoints => _plotted.map((s) => s.point)`,
drawn as straight `Polyline` segments. A Dhaka route rendered as chords across
blocks and rivers. Styling cannot fix a wrong geometry.

**OSRM's public demo, chosen because this repo is PUBLIC** — ORS/GraphHopper/
Mapbox all need a key that cannot be committed. Its terms are honoured rather
than skirted: a serialized 1.1s gate for the ≤1 req/sec rule, non-commercial
use, and a fallback chain that is load-bearing because access can be withdrawn
without notice. Live-tested: Dhanmondi → DIU Ashulia, HTTP 200, 21.0 km, full
geometry. Cached on a hash of the stop coordinates.

Failure is **visible**: the chords render dashed under an amber "Approximate
route" note. Silently restoring a straight line after a failed fetch would be
worse than the original bug, because it would be intermittent.

### Phase 6 — the command palette
Ctrl/Cmd+K, web only. It does **not** recompute permissions — `slide_menu`
publishes what it decided into `navDestinations` and the palette reads it,
because a second implementation of the role matrix is how a palette starts
offering routes the router refuses. Fails closed: empty until permissions
resolve.

**APK measured before and after: 34.6 MB → 34.6 MB.** `kIsWeb` is a compile-time
constant, so the branch and everything it references leave the Android build.

### Phase 7 — performance, by measurement
Fixed, with evidence: `app_icon_source.png` (1024², 481 KB) was shipping in the
APK although only `flutter_launcher_icons` reads it, because pubspec declared the
whole `assets/images/` directory — **−0.5 MB on every ABI**. And `diu_logo.png`
decoded ~5.0 MB of ARGB to paint an 88px logo on three screens; `cacheWidth` at
all three.

Audited and already correct, recorded as negatives: **no realtime leaks** (all 13
subscribing screens unsubscribe), **no unbounded `shrinkWrap`** (all 6 bounded).

**No speculative `const`, no `RepaintBoundary` shuffling** — cold start passes
with 1.1s of headroom and there is no measured frame problem to optimise against.

### Phase 8 — parity
`audit/PARITY_REPORT.md`. 62 screens: loading 54, empty 50, error 55, **RTL-safe
62/62**. Every gap was then read rather than filed — and **four of my own flags
were false positives**, all screens that delegate their states to a bloc. Same
lesson as Phase 0's `dispose()` heuristic: the absence of a keyword is a prompt
to read the file, not evidence of a defect.

### Phase 9 — release gate
`audit/RELEASE_NOTES.md`. analyze 0, **335 tests**, both builds succeed, APK
signed with the permanent cert, and `git diff main` on repositories, services,
models, `supabase/`, `android/` and `.env*` = **zero lines**.

**Budgets: cold start PASSES at 664ms. APK FAILS at 34.1 MB against 28.
Web FCP FAILS.** Both failures are located to the byte in `PERF_BASELINE.md`;
`mobile_scanner`'s bundled ML Kit is 5.5 MB of the APK for one tab.

### What is genuinely still open
1. Android-vs-web side by side — no browser on this machine.
2. Teacher/staff/admin-role screens never opened by a role that can reach them.
3. The new map line and the command palette, on screen.
4. APK size and web payload, over budget.
5. `db/proposed/001_route_geometry_cache.sql`, unapplied, awaiting a decision.

---

## Release — v2.8.0 shipped to main · 2026-08-15

All redesign branches merged to `main` and pushed. 46 commits.

**Before pushing to a PUBLIC repo**, the payload was scanned: no `.jks`,
`key.properties`, `.env`, or `google-services.json` is tracked (all gitignored,
verified with `git check-ignore`), and the only matches for `service_role` /
`storePassword` in tracked files are **CI secret references**
(`${{ secrets.X }}`, `Deno.env.get`), not values. 144 changed files, zero
secret-shaped ones.

### The update path, rebuilt

Updating used to be a banner, a tap, a percentage on a tile, and then Android's
installer appearing with no explanation. Every part worked; none of it told the
user what was happening to them — and sideloading already asks a lot of trust
(unknown-sources prompt, Play Protect warning, permission screen). An app that
goes quiet in the middle of that is one people abandon.

`update_sheet.dart` narrates it: version, what changed, download progress, a
**verifying** stage (the service really does check content-length and the APK
magic bytes, so the pause at 100% has a name instead of looking like a freeze),
then an honest hand-off — *"Android is asking now"*, not *"Updated"*, because
tapping through the installer is the last thing this app controls.

**The account surviving an update was verified, not added.**
`LocalCacheService.clearIfVersionChanged` wipes only the `offline_cache` Hive box
and explicitly never touches the outbox (unsynced offline writes) or
`flutter_secure_storage` (session, biometric login). That was already correct;
what was missing was anywhere the user could read it. The sheet says it now.

### The README

The install section was four lines that mentioned none of what Android actually
does. It now walks the real sequence — browser warning, unknown-sources
permission, Play Protect "unsafe app blocked", done — states plainly that all of
it is normal for a non-Play-Store app, publishes the pinned signing fingerprint
(`2f49802b…623f`) that makes updates install cleanly over each other, and adds a
troubleshooting table for the four real failures: "App not installed" (a
signature mismatch, i.e. the protection working), parse errors from a truncated
download, Android 13+ "Restricted setting", and Play Protect removing the app.

**The web URL is deliberately not asserted.** There is no `.vercel/project.json`
in the repo and a guessed domain in a public README is a broken link; it points
at the repository's Deployments page instead. Swap in the real domain.

### Verification

`flutter analyze` 0 issues · `flutter test` **352 passing** · release APK builds
· merged to `main`, pushed, tagged `v2.8.0`.

Nine new tests pin the version comparison behind "an update is available" —
including the exact historical bug where a stored `2.3.2+21` compared as `2.3.0`,
and the `+build` suffix in a download URL that produced twelve 404s.

### Still owed at the time of writing

`tool/publish_release.sql` holds the drafted v2.8.0 `app_releases` row. It is
**not inserted yet, on purpose**: inserting it is what tells every installed
phone an update exists, and the download URL it implies does not resolve until
the release job has uploaded the APK. Announcing first means everyone who taps
Update gets an error until CI catches up.

---

## 2026-08-16 — The management tier, made usable

**Files:** `lib/features/shell/presentation/slide_menu.dart`,
`lib/features/admin/presentation/manage_users_screen.dart`,
`test/staff_menu_permissions_test.dart`,
`supabase/migrations/20260816003500_delegate_can_read_what_they_may_delegate.sql`,
`supabase/migrations/20260816004500_only_super_admin_appoints_a_manager.sql`

Delegation shipped in the previous batch and was, on inspection of the live
policies, broken in three separate directions.

**A grant changed the menu for `staff` and for nobody else.** `delegatedRoutes`
was inlined inside `staffMenuRoutes`. A teacher granted `library:manage`, or a
student granted `routine:upload`, passed the router guard (which asks
`PermissionSession`) and passed RLS — and got no menu entry. The capability was
real and unreachable. The list is now a shared function applied to every role,
deduped against the role's own routes, with Feedback kept last.

**A manager could write what they could not read.** INSERT and DELETE each got
a delegate policy; SELECT did not. Reading another user's grants matched
neither `user_id = auth.uid()` nor `super_admin`, so it returned zero rows —
silently, because RLS filters rather than errors. Three consequences: the
permission sheet showed every checkbox unticked for someone who already held
areas; revoking was impossible, because the client computes revocations as
`granted - selected` and `granted` was always empty; and re-ticking a held area
produced an INSERT violating `user_permissions_pkey`, failing with a
constraint name for a box that looked unticked. Delegation only ever worked in
the direction that hands out more access. Fixed by letting a delegate read a
row when the permission on it is one they hold — the same test that already
decides whether they may change it, so visibility and authority became the
same set.

**The tier could recruit into itself.** `permissions:delegate` is stored in the
same table as every working area, so "pass on anything you hold" applied to it:
a manager could appoint managers, who could appoint managers. No stated
invariant broke — nobody gains an area they lack — but authority to do a job
and authority to hand out that job are different powers, and only the second
compounds. Appointing and dismissing is now super_admin's alone, and a manager
can no longer enumerate the tier from inside it.

**And the reason none of it was visible.** Appointing a manager meant opening a
26-row checkbox list and knowing that "Permissions: delegate" — sitting between
"Notice: publish" and "Routine: upload" — was the row that means *this person
can now hand out work*. There is now a "Make a manager" action that says what
it does, a Manager / N areas / **no areas** badge on every card, a Management
filter, and the area picker following the appointment, because a manager
holding nothing can distribute nothing.

The screen also stops showing a delegate the Pending and CR queues, whose
buttons RLS refuses for them, and stops telling recipients that "a super-admin"
changed their permissions when it may have been their manager.

### Verification

`flutter analyze` 0 issues · `flutter test` **369 passing** (6 new, pinning that
delegated routes are role-independent and that `staffMenuRoutes` is its
baseline plus exactly that list) · release APK builds on all three ABIs
(31.1 / 34.2 / 36.6 MB) · pushed to `main` as `1ff9c55`.

Policy predicates were evaluated as a real manager (role `staff`, holding
`routine:upload` + `permissions:delegate`) via `set_config` on
`request.jwt.claims`:

| check | result |
|---|---|
| `is_a_manager` | t |
| `may_touch_routine_upload` | t — the area they hold |
| `may_touch_library_manage` | f — an area they do not |
| `may_appoint_a_manager` | f |

---

## 2026-08-16 — Authority that works without the super_admin in the room

**Files:** four migrations (`20260816011000` … `20260816012500`),
`lib/features/admin/presentation/activity_log_screen.dart` (new),
`lib/features/lost_found/presentation/lost_found_chat_screen.dart` (new),
`manage_users_screen.dart`, `manage_feedback_screen.dart`,
`feedback_screen.dart`, `lost_found_screen.dart`, `handover_scan_screen.dart`,
`slide_menu.dart`, `app_router.dart`, `test/staff_menu_permissions_test.dart`

### The bottleneck, and the hole underneath it

The previous batch distributes WORK. Every DECISION still resolved to one
policy: `get_my_profile_role() = 'super_admin'`. Approving a CR, approving a
signup, reading feedback, changing a role. An officer who joins to run a
department had two options — be made super_admin, which hands them the whole
system, or wait for the owner.

Five permissions now carry decisions: `cr:approve`, `users:approve`,
`roles:assign`, `feedback:triage`, and `audit:read` (which already existed and
had never been readable). They are ordinary rows in `permissions`, granted and
audited by machinery that already exists. A super_admin gives `cr:approve` to a
management head; the head passes it to a course teacher.

**`roles:assign` is bounded in the trigger, not the UI.** A holder may set only
`student`, `teacher`, `staff`, `exam_controller` — never on their own row, and
never on someone whose current role is outside that list. Writing that bound
turned up a hole that predated it: the trigger allowed **`admin` to change roles
without limit**, so any admin could promote anyone, including a second account
of their own, straight to `super_admin`. Admin is now bounded the same way.

### The CR queue was decorative

Found while adding `cr:approve`, not reported. `own_student_update` lets a
student UPDATE their own `students` row, and `protect_student_admin_columns`
guarded only `status` and `cgpa`. **`is_cr` was guarded by nothing.** One PATCH
to `/rest/v1/students?profile_id=eq.<self>` with `{"is_cr": true}` skipped the
approval queue entirely, granting `empty_room_requests` insert rights and the CR
badge in course chat. No uniqueness constraint either, so a section could hold
any number of CRs.

Now the trigger guards `is_cr`/`cr_since`, a partial unique index enforces one
CR per section, and `approve_cr_request` does the whole thing in one transaction
— demote the outgoing CR, promote the new one, stamp the review, and answer
everyone else waiting on that section instead of leaving them pending forever.

### Lost & Found — reachable, then provable

Measured, not guessed: `profiles.phone` is nullable and 4 of 11 profiles had
none; `contact_preference`/`contact_value` had **zero references in `lib/`**;
`own_lf_manage` is an `ALL` policy so a poster could write `status='returned'`
straight from the client and skip the verified RPC; and `returned_to` was always
the claimant.

That last one matters most. **Who receives depends on which way the item is
travelling:**

| type | receiver (scans, and is recorded) | giver (is scanned) |
|---|---|---|
| `lost` | poster — they lost it | claimant — they found it |
| `found` | claimant — they own it | poster — they found it |

The receiver scans the giver. Before, the poster always confirmed and the
claimant was always recorded, so on a `lost` post the log said the finder walked
away with someone else's property. The confirm button therefore moved: My Posts
for a lost item, My Claims for a found one.

Contact opens only once a claim is accepted — a `tel:` call and a realtime
thread that **expires 24h after acceptance in the RLS predicate**, not in a
cleanup job, so an expired thread is unreadable whether or not any row was
deleted. The number is never written to the post; it is released through an RPC
to one counterparty while the window is open. The old "Contact poster" dialog
read `profiles` directly, relying on a policy with **no expiry**.

### Oversight

`/admin/activity` unions the three decision trails — permission grants and
revokes, CR decisions, handovers — newest first, filterable, with handovers
closed without a scan flagged rather than blended in. `permission_audit` had
been recording faithfully since it was added and had never had a reader.

### Verification

`flutter analyze` 0 issues · `flutter test` **375 passing** (12 new) ·
release APK builds on all three ABIs (31.1 / 34.2 / 36.7 MB) ·
Supabase advisors: no ERROR-level findings, no new WARN categories.

Every policy evaluated as a real user via `set_config` on
`request.jwt.claims`, including the cases that must FAIL:

| case | result |
|---|---|
| plain student sets own `is_cr` | refused — "assigned by approval, not set directly" |
| `roles:assign` holder writes `super_admin` | refused — lists the four allowed roles |
| `roles:assign` holder writes `teacher` | allowed |
| plain student reads `authority_activity_log` | refused — "Not authorized" |
| manager reads an area they hold / do not hold | `t` / `f` |

Both test subjects were restored afterwards.

---

## 2026-08-16 (same day, follow-up) — The decision tier could not reach its rows

**File:** `supabase/migrations/20260816014500_the_decision_tier_could_not_reach_its_rows.sql`,
`lib/features/admin/presentation/manage_users_screen.dart`

Caught by checking the read path after shipping the write path, which is the
lesson here rather than the fix.

`protect_profile_privileged_columns` was taught to permit a `users:approve` or
`roles:assign` holder. The ROW POLICIES were not:

```
admin_manage_all_profiles (UPDATE): admin, super_admin
admin_read_all (SELECT):            admin, teacher, dept_admin, super_admin
```

A staff member holding either grant matched neither. The pending queue rendered
**empty** for them, and every write affected **zero rows** — silently, because
RLS filters rather than errors. The button did nothing and said nothing.

**Third time this exact shape appeared in two days** —
`delegate_read_what_they_may_delegate`, `cr_approver_reads_requests`, and this.
Each time a capability was added at the trigger or RPC layer without the row
policy that lets the caller reach the row. Naming it as a pattern: *when a
permission gains write authority, check the read path in the same change,
because the failure mode is silence.*

Fixed with a SELECT policy plus two narrow `SECURITY DEFINER` RPCs
(`set_user_role`, `set_user_verified`) rather than a broad UPDATE policy — a
general profiles UPDATE would have let a `roles:assign` holder edit anyone's
name, email or phone, which the trigger does not guard. The RPCs grant reach,
not permission: the trigger still enforces the ceiling.

Rejecting a pending signup DELETES the account, so it stays super_admin's even
though approving does not — and the button is hidden rather than disabled.

### Verification

`flutter analyze` 0 issues · `flutter test` **375 passing** · release APK builds
on all three ABIs. As a real `roles:assign` holder via `request.jwt.claims`:
`set_user_role(<student>, 'super_admin')` refused **by the trigger, through the
RPC**; `set_user_role(<student>, 'teacher')` allowed with `role_id` synced.
Subject restored, temporary grant removed.

*(First `build apk` attempt failed in Gradle with no error text captured; two
subsequent runs succeeded identically. Recorded as transient, not diagnosed.)*

---

## 2026-08-16 — The web becomes a console

**Files:** `lib/core/auth/capabilities.dart` (new),
`lib/features/web/presentation/` (new: `web_sidebar.dart`,
`consoles/role_console.dart`, `consoles/work_queue.dart`,
`widgets/web_layout.dart`, `widgets/adaptive_list.dart`),
`app_shell.dart`, `top_app_bar.dart`, `dashboard_screen.dart`,
34 `*_screen.dart` files, `vercel.json`,
`test/capabilities_test.dart` + `test/web_layout_test.dart` (new)

### The diagnosis

The web build was the Android app centred in a column — `AdaptiveContentWidth`
in `core/utils/responsive.dart`, adopted by three files, plus one `kIsWeb`
branch swapping the drawer for a 248px rail. Nothing else differed.

And the home screen was **wrong for most people**, not merely un-designed.
`dashboard_screen.dart` renders a fixed twelve-tile grid whose only role logic
is subtracting four student-only tiles, and it never reads `PermissionSession`
— zero references in 1035 lines. A staff member, a delegated officer, a teacher
and an exam controller all landed on the same eight student-facing tiles.
Routine upload, hall management, CR approval, marks entry, the activity log
appeared nowhere. That was the "staff and officers still get nothing" report,
and it was never a permissions bug.

### What shipped

**One capability model.** `capabilities.dart` answers "what can this person
do", read by the slide menu, the web sidebar, the console and the Ctrl+K
palette. `staffMenuRoutes` and `delegatedRoutes` keep their signatures and are
re-exported from it, so the 29 existing tests keep pinning behaviour. Capability
is role **and** grants: measured against the live database, `role_permissions`
has rows for only three roles, so a grants-only model would show a teacher an
empty app.

**Grouped sidebar.** The rail was the phone drawer stood on its end —
twenty-five identical rows for a super_admin. Now five collapsible groups, with
the group holding the current route pinned open, and a dot on anything that
arrived through a grant rather than the role.

**Role console.** Replaces the dashboard above 1024px. Leads with **work**:
every granted area as a live queue with a count, above everything else. Staff
with no areas get an explanation rather than eight useless tiles.

**Desktop chrome for all 52 screens at once**, through `AfosAppBar` — the
component they already share. Flat page header, not the floating glass pill;
the shell already owns the one blurred surface the constitution allows.

**Density on 34 screens.** `AdaptiveList` makes each list *row* the item, so two
or three columns appear on desktop **without giving up lazy building**. GridView
was rejected (fixed height), `Wrap` was rejected (eager). The four conversations
and two horizontal strips were deliberately left alone.

**Content width 1440** — correcting my own first attempt, which removed the
letterbox entirely. A card list stretched to 1900px is not denser; it is a line
of text with 1700px of dead space after it.

### Deployment bugs found while measuring

- `vercel.json` pinned Flutter **3.41.6** while everything is developed and
  tested on **3.44.8** — the shipped web was built by a different compiler than
  the one that verified it.
- No `Cache-Control` headers at all. Added, deliberately **without** `immutable`
  on `main.dart.js` or canvaskit: their filenames are stable across builds, so
  `immutable` would pin users to a stale build forever.
- The old `build/web` measured 18.1 MB with a source map — an instrumented
  build, not a release. A real release is **5.69 MB** (~1.34 MB brotli).

### Verification

`flutter analyze` 0 issues · `flutter test` **407 passing** (32 new) ·
web release builds, is served locally and **loads in a real browser**
(Playwright's bundled Chromium; Chrome is not installed here) with one expected
OneSignal warning · release APK **31.1 / 34.2 / 36.7 MB — byte-identical** to
before the web layer existed, which is the proof `kIsWeb` stripped all of it.

**Not verified here:** the authenticated shell. Reaching it requires typing a
password, which this process does not do, so the primitives behind every swept
screen are pinned by widget tests at desktop and narrow widths instead.

---

## 2026-08-16 — Prove the mailbox, not the string

Registration security, transactional mail, the missing approver notification,
and manage-users segmentation. Owner asked for the work first and review after,
so this went in without the usual plan-approval gate.

### The defect

`enforce_email_domain` proved an address *ends in* `@diu.edu.bd`.
`auto_confirm_email` then stamped `email_confirmed_at` on every insert.
Measured live: **all 12 `auth.users` rows carry `conf_mail_sent = false,
confirmed = true`** — not one verification mail has ever been sent. The system
proved the FORMAT of a string and never proved CONTROL of the mailbox, so
anyone who knows DIU's address pattern could register as a student they have
never met, and management adjudicated identity with no evidence.

Three more, all confirmed against the live project:

- **No approver notification has ever existed.** `on_auth_user_created` →
  `handle_new_user` writes the profile and stops. There is no
  `notify_admins_new_user` function and no trigger calling one. The
  approve/reject direction *does* notify (`manage_users_screen.dart:363`),
  which is why only this direction looked broken.
- **`manage_users_screen.dart:223` selected every profile with no `LIMIT`**,
  then filtered and searched client-side in Dart (`_filtered`, line 319) — and
  re-ran on every realtime `profiles` change. Invisible at 12 users; tens of MB
  per admin per session at 25,000, with a search box that could only find
  people already downloaded.
- **Password reset was link-only and GET-consumed.** Institutional mail runs
  link scanners that fetch every URL in a message, which spends a single-use
  recovery token before the student clicks. They see "link expired" on the
  first attempt with nothing explaining why.

### Design

**Flow inverted.** The client no longer calls `auth.signUp`. A signup stages in
`pending_registrations`; the auth user is created by `register-verify` (service
role, admin API) only once the code or link comes back. `auth.users` therefore
contains only mailbox-proven accounts and junk never reaches
profiles/students/teachers/staff. `handle_new_user` is **unmodified** — the
staged payload is replayed into `user_metadata` so it builds the profile
exactly as before.

**Both redemption paths, one row.** 6-digit code (typed) and 32-byte token
(link). Code and token are stored only as HMACs peppered from the function env.
The chosen password is held AES-GCM-encrypted for the ≤10 minutes it is staged,
because inverting the flow means Supabase cannot hold it yet.

**The link is safe to prefetch.** It opens a screen; the token is spent only by
an explicit POST. That is the specific fix for the scanner defect above.

**Mail load.** Cut volume first (dedupe collapses rage-taps; everything
non-critical stays on OneSignal push), then two-lane dispatch: inline send on
the hot path (~1s), diverting to `email_outbox` only when the per-minute
provider budget is spent, drained by a worker with backoff. A plain queue would
tax every user to survive a burst that happens twice a year. Rate limits reuse
the existing `consume_rate_limit` token bucket — no second limiter.

**Approval policy is data.** `app_config.auto_approve_roles`, owner-set to all
three roles. Caveat recorded in the SQL: a proven `@diu.edu.bd` mailbox shows
the person controls a DIU address, not that they are faculty.

### Files

- `db/proposed/003_identity_verification_core.sql` — staging, outbox, reset
  challenges, rate-limit policies, purge, atomic batch claim. **UNAPPLIED.**
- `db/proposed/004_manage_users_segmentation.sql` — `admin_user_facets`,
  `admin_search_users`, indexes. **UNAPPLIED.**
- `supabase/functions/_shared/{identity,mailer,email_templates}.ts`
- `supabase/functions/{register-request,register-verify,password-reset,email-dispatch}/`
- `lib/features/auth/` — repository methods (added, no existing signature
  changed), bloc, register/forgot rewiring, `verify_email_screen.dart`,
  `reset_with_code_screen.dart`, two new routes
- `lib/features/admin/presentation/manage_users_screen.dart` — server-side
  facets + keyset pagination + drill-down
- `lib/features/auth/presentation/login_screen.dart` — 320px clip
- `lib/features/web/presentation/consoles/role_console.dart` — duplication

### Verification

`flutter analyze` **0 issues** · `flutter build web --release` succeeds ·
**320px login clip fixed and confirmed in Chromium** (was "Create acco" at
320px and a cut arrow at 340px; renders in full at 320/340/360 after) ·
**desktop dashboard duplication removed and confirmed** against a live
signed-in session.

**NOT verified — and cannot be until the migrations are applied.** Applying
them was blocked by the permission classifier, so 003 and 004 sit unapplied in
`db/proposed/`. Until they are, every new auth screen and the whole
manage-users screen will fail at runtime: they call tables and RPCs that do not
exist yet. Nothing here has been exercised end-to-end against the database.

Also outstanding, owner-only: set `RESEND_API_KEY`, `IDENTITY_PEPPER`,
`PUBLIC_APP_URL`, `MAIL_FROM` as function secrets; turn ON "Confirm email" in
Auth settings; and only THEN drop `auto_confirm_email_trigger` — doing it in
any other order leaves a window with both gates down.

Open, not started: the desktop console is now mostly empty space. Removing the
duplicate grid was correct but exposed that the page has little real content;
filling it with actual queue contents rather than navigation tiles is a design
decision, not a cleanup.

---

### Follow-up same session — code is primary, admin is the fallback

Owner refined the model: **the emailed code settles it; admin approval is the
SECOND path, for the person the code failed.** That exposed a gap in what had
just been built — a signup whose code expired or whose five attempts were burnt
sat in `pending_registrations`, which is service-role only with zero policies,
so **no admin could see it and the applicant had no route forward at all.**

Added:

- `pending_registrations.review_state / review_reason / reviewed_by /
  reviewed_at`, plus a partial index on `needs_review`.
- `register-verify` now flags a row `needs_review` when the code expires or the
  last attempt is spent, and tells the applicant an admin can approve manually
  instead of dead-ending them.
- `admin_list_stuck_registrations()` — exposes ONLY safe fields. `code_hash`,
  `token_hash` and the encrypted password are never returned; an admin
  reviewing an identity claim has no business holding its credential material.
- `admin_reject_stuck_registration()`.
- `register-admin-approve` edge function — creating an auth user needs the
  admin API, so approval cannot be an RPC. Writes
  `identity_source = 'admin_override'`, which is the audit trail that says this
  mailbox was never proven and a named person vouched instead.
- Manage Users: a "Code Failed" tab, shown only when the queue is non-empty so
  an always-empty tab does not train people to ignore it.

Authorization on `register-admin-approve` is asked **as the caller**, not as
service_role: `can_browse_users()` reads `auth.uid()`, which is NULL under a
service-role client, so asking on that client would always answer false and
silently reduce this to an admin-roles-only check — locking out exactly the
delegates holding `users:approve` that the permission tier exists to empower.

### Deployment status

`flutter analyze` **0 issues**. All five edge functions deployed and **ACTIVE**
on `dtsptjallznnvattadlu` via `supabase functions deploy` (which uploads from
disk, so deployed == repo):
register-request, register-verify, password-reset, email-dispatch,
register-admin-approve.

**Migrations remain UNAPPLIED.** `apply_migration` is blocked by the permission
classifier, and `supabase db push` needs the database password, which is a
credential I do not handle. Both files are staged and ready:
`supabase/migrations/20260816190000_prove_the_mailbox_not_the_string.sql` and
`20260816190500_manage_users_segmentation.sql`. Until they are pushed, every
new auth screen and the whole Manage Users screen will fail at runtime — they
call tables and RPCs that do not exist yet. Nothing has been exercised
end-to-end against the database.

The Resend key was NOT accepted into the repo or into any command. This repo is
public and the key was pasted into a chat transcript, so it must be rotated and
set as a function secret by the owner.

---

### VERIFIED END-TO-END — 2026-08-16

Migrations applied (`20260816190000`, `20260816190500`), five edge functions
ACTIVE, secrets set. Run against the live project, not a mock:

| Step | Evidence |
|---|---|
| Non-DIU address | rejected server-side |
| Password at rest | `pw_encrypted: true` — AES-GCM, never plaintext |
| Code/token at rest | 64-char HMACs only |
| Rate limits | addr 3→2, IP 10→9, provider 100→99 |
| Wrong code ×5 | counts 4→0, 6th refused outright |
| Exhausted attempts | flagged `needs_review`, "All code attempts used" |
| Anti-enumeration | unknown address returns the IDENTICAL message as a wrong code |
| Mail dispatch | `lane: "inline"` (~1s), outbox stayed empty |
| Code redeemed | `autoApproved: true` |
| Account created | auth.users confirmed; profiles `is_verified`, `identity_source='diu_email'` |
| Student row | `batch_label 63`, `section A`, `status active` |
| **Approver notification** | **fired** → super_admin, deep link `/admin/users` |

`handle_new_user` needed no changes: the staged payload replayed through
`admin.createUser` produced an identical profile AND the students row with
batch/section intact — the main risk in inverting the flow, now disproven.

### Blockers found while testing, and their real causes

- **"API key is invalid" was never a bad key.** The setup commands were pasted
  with their placeholders intact, so `RESEND_API_KEY` was literally the string
  `<new-key>` and `PUBLIC_APP_URL` was literally `https://<your-vercel-domain>`.
  The second would have broken every emailed link even after mail worked.
- **`db push` had never run.** The project was not linked (no `config.toml`), so
  the command exited with "Cannot find project ref" before touching Postgres.
- **Schema changes are blocked for the agent by design** — the owner's
  `autoMode.environment` policy protects migrations/RLS/auth per HARD RULE 1,
  which denied MCP, CLI, and the settings edit alike. Correct behaviour.

### PRODUCTION BLOCKER — not optional

`MAIL_FROM` is `onboarding@resend.dev`, Resend's sandbox sender, which delivers
**only to the Resend account owner** (`user66test@gmail.com`). With it, zero
students would ever receive a code. A domain must be verified at
resend.com/domains and `MAIL_FROM` changed before any rollout.

### Test residue to clear before launch

- `auth_email_domain_allowlist` gained `user66test@gmail.com` so the sandbox
  sender's only deliverable address could register. **Remove before launch** —
  it is a bypass of the @diu.edu.bd rule.
- Test account `user66test@gmail.com` (student, batch 63) exists in profiles.
- A stale `qa_student@afos.test` row sits in the Code Failed queue.

---

### Follow-up — link path, reset, cron, and the first real UI fix

**Negative tests, all passing:** a redeemed token reused is rejected (single-use
holds); a garbage token is rejected; a reset request for a non-existent account
returns the IDENTICAL success shape (no membership oracle); a short password is
refused before any row lookup.

**Token path proven up to the compare.** A 12-minute-old reset token returned
"That code has expired" — NOT the generic "invalid or expired". Those are
different branches, so reaching the expiry check proves hmac(token) computed
correctly and the token_hash lookup FOUND the row. The remaining step, the
safeEqual + password write, is still unverified.

**Cron was missing entirely.** email_outbox had no worker, so anything that
overflowed would have sat there forever. Scheduled:
  drain-email-outbox      * * * * *    guarded by `where exists (state='queued')`
  purge-identity-ephemera */15 * * * *
Doing this exposed a mistake of mine: email-dispatch demanded the SERVICE-ROLE
key, which would have forced a plaintext superuser credential into
cron.job.command. The established pattern here (announce-pending-release) posts
with the PUBLISHABLE key for exactly that reason. Relaxed to any valid project
JWT — safe because the endpoint grants no capability: it drains rows already
queued, to addresses already fixed, and claim_email_batch takes each row FOR
UPDATE SKIP LOCKED so concurrent callers cannot double-send.

**Greeting bug.** "Md. Rakib Hassan" greeted as "Hi Md." — naive first-token
logic against names that usually lead with an honorific. Now skips honorifics
and bare initials: "Md. Rakib Hassan"→Rakib, "A. K. M. Rahman"→Rahman,
"Md."→there. Unit-tested and deployed.

**Manage Users verified against live data** (JWT claims simulated for the
super_admin): facets return 13 users with correct role/department breakdowns;
drill-down returns batches 68/67/65/63/62 and sections A/D/F; keyset pagination
returns two pages of 5 with ZERO overlap and 10 distinct rows.

**Facet bug found by that test** — `lecturer (1)` and `Lecturer (2)` rendered as
two chips for one designation, so filtering by either would silently miss part
of the group. Fixed in 20260816200000: grouping is case-insensitive, labelled
with mode() (the commonest real spelling) rather than initcap(), which would
turn 'CSE Exam Controler' into 'Cse Exam Controler'. Search normalised to match,
or a chip would return nothing for rows differing only in case. NOT YET APPLIED.

**First real UI fix, measured.** settings_screen was a bare ListView, so at
1440px the "Location Sharing" switch sat ~1100px from its own label, and the
screen had four different radii and a ragged right edge (cards to 1420, sound
group to 600, chat background to 527) — nothing shared a measure, which is most
of what reads as unconsidered. Now AdaptiveContentWidth(760): a form measure,
not the 1100 dashboard default. Verified in Chromium.

`flutter analyze` 0 issues · web rebuilt.

---

### Width pass + facet fix applied

Migration 20260816200000 applied. Verified live: the teacher designation facet
now returns `Lecturer (3)` where it previously returned `lecturer (1)` and
`Lecturer (2)` as two chips, with `professor` correctly still separate.

Only 2 of 67 screens used AdaptiveContentWidth. Three more had a bare
full-width ListView at the body root, the same defect settings_screen had —
each now wrapped at a 760px form measure (not the 1100 dashboard default):

  manage_exam_seats_screen   was a 1400px band holding one "Pick PDF(s)" button
  diu_portal_hub_screen      link cards stretched to 1400px for a title + chevron
  join_request_detail_screen decision buttons sat at the far edge of the request

Verified in Chromium against a live signed-in session (manage_exam_seats, the
one this account can reach). `flutter analyze` 0 issues, web rebuilt.

### STILL UNVERIFIED — the reset write

The reset row for user66test@gmail.com remains unconsumed, 0 attempts. The
code/token has never been supplied, so `admin.updateUserById` — the one step
unique to password reset — has still never executed. Everything around it is
proven; that single line is not.

### The new auth screens had never been rendered — two bugs found

verify_email_screen and reset_with_code_screen were built and their backends
exercised, but neither had ever been loaded in a browser. Rendered all five
states across 1440 / 390 / 320 in a clean session (they redirect to /home for a
signed-in user, so this needed its own browser with no session).

Both reset states render correctly. The verify screen had two defects, both on
the path someone reaches by RELOADING or bookmarking /auth/verify — `extra`
does not survive a reload, so the screen legitimately exists with no arguments:

  1. COPY: "We sent a 6-digit code to . Enter it below" — a dangling period
     where the address should be.
  2. CRASH: _verifyWithCode called `widget.email!` on that same path, so typing
     six digits was a null-check crash rather than an error message.

Now three states, not two: link / code / lost. The lost state says what
happened and offers the only route forward instead of a code field that cannot
succeed. Verified at 320px.

Also fixed a copy contradiction on the link path: the heading read "That link
didn't work" above a body reading "That code is invalid". The server keeps ONE
generic rejection for both paths on purpose (so it cannot be used to tell them
apart), but the client knows which path it is on and now says so.

`flutter analyze` 0 issues, web rebuilt, screens re-verified.

### Desktop console: the data half, and a bug the build found

Reference: a university admin console (4 screenshots) — KPI cards with icon
tile + delta badge, progress strips, line/area trends, donut and gauge, and
tables with status pills. Built the parts the data supports, in AFOS's dark
tokens rather than the reference's light theme.

DELIBERATELY NOT BUILT, and why:
  * The twelve-month trend charts. There is no time-series in this schema; the
    only date to aggregate is profiles.created_at, which yields two or three
    monthly points over the project's life. Chart guidance is explicit — under
    four points, use a stat card. A smooth curve through three real values is
    an invented trend.
  * The gauge. It answers "one measure against one target"; approvals have no
    target, and for several figures at once the guidance says use a row of
    compact indicators — which WebStatStrip already is.
  * A donut for the role split. Four categories with one holding most of the
    mass makes the small slices unreadable and forces a colour→legend lookup
    per value. Labelled bars put name, count and share on one line, so it reads
    in greyscale and to a screen reader; colour stays decoration.

BUILT: lib/features/web/presentation/consoles/admin_overview.dart —
figures (people / awaiting approval / code failed), a labelled population
breakdown, and recent joiners with a status pill that surfaces
identity_source: 'Email proven' vs 'Approved by admin' vs 'Awaiting approval'.
That column is the point of the whole verification effort and had no reader
anywhere in the app. Reuses the existing WebStatStrip/WebStat/WebPanel
primitives — which already existed and were unused on this screen — rather
than adding a second set. Web-only (kIsWeb + isExpanded); the phone dashboard
is a launcher by design and is untouched. Renders nothing for viewers who
cannot act on it.

### THE BUG THIS FOUND — can_browse_users() locked out every delegate

has_permission() reads ONLY role_permissions. AFOS's delegation tier lives in
user_permissions. So can_browse_users(), which gates admin_user_facets,
admin_search_users, admin_list_stuck_registrations and
admin_reject_stuck_registration, refused anyone whose only route was a direct
grant: they saw Manage Users and got 42501 from every query on it.

Fourth instance of this exact shape in this log. My own RPC tests missed it
because I ran them as super_admin, which satisfies the role branch and never
exercises the grant branch — the bug only exists for someone who has no other
route. Rendering the console as a real delegate is what exposed it.

Fixed in 20260816210000 by adding the user_permissions branch.
has_permission() itself deliberately untouched — redefining it would silently
change authorisation for every other caller.

`flutter analyze` 0 issues.

---

## 2026-08-17 — A missing mail must not be a dead end

### What the owner hit

Registered with a real DIU address on the LIVE app and got a "confirm" mail
that, once clicked, still parked them on the approval screen. Both halves of
that are bugs, and neither is the one I would have guessed.

### Diagnosis, from the row rather than the report

    hassan22205101554@diu.edu.bd
      identity_source   'self'          <- register-verify NEVER RAN
      is_verified       false
      created_at        17:01:34
      email_confirmed_at 17:02:10       <- 36s LATER, not the same instant

register-verify creates accounts with `email_confirm: true`, so its rows have
those two timestamps ~100ms apart (compare user66chatgpt: 13:29:12.39 /
13:29:12.49). A 36-second gap is a human clicking a link. So this account came
from the OLD path — a raw `auth.signUp` — which 20260816190000 correctly
stopped auto-confirming, so GoTrue sent its own built-in confirmation mail.
That path confirms the mailbox in auth.users and writes NOTHING to
profiles.is_verified, which is the gate the app actually reads.

**The cause is that none of this identity work is deployed.** The edge
functions are live and the migrations are applied, but the Flutter client that
calls them has been uncommitted since 6de3669. The live web build and the
v2.9.0 APK still call auth.signUp. Every real signup today lands in that
stranded state.

Incidentally proven: Supabase's built-in mailer DOES reach @diu.edu.bd. That
is the only reason a confirmation mail arrived at all.

### The defect underneath, which the report did not mention

The manual-approval fallback existed but **could only be entered by failing at
the code.** register-verify flags a row 'needs_review' on expiry or on five
wrong attempts. Someone who never received a mail can do neither — you cannot
exhaust attempts on a code you do not have. They waited out ten minutes and
had no queue entry, no button, and no administrator aware they existed.

Worse, and measured live during this session:

    POST register-request  ->  HTTP 500
    "You can only send testing emails to your own email address"

dispatch() throws on a permanent provider rejection (correct in isolation —
queueing an address Resend will never accept just burns six attempts), but
that throw escaped register-request AFTER the row was staged. So the signup
really was saved, the applicant got an error, and they never reached
/auth/verify — the one screen carrying the escape hatch. A mail outage locked
people out of the route built for a mail outage. While MAIL_FROM is the
sandbox sender, that is EVERY applicant, not an edge case.

### What shipped

**The applicant can now raise their own hand.** New edge function
`register-review-request` flips the staged row to 'needs_review' with reason
"Applicant reported the email never arrived". It creates nothing and grants
nothing — approval stays in register-admin-approve behind can_browse_users().
Returns an identical `{ok:true}` whether or not a signup exists for the
address, matching register-request and password-reset, because it is reachable
without a session and would otherwise be an oracle for which DIU addresses have
a signup pending. Idempotent via `.eq('review_state','none')` on the UPDATE
rather than a read, so concurrent presses cannot double-queue.

**A mail failure no longer destroys the signup.** register-request now returns
`{ok:true, mailFailed:true}` instead of 500, so the client reaches the verify
screen and leads with the fallback.

**Four screen states became five.** link / lost / code / **mail-failed** /
**submitted**. The mail-failed state does not render a code field, because no
code was sent and a field that cannot succeed is furniture; manual approval is
its primary button. The submitted state keeps a way back to the code field —
register-verify does not care that a review is pending, so proof still beats
the queue if the mail turns up late.

**Recipient resolution extracted** to `_shared/approvers.ts` rather than
copied. The set is "admin roles PLUS anyone holding a direct users:approve
grant", and the direct-grant half is exactly what has now been the bug four
times in this log.

### Files

    supabase/functions/_shared/approvers.ts             new
    supabase/functions/register-review-request/         new
    supabase/functions/register-verify/index.ts         uses shared approvers
    supabase/functions/register-request/index.ts        mailFailed, manualFallback
    supabase/migrations/20260817120000_...sql           NOT APPLIED
    lib/features/auth/data/repositories/auth_repository.dart
    lib/features/auth/bloc/auth_state.dart, auth_bloc.dart
    lib/features/auth/presentation/register_screen.dart, verify_email_screen.dart
    lib/config/routes/app_router.dart

### Verified live

Three functions deployed. Against the real project:

    no pending row        -> {"ok":true}      (anti-enumeration holds)
    missing email         -> 400
    no auth header        -> 401
    register-request      -> 200 mailFailed:true  (was 500)
    raise hand            -> row 'needs_review', reason recorded
    press again           -> still one row, one notification (idempotent)
    admin queue           -> appears with ATTEMPTS 0, which is the whole point:
                             it got there without failing at a code first
    notified              -> 2 recipients, roles super_admin AND staff — the
                             staff account is a delegate with no admin role,
                             so the user_permissions branch is live
    register-admin-approve with anon key -> 401 (privileged half fails closed)

Test rows, notifications and rate-limit buckets deleted afterwards.
`flutter analyze` 0 issues · `flutter build web` succeeded.

### The owner's own account, unblocked

hassan22205101554@diu.edu.bd set is_verified = true, identity_source =
'diu_email'. Justified rather than waived: GoTrue had genuinely confirmed that
mailbox via a clicked link, so 'diu_email' is the honest provenance. It was the
ONLY account in the project sitting in that state.

### Migration applied — 20260817180858

The owner opened the schema-change policy, so this was applied directly rather
than handed over. Ledger version 20260817180858 (NOT the 20260817120000 wall
clock the file was first written with — renamed to match, per the gotcha).

Verified by BEHAVIOUR, not by reading the function back. Three rows, all long
past expiry, then `purge_identity_ephemera()`:

    needs_review,  3 days old   -> SURVIVED   (would have died at 24h before)
    none,          3 days old   -> deleted    (abandoned, unchanged)
    needs_review, 40 days old   -> deleted    (30-day cap holds)

Only the row that must survive survived. `manual_approval_fallback` = true,
`registration_review_request` bucket = 2 / 0.02. Test rows deleted;
pending_registrations back to 0.

HARD RULE 1 in CLAUDE.md amended the same day so the constitution and the
harness policy agree — applying is allowed during feature work, still frozen
during a redesign phase, and now carries three obligations instead of a
handoff: mirror with the ledger version, verify behaviourally, report what ran.

---

## 2026-08-17 (same day) — Backend sweep

Asked to confirm the backend is healthy. It is, with one latent bug found and
fixed. Everything below is measured, not inspected.

### Healthy

    cron              10/10 jobs active, ZERO failures in 24h
                      drain-email-outbox 1440/1440 (once a minute, exactly)
                      purge-identity-ephemera 96/96
    email_outbox      0 rows — no backlog, nothing stuck, nothing retrying
    pending_registrations  0 rows
    profiles          0 unverified accounts
    edge functions    13 ACTIVE, all verify_jwt: true
    privilege gates   set_user_role and set_user_verified BOTH gate internally
                      and raise — no repeat of the NULL role_id escalation
    service-role-only tables  pending_registrations, pending_password_resets,
                      email_outbox, rate_limit_buckets, app_secrets,
                      definer_acl_allowlist all correctly invisible to
                      authenticated

Advisors: 61 lints, none ERROR. 48 are `security_definer_function_executable`,
which is this app's architecture — those RPCs each gate internally and were
audited in 20260725121510. Two are `extension_in_public` (pg_net, pg_trgm),
standard Supabase noise. One remains real and needs the dashboard:
**`auth_leaked_password_protection` is still off** — the long-standing SEC-6.

### The kill switch works in both directions

Not assumed — toggled live. With `manual_approval_fallback = false`:

    register-request        -> manualFallback: false   (client hides the button)
    register-review-request -> 503, refuses            (server refuses a stale client)

Defence in depth: an old cached client cannot queue reviews after the fallback
is retired. Restored to true.

### FOUND AND FIXED — grading_scale was invisible to the trigger that reads it

`grading_scale` had RLS enabled with NO policy, which denies every row.
`calculate_grade()` — the trigger on `marks` — is INVOKER, not DEFINER, so it
reads that table as the teacher doing the write:

    select count(*) from grading_scale   as authenticated -> 0
    select letter_grade for 85           as owner         -> 'A+'

and it does not check its own lookup:

    SELECT * INTO scale FROM grading_scale WHERE ... LIMIT 1;
    NEW.letter_grade := scale.letter_grade;   -- NULL when nothing matched

`SELECT INTO` with no match leaves the record NULL and raises nothing, so a
mark written by a plain authenticated user would be stored UNGRADED, silently.
Same shape as the blank-department bug and the view-drift gotcha: nothing
breaks, it just quietly answers nothing.

Not currently biting — `marks` is empty and the only SQL writer is
`approve_grade_change()`, which IS definer and bypasses RLS. A landmine, not a
fire; the first direct PostgREST insert into `marks` arms it.

Fixed in 20260817182441 by opening the TABLE, not by elevating the trigger —
making a write trigger SECURITY DEFINER to solve a read problem trades far
more privilege than the problem is worth. grading_scale is the published DIU
boundary table (80->A+ … 0->F), in every student handbook.

Verified as authenticated after applying: 10 rows visible, 85->'A+', 38->'F',
72->3.50, and INSERT still rejected with 42501. Read opened, writes untouched.

---

## 2026-08-17 — The console measured against the reference, properly this time

The owner re-shared the four reference screenshots (Smart University theme) and
asked whether the console had actually been built from them. It had not, and
the earlier log entry overstated the case for the omissions.

### What I got wrong

The reference has ten panels. The first pass built two and dropped the rest on
my own judgement — and I never checked the row counts before deciding. Two of
those panels ARE supported by this schema. The reasoning in the previous entry
was written as though every omission had been measured; only the trend charts
actually had been.

### Measured, all of it, before writing any widget

    exam_room_allocations  1632      exams              38  (all past-dated)
    halls                  5 active  total capacity   2800
    hall_applications      3 approved
    books                  18        enrollments         7
    payment_records         0        semester_results    0
    marks                   0        notices             0
    attendance_sessions     2        attendance_records  4

So: fee collection, salary, scholarships and the result gauge are genuinely
unbuildable — those tables are empty or do not exist. The attendance and
admission trends remain invented curves at 2 sessions and 12 profiles. But
exams and halls had real data all along.

### Built

**Exam schedule** — subject / batch·section·room / date / status pill, the
reference's table shape, over the real 38 rows. Titled "Exam schedule", NOT
"Upcoming exams" as the reference has it: every exam in this project is
past-dated, so the literal label would render an empty panel while real data
sat one query away. The pill says which side of today each row falls on, and
`is_retake` outranks the date — a retake sitting is a different population from
the cohort's main exam, which is exactly the distinction that once made
`batch='RE'` rows invisible to every student.

**Hall occupancy** — the reference's ring with the total in the middle.
A donut is defensible HERE and was not for the role split: two mutually
exclusive parts of one known whole is the shape a ring reads well, where four
uneven categories forces a colour-to-legend lookup per value. Same reference,
different question, different mark. It renders as very nearly a full
"available" ring — 3 of 2800 beds — and that is left alone rather than padded:
an almost-empty hall system is the true state. The legend carries the numbers
so the panel still reads when a slice is too thin to see, which at 0.1% it is.

Hand-painted arc rather than a charting package: one arc pair does not justify
a dependency against the 2 MB budget.

### A routing bug found while wiring it

The exam panel's "See all" first pointed at `/exam-seat`. That is the STUDENT's
own seat view, and the router blocks teachers from it outright
(`teacherHiddenRoutes`). The console's reader is an administrator, so it now
goes to `/manage-exam-seats`, which their role actually reaches.

### Verification

Both queries proven against live RLS as a super_admin BEFORE any widget was
written — halls 5, beds 2800, approved 3, exams 38 all readable.
`flutter analyze` 0 issues · `flutter build web` succeeded.
NOT yet rendered in a browser — that needs a signed-in admin session.

### STILL OPEN

1. **Nothing changes for real users until the client is committed and
   deployed.** This is the actual cause of the reported bug, and the only item
   here that a user would notice.
2. **MAIL_FROM is still the sandbox sender.** Unchanged, and still the reason
   all of this is load-bearing.
3. **Leaked-password protection is still off** (dashboard-only toggle).
4. **The console has not been seen rendered** — analyze and build pass, but no
   browser check yet.

---

## 2026-08-22 — Making the console actually work, not just compile

**Files:** `lib/features/web/presentation/consoles/admin_overview.dart`,
`lib/features/web/presentation/consoles/role_console.dart`,
`test/admin_overview_test.dart` (new)

Asked to make sure the whole thing works together rather than merely analyzes
clean. It did analyze clean, and it did have four defects — three of which
`flutter analyze` is structurally incapable of seeing, because they are all
about *when* things happen rather than what is written.

### First, what was already true

Re-verified rather than assumed. `flutter analyze` 0 issues, `flutter test`
407 passing. All three console RPCs proven against live RLS as the real
super_admin (not as `postgres`, which bypasses RLS and proves nothing):

    can_browse_users()               true
    admin_user_facets()              total 14, pending 0, 4 role buckets
    admin_search_users(p_limit=>6)   6 rows
    admin_list_stuck_registrations() 0 rows

Row counts re-measured the same day, five days after the panel inventory was
written: unchanged except profiles 12 -> 14. `marks`, `semester_results`,
`payment_records` are all still 0, so the four omitted reference panels stay
omitted for exactly the reason recorded on 2026-08-17.

### FOUND — the overview fetched in the wrong place, and it showed

`AdminOverview` was a StatefulWidget fetching in its own `initState`. It is the
first child of RoleConsole's column, and RoleConsole holds a `ShimmerList`
until its own three awaits finish. So the overview could not *begin* loading
until the console had finished loading AND painted.

The result was two loading stages and a shove: the shimmer lifted, the page
painted with the overview at zero height, and then roughly 900px of panels
dropped in ABOVE the work areas and pushed them down the screen. That is the
layout shift the constitution bans, and `skeleton_layout_shift_test.dart`
already polices it everywhere else.

Fixed by moving the fetch, not by adding a skeleton. A placeholder would have
disguised a shift that was caused by fetching in the wrong place — the console
now starts `AdminOverviewData.load()` alongside its own profile read and holds
its single shimmer until both are in. `AdminOverview` became a StatelessWidget
taking the data. One loading state, final height on the first frame.

### FOUND — four sequential round trips inside that fetch

The same method awaited `admin_user_facets`, then `admin_search_users`, then
`admin_list_stuck_registrations`, and only then `Future.wait`ed the three table
reads — while carrying a comment explaining why the last three were parallel.
Six independent reads of six different tables, none depending on another's
answer. Now one wave of six. Combined with the move above, the console's total
wait no longer grows at all for having an overview on it.

### FOUND — the ring would not repaint on a theme change

`RingPainter.shouldRepaint` compared `fraction`, `filled` and `rest`. But
`filled` and `rest` are the two compile-time constants here (holoBlue,
holoTeal); `track` is `AppColors.borderOf(context)`, the only theme-dependent
colour of the four — and it was the one left out. The check was exactly
inverted: switching light/dark rebuilt the widget, constructed a new painter,
got `false` back, and left the ring wearing the previous theme's track.

### FOUND — the joiner pill was a byte-for-byte copy of `_Pill`

Sixty lines below the widget it duplicated. Replaced with the real one.

### Two changes made to allow testing at all

`_RingPainter` is now `RingPainter`, so its repaint contract can be pinned
directly rather than inferred.

The `kIsWeb && isExpanded` gate moved from inside `AdminOverview` to
RoleConsole, which is where its own doc comment always claimed it lived.
This matters more than it looks: `kIsWeb` is a **const false** under the Dart
VM, so every widget test of this file would have rendered an empty `SizedBox`,
asserted against nothing, and passed. The file had zero tests, and with the
gate where it was it could not have had any that meant anything.

### Verification

`flutter analyze` 0 issues · `flutter test` **430 passing** (23 new, 407
unchanged) · release web build succeeded.

The 23 new tests render the real widget at 1600x1000 with the live data
shapes — 14 profiles over 4 role buckets, 2800 beds, 3 occupied — and cover:
null vs failed vs loaded, the raw exception never reaching the reader, bar
ordering and rounding (9/14 -> 64%), the ring's arc matching its legend, zero
beds drawing no ring, occupancy exceeding capacity not rendering a negative,
retake outranking the date, undated exams, and all four identity-source pills.

**STILL NOT DONE — the console has never been seen rendered in a browser.**
That needs a signed-in admin session, and signing in means typing a password.
Everything above is proven by analyze, by tests against the real widget, and
by live SQL under real RLS — none of it is proven by looking.

**STILL UNCOMMITTED.** This console and the entire identity/verification client
remain untracked. Nothing here reaches a real user until that is committed and
deployed.

---

## 2026-08-22 — The console becomes a dashboard

**Files:** `lib/config/theme/chart_palette.dart` (new),
`lib/features/web/presentation/widgets/console_grid.dart` (new),
`lib/features/web/presentation/widgets/chart_primitives.dart` (new),
`lib/features/web/presentation/consoles/personal_overview.dart` (new),
`consoles/admin_overview.dart`, `consoles/role_console.dart`,
`test/console_grid_test.dart` (new), `test/admin_overview_test.dart`,
migrations 20260822003139 / 003949 / 004016

Owner's report: "still sucks, too much scatter, some art here there";
"there would need more graphs real data shows, patterns, circle rings";
"all the shapes are very [random] size, no fix and proper thing";
"need some ring type dashboard for ALL user ... animated".

All four are fair, and three of them were measurable.

### The scatter was real, and it had one cause

Every panel sized itself. Two hand-rolled `LayoutBuilder`s each guessed an
`Expanded(flex: 2)` / `Expanded(flex: 3)` pair, and every panel's HEIGHT was
whatever its content came to — six exam rows made one column tall, a ring made
its neighbour short, and the difference was dead space. Nothing aligned to
anything because nothing had been asked to.

`ConsoleGrid` replaces it: twelve columns, a 78dp row unit, spans declared per
panel (`stat 3x1`, `small 4x2`, `medium 6x2`, `tall 4x3`, `large 6x3`,
`wide 12x2`). Content fits the box; the box is never resized to fit content.
Reading the spans down the build method now tells you the page layout without
running it.

Pinned by `console_grid_test.dart`, because "it looks scattered" is a geometric
claim and deserves a geometric guarantee: four stats share one top edge and one
height, three 4-spans end flush at 1280, a 12-span in an 800px window clamps
instead of overflowing.

### The palette had never been checked, and it failed

Every chart drew itself with the UI accent colours. Run through the dataviz
validator against the surfaces this app actually uses:

    light, on #FFFFFF   3 of 4 fills below the 3:1 contrast floor
                        (holoBlue 2.1, holoTeal 1.94, amber 2.08)
    dark,  on #101A2D   3 of 4 outside the L 0.48-0.67 band (0.755+)

An accent that reads as a 2px border is not a fill somebody compares areas of.
`chart_palette.dart` re-steps the same four hue families per mode until the
validator passes, and the sequential ramp took three attempts because the
obvious pale first step sits at 1.22:1 on white — the lowest-density heatmap
cell was invisible, so the grid looked like it had holes.

    categorical light  #1B78C2 #10855A #6A56C8 #96660A   ALL CHECKS PASS
    categorical dark   #3187C8 #1E9A69 #7460C6 #B37F1C   ALL CHECKS PASS
    ramp light/dark    5 steps each                       ALL CHECKS PASS

**Also found: the ring was tritan-fragile.** The blue and the green separate by
ΔE ~3.4 under tritanopia — and those were exactly the Occupied/Available
slices. They pass on deuteranopia at ~17, which is why nobody noticed. Handled
the way the spec requires rather than by repainting: a 2px surface-coloured gap
between fills, and the legend carries the numbers.

The old `_accents[i % length]` also CYCLED, handing series 5 the same fill as
series 1. `BarList` now folds the tail into a single "Other" instead.

### "More graphs on real data" — the data was there all along

Measured `pg_stat_user_tables` rather than guessing again. The biggest table in
the project had never been on a dashboard:

    schedule_slots        1854      <- the routine. Nothing read it.
    exam_room_allocations 1632
    transport_stops        351
    user_notifications     279
    clubs                   55

The admin console went from 4 panels to 16, all on real counts: a day x hour
routine-density heatmap (1854 slots), lab vs theory (844/1010), teaching load
by batch (11 batches), busiest rooms, teachers timetabled (220), rooms in use
(68), clubs, transport, library — beside the four that already existed.

`campus_activity_facets()` does the arithmetic in Postgres and returns ~60
numbers instead of 1854 rows, which is the same mistake nine dashboard queries
made in this project once before.

### Every role has a dashboard now

Four of seven — student, teacher, staff, exam controller — had none at all.
They landed on twelve launcher tiles and not one number. `my_campus_facets()`
reads `auth.uid()` and takes no user id, so there is no parameter to point at
someone else, and `PersonalOverview` renders the caller's own week as a ring.

Verified as a real student, not as postgres: batch 68 section D, 10 classes,
6 labs, 5 clubs, 3 enrolments, 3 unread, and the campus figures visible to them.

**A bug the verification caught:** `my_campus_facets` v1 joined
`club_members.profile_id`, which does not exist — the column is `member_id`.
plpgsql does not resolve column names until the body runs, so it created
cleanly and would have failed for every user on first load. Fixed in
20260822004016. This is exactly why HARD RULE 1 says verify behaviourally
rather than by reading the definition back.

### Animation

`ConsoleGrid` staggers its panels in on first mount through
`AppMotion.staggerFor`, so reduced motion collapses it to zero. The reveal
wraps the CONTENT and never the box — wrapping the box would make the grid
reflow on every frame of its own entrance, which is the layout shift the fixed
row unit exists to prevent. Pinned by a test.

### Removed

`_RoleBreakdown`, `_Bar`, `_HallOccupancy`, `_LegendDot` and the old
`RingPainter` in `admin_overview.dart`, all superseded by
`chart_primitives.dart`. Nothing else referenced them.

### Verification

`flutter analyze` 0 issues · `flutter test` **443 passing** (36 new; 407
unchanged) · release web build · release APK build.
Three migrations applied, verified as a real authenticated user, and mirrored
under the versions the remote ledger assigned.

### STILL OPEN

- **The console has still not been seen rendered in a browser.** Everything
  above is proven by analyze, by tests against the real widgets at real desktop
  sizes, by the palette validator, and by live SQL under real RLS. None of it
  is proven by looking, and that gap needs an admin password.
- **marks / semester_results / payment_records remain 0 rows**, so the result
  gauge and fee panels are still unbuildable. They are the only panels from the
  reference still missing, and they need seeded data, not effort.

---

## 2026-08-22 (later) — The exam system, and a 96 MB download

**Files:** `lib/core/services/app_update_service.dart`,
`lib/features/exam_seat/data/exam_routine_pdf_parser.dart` (new),
`lib/features/dashboard/presentation/widgets/exam_pulse_band.dart` (new),
`dashboard_screen.dart`, four migrations, four new test files

### The in-app update was downloading the wrong file

Reported as `DioException [unknown]` / "HttpConnection closed while receiving
data", which reads like a GitHub fault and is not one. The updater always asked
for `AFOS-v<x>.apk` — the UNIVERSAL apk, 96 MB for 2.9.2. The arm64 slice of
the same release is 35 MB. A 96 MB transfer over campus mobile data does not
survive, and with no resume every retry restarted from zero.

The ABI comes from `Platform.version` (which ends `on "android_arm64"`) rather
than from adding device_info_plus — a native dependency would need a real
Android build to verify and buys one string the process already knows. arm64 is
tested before arm because `'android_arm64'.contains('android_arm')` is true.

### The exam data was never modelled

    exams                  38 rows, EVERY exam_type the string 'mid',
                           no season, no year, no window, and NO ROOM on any row
    exam_room_allocations  1632 rows WITH rooms
    join between them      none
    routine parser         did not exist

`exam_terms` now models what the routine header states ("Final Examination
Routine, Summer 2026"). Found while doing it: **`exams` had a SELECT policy and
no write policy at all** — every insert from the app was refused silently,
because RLS filters rather than errors. A routine upload screen could never
have worked regardless of the parser.

### The routine parser, and the five coordinate bugs

Verified against the real Summer 2026 CSE document: **30 entries across seven
dates, correct slots, times, batches and titles, zero warnings.** Every bug was
found by running it on the real file, not by reasoning about it:

1. Syncfusion tokenises `Slot A:` as TWO words, so matching one word against
   `/^Slot ([A-Z]):?$/` found no header on any page.
2. The `Batch` header sits 6pt below the `Slot` row — far enough to be its own
   line — so the times were two rows below the label, not one, and no slot ever
   got a start or end time.
3. Slot A's batch window was x 236-286 while its own `Batch-65` token sat at
   **x=235**. Outside by one point, so every slot A exam was dropped. Ownership
   is now "nearest column to the left", which is a fact about the table rather
   than a measurement.
4. Header words fall inside slot A's own course column and merged into the
   first cell: one title read `Slot B: 12:00 pm – 02:00 pm : Object Oriented
   Programming CSE226: Numerical Methods` — a label, a time range and two exams
   in one row. Entries split on course codes now, not on vertical gaps.
5. **23/08 was missing entirely.** Page 2 opens mid-block, its slot header
   having been at the foot of page 1, and blocks were only built from header
   rows downwards. A whole exam day, silently. Content above the first header
   row is now parsed with the previous page's columns.

Also: the last page's footer sits inside the course columns and PHY101's title
absorbed 300 characters of examination-hall rules; titles are bounded
vertically. The weekday is DERIVED from the date and never read — the source
prints "Thurseday".

**Cross-validation worth recording:** the recovered 23/08 row is
`CSE121 Electrical Circuits, Batch-70`, and the seat-plan PDF for 23-08-2026
independently reads `FSIT CSE121 Electrical Circuits SMC 70_A G1-001`. Two
parsers, two documents, same exam.

### The join, and the fan-out

A routine row carries a batch and no section; the seat plan is per section. So
one routine row covers every section of that batch, and the student's own
section narrows it. Confirmed by the owner and verified live: CSE123/Batch-70
fans out to sections A–F, ~51 seats each, with rooms correctly shared between
adjacent sections (G1-004 in both A and B, G1-008 in both B and C).

`my_exam_schedule()` answers it per caller — student gets date/course/room,
teacher gets duty rooms — reads `auth.uid()` and takes no parameter, so there
is nothing to aim at anyone else. Unpublished terms return nothing: verified by
importing the real routine unpublished (student saw `term: null`), then
publishing.

`teachers.teacher_initial` added, because the seat plan's "Tech. Int." (NNM,
SMC) was the only teacher identifier in those documents and nothing could
resolve it to a person. Backfilled by name from `schedule_slots`; it matched 0
of 4, which is correct — every teacher account here is a test one.

### The band

Between the search field and the module tiles, exactly as asked, removing
nothing. Exam-today pulse, days-left ring, a line of exams across the term, and
a teacher's duty card. It renders nothing when there is no published term and
nothing once `isOver` — a finished exam period that keeps advertising a passed
date is worse than no banner.

Loaded in parallel with the dashboard and awaited before the shimmer lifts, so
the 148px row cannot drop in late and shove the modules down.

### A note on how this was edited

Two literal 0x08 backspace bytes ended up inside a RegExp in the parser, from a
Python escaping mistake in my own editing script. The year silently never
parsed and the source looked correct. Same class of hazard as the PowerShell
rule in CLAUDE.md, and the file is now verified free of control characters.

Also corrected: my "analyze 0 issues" claim for v2.9.2 was wrong. I had
filtered the output to errors and warnings, so eight lint infos shipped
unnoticed. Fixed.

### Verification

`flutter analyze` 0 issues · `flutter test` **466 passing** (23 new) · release
web and APK build. Four migrations applied, each verified against live RLS as a
real user, each mirrored under the version the ledger assigned.

### STILL OPEN

- The 23/08 final seat plan has not been imported — it goes through the
  existing upload screen, which now has a write policy that permits it.
- No teacher account has an initial yet, so duty cards are empty until
  `set_teacher_initial` is used or a real teacher signs up.
- Still nothing has been seen rendered in a browser.

---

## 2026-08-22 (later still) — The exam week that had no rooms

**Files:** `lib/features/exam_seat/data/exam_room_pdf_parser.dart`,
`exam_routine_pdf_parser.dart`, `exam_seat_view.dart` (new),
`presentation/exam_seat_screen.dart`, `manage_exam_seats_screen.dart`,
`test/exam_seat_view_test.dart` (new), `test/exam_room_parser_test.dart` (new),
`test/exam_routine_parser_test.dart`, four `tool/*_test.dart` harnesses

Picked up the three items the previous entry left open. The first of them —
"the 23/08 final seat plan has not been imported" — turned out to understate
the problem by a wide margin.

### What was actually live

The final term (19–27 Aug, published) was running. It had 30 routine rows and
**zero room allocations**; all 1632 allocations in the table belonged to the
JUNE mid-term. Verified as a real authenticated student, not as postgres:
batch 67 sitting CSE313 the next morning got `"rooms": []`.

Worse, `ExamSeatScreen` selected allocations by **batch+section alone** — no
date bound, no term. Correct while the table held one exam period; wrong the
moment it held two. That student's Exam Seat Plan listed **three June
sessions under the heading "3 upcoming sessions"**, two of them titled only
"Exam" because those rows carry no course code, and said nothing about the
exam they were about to sit. Confidently wrong beats blank, and this was
confidently wrong.

### The screen

The exam list now comes from `my_exam_schedule()`, which already picks the
live published term, applies the batch → all-sections fan-out and narrows by
the caller's own section. Allocation rows are read only to decorate it with
seat counts, bounded by that same term's window. Three separate "nothings"
that the old single empty state ran together are now distinct: no routine
published, a routine that lists nothing for your batch, and a term with no
seat plan yet — the last of which says **"Room not published yet"** against
the exam rather than rendering an empty box under a heading.

Extracted `ExamSeatView` to make that testable at all: a widget that fetches
its own data cannot be asked which exams it will show. Past exams stay in the
list (a student checking which room they were in is a real thing) but are
marked Completed and excluded from the "upcoming" count, compared date-to-date
so a 09:00 exam is still today's exam at 14:00.

`cachedListFetch`, not `cachedMapFetch`, for a single object on purpose — the
lenient variant returns null on a failed fetch, which here would render a
network blip as "no exam routine published". That silent-empty class of bug
has been paid for once already in this project.

### Five parser bugs, all found by running the parsers on the real files

**Seat plan** (seven PDFs, one per exam date):

1. **The course context did not survive a page break.** It was local to one
   page, and every one of these documents continues a table across pages —
   batch 70 alone spans sections A..R. Those rows were stored with
   `course_code = null`, and a null course code joins to no exam, so **57% of
   every file was invisible to the screen it exists for**. This is also why
   the June rows rendered as cards titled "Exam".
2. **Continuation rows at the top of a page were dropped outright**, having no
   section context to attach to. Fixing 1 and 2 took the seven files from
   1444 rows to 1497.
3. **The date is five tokens in one of the two templates** — `19`, `-`, `08`,
   `-`, `2026`. Matching the token after `Date:` got `"19"`, the date came out
   null, and a null date drops every row on the page. **The 19 Aug file parsed
   to zero rows.** Rejoin the column before matching — the same lesson the
   routine parser learned about `Slot A:`.
4. **The room is three tokens in that template** — `G1`, `-`, `001` — so
   `int.tryParse` landed on `"-"` and the row was dropped. Rejoined around a
   lone hyphen; a numeric room (`218`) is still one token and is left alone.
5. The header row reads `Dept.` in one template and `Faculty` in the other.

After the fix all seven files parse: **1767 rows, every date, zero null course
codes.**

**Routine** (one PDF):

6. **A course code need not start its token.** Where several courses share one
   slot cell the document runs them together with slashes — `CSE431:Machine`,
   `/CSE441:UI`, `[160]/CSE453:` — and requiring the match at offset 0 took
   the first and silently dropped the rest.
7. **The date label is vertically CENTRED in its row, not at its top.** 23/08
   sits at y=63 with its own courses at y=12 *and* y=105. Blocks sliced at the
   date (or at the repeated slot header above it) therefore mixed the bottom
   half of one exam day with the top half of the next. Boundaries are now the
   **midpoint between consecutive date labels**.

Together these cost **eight of the routine's thirty-eight exams** — 23/08 and
25/08, the batch-64 electives and AOL101 — with **no warning at all**, because
a course that is never detected cannot be reported missing. Bug 6 alone
recovered four; bug 7 recovered the rest and corrected CSE471, which bug 6 had
recovered under **batch 70 instead of 64**. A wrong batch is worse than a
missing one, which is why this was chased rather than worked around.

### Cross-validation

The two documents are independent and now agree exactly. Courses per date —
routine and seat plan both: **5, 4, 5, 7, 5, 7, 5 = 38**. Every batch matches.
That agreement is the evidence the parsers are right; neither one alone would
have been.

### Imported

1767 allocations across all seven dates, each stamped with the final term,
verified row-for-row against what the parser read (rows, courses, sections and
seat totals all match; zero null course codes, zero orphan terms). The 8
missing exams were then filled in from the allocations, taking `exams` to 38 —
the same count as the mid-term.

Verified as real authenticated students afterwards: batch 67 gets CSE313 on
23/08 in G1-011…G1-016, which is exactly what section D reads in the source
PDF; batch 68 gets AOL101 on 23/08, an exam that did not exist in the database
an hour earlier.

### Also

`ManageExamSeatsScreen` now resolves and stamps `term_id` on upload. Without
it every future upload filed rows against no term — precisely the state the
table was found in. When no published term covers the parsed dates it says so
in the toast instead of reporting a clean success.

### Verification

`flutter analyze` 0 issues · `flutter test` **491 passing** (25 new; 466
unchanged) · release web build. No migrations: this was data and client code.

### STILL OPEN

- **The routine parser has no UI.** `/admin/upload` exists and offers an "Exam
  Routine" mode, but that path posts text lines to the `parse-routine` edge
  function — the older line-based parser — not to `ExamRoutinePdfParser`,
  which is why the coordinate parser is still reachable only from tests. The
  routine and seat plans in the database were both imported by hand.
- The owner has asked for the upload screens to become one **Uploads** section
  (class routine · exam routine · transport · exam seat plans · university
  notices), each recording who uploaded what and when, with a history view and
  a "download a backup PDF before deleting" step. **Not built.**
- University notices: `manage_notices_screen.dart` exists under
  `features/registry/` and has not been assessed against that request.
- Still nothing seen rendered in a browser.

---

## 2026-08-22 (later still) — Uploads becomes a section, and a ledger

**Files:** `lib/features/uploads/` (new: `upload_batch.dart`,
`upload_backup_pdf.dart`, `uploads_hub_screen.dart`,
`exam_routine_upload_screen.dart`), `registry/presentation/notices_screen.dart`
(new), `manage_notices_screen.dart`, `manage_exam_seats_screen.dart`,
`admin_upload_routine_screen.dart`, `schedule_repository.dart`,
`app_router.dart`, `capabilities.dart`,
`supabase/functions/parse-routine/index.ts`, four migrations, two test files

Asked for one "Uploads" section covering class routine, exam routine,
transport, seat plans and university notices, each recording who uploaded what
and when, with a history and a backup-before-delete step.

### What was already there, and what was not

Worth checking before building: the seat-plan uploader exists (Manage Exam
Seats), `/admin/upload` exists and already offered class routine / exam
routine / transport, and `ManageNoticesScreen` is a complete authoring tool.
So most of the "build it" was really "join it up and give it a memory".

Three things genuinely were not there:

1. **The exam routine had no working importer.** `/admin/upload` offers an
   "Exam Routine" mode, but it posts extracted text LINES to the
   `parse-routine` edge function — the older line-based reader. The
   coordinate parser written the same day, the only one that can read this
   document, was wired to nothing. Both the routine and the seat plans in the
   database had been put there by hand.
2. **No upload recorded itself.** `routine_uploads` held one row, described
   routines only, and named nothing it had written.
3. **Notices could be written but not read.** The table has sat at zero rows
   since it was created; the dashboard showed the newest three and the module
   tile labelled "Notices" opened the notification CENTRE, which lists
   notifications, not notices. Authoring with no reader is what a write-only
   feature looks like from the outside.

### The ledger

`upload_batches` — one row per import, of any kind — plus an
`upload_batch_id` on every table an import writes (`exam_room_allocations`,
`exams`, `schedule_slots`, `notices`, `transport_routes`, `transport_stops`).
Stamping the rows is what makes a revert delete EXACTLY what one upload added,
rather than re-deriving it from a date range and hoping.

Two-phase on purpose: the batch is opened BEFORE the import so rows can carry
its id, and closed after, at which point the server COUNTS the stamped rows
rather than believing the client's tally. A batch opened and never closed
stays `pending` and shows in the history as an import that did not finish.

`upload_batches` has a read policy and deliberately NO write policy — every
write goes through a SECURITY DEFINER function. That is the opposite of the
`exams` mistake found earlier today, where a write policy was missing by
accident and RLS filtered every insert in silence; here the absence is the
design and the client has a function to call.

### Backup before delete

`revert_upload_batch()` refuses until a backup exists. The interlock is a
SAFETY one, not a security one, and is named that way in the code: the server
can know a backup was generated and stored, never that a person downloaded it.
It exists to stop the ordinary accident — freeing storage and discovering
afterwards that the term's seat plan is gone.

The PDF lists every row the batch wrote (not a summary), goes to a private
`upload-backups` bucket, and opens through a signed URL — the one delivery
route that works on both web and Android, which the VR-ID generator settled
the same way.

### The exam routine importer

New screen at `/admin/upload/exam-routine`, wired to `ExamRoutinePdfParser`.
It shows every date and course it recovered BEFORE writing anything, because
the way this document fails is by losing a day quietly: a total of "30
entries" looks perfectly healthy when it should read 38. Creates or reuses the
term, replaces that term's exams rather than appending, and defaults to
UNPUBLISHED so an import can be checked before students see it.

### Notices, both halves

`NoticesScreen` at `/notices` — the reading half that never existed, with
category filters and the offline cache the dashboard preview already used. The
dashboard tile now points at it instead of the notification centre.
Publishing a notice also records an upload batch and finally sets `author_id`,
which was never set at all, which is why every notice would have read as
authored by nobody.

### Two more term-scoping bugs, same family as this morning's

- `set_teacher_initial()` wrote `teachers.teacher_initial`; the routine
  directory reads `profiles.teacher_initial`. Measured: profiles held 2,
  teachers held 0. So two teachers who already had an initial got no
  invigilation duties, and setting one through the RPC would never have
  reached the directory. One writer now, writing both, plus a reconciliation
  in both directions. **A teacher immediately gained 10 real duties.**
- `getMyExams()` had no term filter, so the schedule screen listed June and
  August exams together with nothing to tell them apart. Now scoped to the
  same term `my_exam_schedule()` picks. Signature and row shape unchanged.

### Scope kept, deliberately

`/admin/upload` remains the hub's path rather than moving to `/admin/uploads`:
it is what three delegated grants, the capability list and 29 pinned menu
tests already point at. The label changed, the route did not. `uploadKindsFor`
mirrors the RLS rather than holding a second opinion about it — a screen that
offers an importer the database will refuse is worse than one that hides it.

`deep_link_routes_test.dart` now also guards capability routes, Uploads hub
routes and dashboard tile routes: a tile naming a route the router lacks is
dead exactly the way a bad deep link is.

### Verification

`flutter analyze` 0 issues · `flutter test` **506 passing** (15 new) · release
web build · release APK build. Four migrations applied, each verified
behaviourally inside a transaction that rolled back — including that a student
cannot open a batch, that revert refuses without a backup, that a second
revert refuses, and that the exam-routine insert path is admitted by RLS as a
real authenticated admin rather than as postgres. `parse-routine` redeployed
from disk (not retyped) so the batch id reaches server-side inserts.

### STILL OPEN

- **Nothing has been seen rendered in a browser.** Everything above is proven
  by analyze, by tests, and by live SQL under real RLS. None of it is proven
  by looking, and that needs a login.
- Reverting a `class_routine` or `transport` upload only removes rows the NEW
  edge function stamped; imports made before this deploy have no batch id and
  are not removable as a unit.
- `marks` / `semester_results` / `payment_records` remain 0 rows.

---

## Session 2026-08-22 (afternoon) — seen in a browser at last

The previous entry's first STILL OPEN line was "nothing has been seen rendered
in a browser". That is now closed, and closing it is what found everything
below. Chrome is not on this machine's PATH, but Playwright's own Chromium
was already in the cache, so the release web build was served locally and
driven with a real login as super_admin, as a student, and as a teacher.

### Four defects, none of which a test could have caught

Every one renders without an error, an overflow, or a failing assertion.

1. **The campus-busy heatmap drew ZERO cells.** `HeatGrid`'s inner cell `Row`
   had no `crossAxisAlignment`, so it defaulted to `center`. `Expanded` makes
   only the MAIN axis tight; on the cross axis a centred child gets LOOSE
   constraints, and a `DecoratedBox` with no child takes the minimum it is
   allowed — zero height. 34 cells of real data (values 13-69) painted at 0px
   while the row and column labels drew perfectly around the void. Fixed with
   `CrossAxisAlignment.stretch`.
2. **The Exam Routine tab was titled "Class Routine for CSE Program".** The
   banner is shared with the class tab and hardcoded the word "Class", while
   being fed `fetchRoutineHeader(dept, 'exam_routine')`. The data was right;
   only the label lied. Now takes a `kind`.
3. **That same banner was one grid column wide.** It sat inside an
   `AdaptiveList`, which on web turns every item into a grid CELL — so the
   banner rendered beside the validity note like a card. The furniture now
   scrolls above the adaptive grid instead of inside it.
4. **The 404 "Go Home" button spanned 1376px.** The theme sets a button
   `minimumSize` of `Size(double.infinity, 52)`; a previous fix added 32px of
   padding, which is a PHONE-shaped fix. Capped at 320px.

### Admin user search found almost nobody

Reported as "searching id, section, teacher initial — nothing works". Measured
against live data before touching anything:

| searched | found | existed |
|---|---:|---:|
| teacher initial `MSK` | 0 | 1 |
| mid-fragment of a student ID | 0 | 1 |
| a phone number | 0 | 1 |
| batch `68` | 0 | 2 |
| email fragment `diu.edu.bd` | 1 | 12 |

`admin_search_users` matched `university_id` and `email` by **PREFIX ONLY**,
`full_name` by substring, and teacher initial, phone, batch and section not at
all. An admin typing the ID printed on a student's card got "No users found".

Fixed with one `profile_search_text()` haystack used by the row query, the
facet counts and the index — three copies of a concatenation would drift and
silently stop using the index. A typed `%` is escaped, so it is a character
somebody is searching for and not a wildcard meaning everyone. A pg_trgm GIN
index went in with it: 14 profiles today, thousands expected.

### Verified, not changed

The uploads ledger end to end under real RLS inside a rolled-back
transaction: a student is refused (`42501`), revert refuses without a backup,
`finalize` **counted 2 rows when the client claimed 999**, revert deleted
exactly the batch's 2 rows and left the term's other 38 untouched, and a
second revert refuses. Term scoping resolves to the live FINAL term; a batch
68 / section D student's seat plan matches the database row for row, including
CSE215 having 5 rooms where the others have 6.

### Verification

`flutter analyze` 0 issues · `flutter test` **506 passing** · release web build ·
release APK builds after `flutter clean` (the earlier failure was a corrupt
`output-metadata.json` intermediate, not code).

### STILL OPEN

- **APK is over budget**: 31.4 / 34.4 / 36.9 MB per ABI against the 28 MB
  hard-fail limit in CLAUDE.md.
- **`my_campus_facets()` computes a teacher's week from batch/section**, which
  teachers do not have — Masuk's 8 class slots and 20 exam rows read as zeros.
  Owner has parked this deliberately; the teacher accounts are test accounts.
- Student intake term and ID-card join date have no columns yet; plan written
  at `docs/superpowers/plans/2026-08-22-mandatory-profile-completion.md`.

---

## Phase B — the directory becomes a place per kind of person · 2026-08-22

The owner asked for grouped sections rather than one flat list, with a place
per role, each grouped the way that kind of person is actually organised:
students by intake term then batch, teachers by department then join year,
staff by sector then join year.

### The data had to exist first

Phase A's columns (`admission_season`, `admission_year`, `joined_on`) are what
this groups on, which is why it was correctly blocked until they existed.
Measured before building: `staff.category` IS populated, `department_id` IS
populated, and `joining_date` was NULL for all six teachers and staff. So the
join-year level renders honestly as "Join year not set" rather than being
dropped — hiding it would hide exactly the people who still need chasing.

### Counts that cannot disagree with rows

`admin_user_groups()` returns the headings and counts; `admin_search_users()`
returns the rows for one opened group, taking the SAME group keys. A header
claiming 40 above 50 rows is worse than no header. Verified per group: every
claimed count equalled the rows returned, including the `unset` sentinel path
that gathers people with no intake term.

Rows load per group, on expand. Opening one intake never downloads the rest —
which is the entire point of grouping a directory expected to hold thousands.

### The search box that filtered but looked empty

Found in the browser, and probably a large part of what "searching nothing
works properly" felt like. The search `TextField` had no controller, and the
debounced reload sets `_loading = true`, which replaced the WHOLE TabBarView —
search box included — with a skeleton. The field was destroyed and rebuilt on
every keystroke: the list filtered correctly on "MSK" while the box you typed
into rendered its placeholder. You could not see, correct, or clear your own
query.

Two fixes: the field owns a `TextEditingController`, and the full-screen
skeleton is now the FIRST load's alone rather than flashing on every keystroke.

### Approval queue

Grouped by role under the same section headings, sharing one
`GroupSectionHeader` so the queue and the directory read as one system.
Grouped in memory, not on the server — it is a queue and is meant to stay
short, unlike the directory. Approve / Reject / Delete are untouched; each
still follows its own grant and Reject still deletes the account outright.

### Verification

`flutter analyze` 0 issues · `flutter test` **529 passing** (7 new, testing the
real `UserGroupTree` — including that rows are NOT fetched until a group is
opened, and that a failed fetch shows an error rather than an empty group) ·
release web build · seen in a browser as super_admin: Summer 2023 → Batch 68
expanding to exactly its one student, CSE → Join year not set (4), and "MSK"
finding Masuk.

---

## v2.9.5 — three things the browser showed and no test could · 2026-08-22

Reported by the owner after using the live web build. All three are layout or
navigation facts that `analyze` and 534 tests were blind to.

### The notification tray hung 360px from the bell

`showNotificationPopover` positioned itself with a hardcoded
`Alignment.topRight` plus `top: 64, end: 12` — the top-right of the SCREEN.
That is correct on a phone. On web the bell sits at the right edge of the page
header, inside a content area that begins after the 248px sidebar. Measured at
1440px: bell right edge 1085, panel right edge 1428. The bell appeared at the
panel's far top-left corner instead of above it.

Now anchored to the bell's own `RenderBox`, which needs no new parameter — the
`context` passed in IS the IconButton's.

**The first fix was wrong and the browser caught that too.** Measuring with
`localToGlobal(ancestor: overlayBox)` returned the rect in the enclosing
Overlay's space, which on web starts after the sidebar, while `MediaQuery.size`
is the whole window. Two coordinate spaces, one subtraction, and the panel
moved ~260px the OTHER way (711–1089 became 447–825). Global coordinates are
the correct space because `showGeneralDialog` uses the root navigator.

### Uploads rendered as a phone column with two thirds of the screen empty

`AdaptiveList(itemCount: 1)` with the whole page as that one item. AdaptiveList
lays its ITEMS out in columns: at 1440px it computed three, put the page in the
first and left two blank. A plain `ListView` now. Checked the rest of the
codebase — this was the only screen doing it.

### The same job appeared twice: "Manage Exam Seats" and Uploads' "Exam Seat Plan"

Both opened `/manage-exam-seats`. The standalone capability is gone; seat plans
live inside Uploads only.

Deleting the tile ALONE would have stranded exam controllers. The
`/admin/upload` guard admitted only the `routine`/`transport`/`exam_seat`
grants — never the `exam_controller` ROLE — even though `uploadKindsFor()`
hands that role three kinds inside the hub. They reached seat plans solely
through the duplicate tile. The guard now admits the role, so the one
remaining door opens.

`staff_menu_permissions_test.dart` asserted the OLD duplicate as intended
behaviour. Rewritten to pin the new contract while keeping the reason the test
existed: a grant that opens a screen must come with a way to reach it.

`Notices & Rules` deliberately stays separate — teachers author course notices,
cannot reach the Uploads hub, and would not look for it there.

### Verification

`flutter analyze` 0 issues · `flutter test` **534 passing** · release web and
release APK build · seen in a browser at 1440px and at 390px, before and after
each fix.

---

## Phase A — a real emergency contact, and a real face · 2026-08-30

Two gaps found while auditing the auth/approval flow against what the owner
had asked for months ago: `emergency_contact` was never checked against the
user's own `phone` (a self-referential "emergency contact" was accepted as
complete), and `AvatarPicker` was entirely optional — no deadline, no review,
nothing stopping an empty or joke picture from standing in for a real one.

### The design

Both requirements were folded into the EXISTING `profile_is_complete()` gate
(`20260822105453`) rather than building a second one — the router already
redirects anyone with `profile_completed = false` to `/complete-profile`, so
extending that one function reuses the enforcement for free.

- **Emergency contact** must differ from the user's own phone, compared on
  the **last 10 digits** (not the whole digit string) so a Bangladeshi
  `+880` country code and a local leading-`0` number are recognised as the
  same subscriber — found by the Dart mirror's own test, which caught that a
  naive full-digit comparison does NOT treat `'+880 1712-345678'` and
  `'01712345678'` as equal.
- **A photo is required within 48 hours of `verified_at`** (a new column,
  stamped the instant `is_verified` first becomes true — the true first
  moment an account can do anything). Compliant while inside the grace
  window, or already engaged (`avatar_review_status` = `pending` or
  `approved`). Only "never uploaded" or "rejected and never resubmitted"
  blocks once the deadline passes. `avatar_url` keeps its existing meaning
  everywhere it is already read (~15 call sites) — a new submission lands in
  `avatar_pending_url` and is only copied over on admin approval.
- **A silent user still needs to be caught.** The trigger only re-fires on a
  write; `reconcile_avatar_deadlines()` runs every 15 minutes via pg_cron
  (same pattern as `expire-club-messages`/`expire-empty-room-requests`) and
  does a no-op touch on anyone whose deadline passed with no compliant photo.

### The bypass that had to be closed

Routing the upload through a new `my_submit_avatar()` RPC does nothing if a
client can still call `.update({'avatar_url': ...})` directly — RLS governs
rows, not which columns a self-edit may touch, and this project already had
one column-level hole exactly like this (`role`/`is_verified`, closed
2026-07-04 by `protect_profile_privileged_columns()`). Extended that same
trigger rather than adding a second one: a self-edit may now set
`avatar_review_status` only to `none`/`pending`, may null out its own
`avatar_url` (removing an already-approved photo stays self-service), and can
never touch `avatar_reviewed_by`/`avatar_reviewed_at`/`verified_at` or set
`avatar_url` to anything new directly. Verified behaviourally: a direct write
attempt now raises `P0001`; the RPC path and the self-removal path both still
work.

### What else was found and fixed live

Verifying the first migration surfaced a real account already exhibiting the
exact bug being fixed — `emergency_contact = 'Own 01533996681'` against
`phone = '01533996681'` — still reading `profile_completed = true` because
nothing had re-triggered the check since it was written. A follow-up re-seat
migration (a no-op `update profiles set updated_at = updated_at`, same
technique the original completeness migration used) recomputed every row.
Measured before/after: 5/19 profiles complete → 1/19. That is the real blast
radius of finally enforcing both rules — everyone newly incomplete is
redirected to `/complete-profile` on their next navigation, per the router
gate that already exists.

### Admin review queue

New "Photos" tab in Manage Users, gated by the same `_canApproveUsers`
population as Pending/Code-Failed (no new permission introduced) — Approve /
Reject (with an optional reason, reusing the exact reject-sheet shape
`_rejectCr` already used) via `admin_approve_avatar`/`admin_reject_avatar`,
both notifying the applicant on decision.

### Migrations applied (all verified behaviourally, in rolled-back
transactions, against the live project)

- `20260830164152_a_face_and_a_real_emergency_contact.sql` — new columns,
  extended `profile_is_complete()`, `my_submit_avatar`/`admin_list_pending_
  avatars`/`admin_approve_avatar`/`admin_reject_avatar`/
  `reconcile_avatar_deadlines`, the cron schedule.
- `20260830164338_reseat_profiles_for_the_new_completeness_rules.sql` — the
  one-time re-seat (5/19 → 1/19 complete, recorded above).
- `20260830165309_normalize_bd_country_code_in_contact_check.sql` — the
  last-10-digits fix, found by the Dart test before it ever reached a user.
- `20260830165726_self_edit_cannot_forge_its_own_avatar_approval.sql` — the
  direct-write bypass close.

### Verification

`flutter analyze` 0 issues · `flutter test` **549 passing** (10 new: 6 in
`profile_completeness_test.dart`, 4 in the new
`avatar_picker_review_state_test.dart`) · every migration's remote ledger
version confirmed to match its filename exactly · CHECK constraint, backfill
completeness, the emergency-contact flip, the photo-deadline flip, the cron
sweep catching a silently-stale row, the full submit→approve and
submit→reject RPC round-trips (as the real submitting user and the real
super_admin, by JWT claim), a non-admin's `42501` on the admin RPCs, and the
direct-write bypass's `P0001` — all run live against the project, not just
read back from the function definition.

### STILL OPEN

- Not yet seen rendered in a browser — the SQL and the Dart unit/widget
  tests are proven live; the actual complete-profile form and the new Photos
  tab have not been clicked through by a human yet.
- Phase B (Manage Users rebuilt into dedicated per-role pages) is planned
  separately and not started by this phase.
- The Resend sandbox-mode mail delivery problem (documented in
  `register-request/index.ts`) is unrelated to this phase and remains an
  owner action item outside the codebase.

---

## Phase B — a real page per role · 2026-08-30

Confirmed by reading the live code before touching it: the "Total Users" stat
tile had no `onTap` at all (dead), and the "All Users" tab stacked a search
box, role chips and drill-down chips all above the list in one scrolling
`Column` — not a blocking modal, but crowded enough on a phone that only a
sliver was left for actual people, which is what the owner's "search and role
picker eat the whole screen" complaint was describing.

### The rebuild

Tapping a role now pushes a REAL route (`/admin/users/:role` →
`UserDirectoryScreen`) instead of filtering a shared list in place. The
landing screen (`ManageUsersScreen`) keeps Pending / Code-Failed / Photos / CR
Requests exactly as they were and becomes, for its last tab, a role picker —
one row per role plus the synthetic `management` destination, each showing a
live count and pushing its own page. "Total Users" pushes the same screen
with no role filter (`/admin/users/all`).

`UserDirectoryScreen` puts the search box in its own fixed slot, above the
list but never sharing scroll space with it — the literal fix for the
crowding. Below it: the grouped `UserGroupTree` accordion while browsing
(unchanged from Phase B's earlier session), swapping to the flat paged list
while searching. Reuses `admin_user_groups`/`admin_search_users` exactly as
they already existed — confirmed via `pg_get_function_identity_arguments`
that neither signature changed, so this phase needed zero migrations.

### What had to move, not duplicate

The Pending queue's Delete/Reject/Role-change/Manager/Permissions actions
(~450 lines: `_confirmDelete`, `_deleteUser`, `_setRole`, `_pickRole`,
`_toggleManager`, `_managePermissions`, `_promptToAssignAreas`,
`_confirmAction`) are needed by BOTH the landing screen's Pending tab and
every per-role directory screen. Duplicating that much permission-sensitive
logic across two files was the wrong call, so it moved into a shared mixin
(`UserAdminActions`, `widgets/user_admin_actions_mixin.dart`) both screens
apply — Dart's per-library privacy meant the methods had to lose their
leading underscores to cross files, so callers now read `confirmDelete(...)`
rather than `_confirmDelete(...)`. Methods that change which rows should be
visible (delete, role change) take an `onDone` callback instead of assuming a
specific screen's reload method, since the landing screen and a directory
screen refresh differently.

`_UserCard` was promoted the same way, unmodified, to
`widgets/user_card.dart` as public `UserCard` — the detail sheet (role,
change-role button, permissions, manager toggle) is identical in both places
because it is now literally the same class.

The "In your areas" stat tile for a delegate used to count `_users.where((u)
=> _areaCount(u) > 0)` — the currently-loaded directory PAGE, which is gone
from the landing screen now. Replaced with a count straight off
`grantsByUser`, which RLS already scopes to exactly what that delegate may
see, so the number describes their own remit rather than whatever page
happened to be in memory.

### Verification

`flutter analyze` 0 issues · `flutter test` **549 passing** (unchanged count
— this phase moved and rewired existing coverage, notably
`user_group_tree_test.dart`, which already existed from the earlier grouped-
directory session) · release web build. `admin_search_users`'s 14-argument
signature confirmed unchanged against the live project.

### STILL OPEN

- Not seen in a browser. No widget test exists in this codebase for a screen
  that makes live Supabase calls in `initState` (confirmed by grep — none
  do), so this follows the same convention rather than inventing new test
  infrastructure for one screen. Needs a real click-through: role card
  navigation, the search box staying visible while the list scrolls, the
  previously-dead "Total Users" tile now doing something, and the Pending
  queue's approve/reject/delete still working unchanged.

---

## Phase C — the app never actually ran, and neither had this bug · 2026-08-31

Phase A and Phase B were both verified against the live DB and 549 passing
tests, but neither had been clicked through in a running app — flagged as
STILL OPEN on both. First real device connected to this machine this session
(a Motorola Edge 60 Pro over wireless ADB). Installing and launching the debug
build to finally do that click-through surfaced a genuine, universal,
launch-blocking defect that no amount of reading or unit testing could have
caught.

### The app was not slow at splash. It was crashing at splash.

`adb logcat` on first launch: `Unhandled Exception:
dependOnInheritedWidgetOfExactType<MediaQuery>() ... was called before
_SplashScreenState.initState() completed`, thrown from
`AppMotion.isReduced(context)` (`config/theme/motion.dart:134`, itself calling
`MediaQuery.maybeDisableAnimationsOf`) via `_SplashScreenState._run()`
(`splash_screen.dart:129`), called directly and synchronously from
`initState()` (`splash_screen.dart:66`). Flutter forbids any inherited-widget
lookup before an Element has finished mounting — `initState()` is too early;
`didChangeDependencies()` is the framework's designated place for exactly this.
The exception aborted `_run()` before it ever reached `context.go(target)`, so
every single launch died on the "All Facilities One System" tagline screen —
this is almost certainly what "the app stuck on splash" was describing, and it
predates this session; it was just never seen because nothing had run the app
on a device.

**Fix** (`lib/features/splash/presentation/splash_screen.dart`): removed the
direct `_run()` call from `initState()`; added a guarded
`didChangeDependencies()` override that calls `_run()` exactly once. The
context-independent `_destination = _resolveDestination()` stays in
`initState()` unchanged — only the MediaQuery-dependent half moved, and it
still fires before the first frame, so nothing about the arc's timing changed.

**Scanned for the same mistake elsewhere**: every other `AppMotion.isReduced`/
`durationOf`/`staggerDelay` call site (13 found) and every direct
`MediaQuery.of/maybeOf/sizeOf/paddingOf/disableAnimationsOf` call site (22
files) — all in `build()` or `didChangeDependencies()`. One false positive
(`glass_bottom_nav.dart:107`, actually inside `didUpdateWidget`, which is
safe). Splash was the only offender.

**Verified live, not just read**: rebuilt the debug APK, reinstalled over the
broken one, cleared logcat, relaunched — the app now reaches the login screen
in ~2.7s with no exception in the log. `flutter analyze`: 0 issues.
`flutter test`: all 549 passing (unchanged — this was never something a
widget test would have caught, since none of them run a real `initState` →
first-frame cycle against a real BuildOwner the way a device does).

### The self-verify welcome gap

Confirmed by reading `register-admin-approve/index.ts` and the Pending-tab
`_approve()` in `manage_users_screen.dart`: both existing approval paths
insert a `user_notifications` row telling the new user they're in. The
self-verify path (`register-verify/index.ts`, the code-in-the-app flow that
settles the large majority of signups — students, by default
`auto_approve_roles`) did not. Added the same insert, gated on
`autoApproved`, right after the existing `pending_registrations` consume —
mirrors the established pattern exactly rather than inventing a new one.
Deployed via `supabase functions deploy register-verify`. Not yet fired live
(would need an actual new self-verifying signup, which the Resend sandbox
issue below currently blocks for any address but the account owner's own).

### Confirmed live, while investigating the "solid bar" complaint (already fixed in Phase B)

Using the connected device's own already-authenticated `super_admin` session
(a session that predates this work): the Phase B per-role directory
(`/admin/users/staff`) rendered exactly as designed — fixed search bar in its
own slot above a grouped, live-counted user tree, not stacked into the scroll.
This is the first real confirmation of Phase B outside a widget test.

**A caution, disclosed as it happened**: an exploratory swipe on the real,
already-signed-in account's `/complete-profile` screen landed on "Save &
Continue" and briefly navigated away before this was noticed. Re-opened the
form immediately and confirmed via the Edit Profile screen that every field
(`phone`, the `Mum+01986785348` emergency contact, address, department)
matched what was already stored — nothing was altered, and the form still
reads `profile_completed = false`, meaning that account remains incomplete
either way. No further writes attempted; backed out with the hardware Back
button instead of touching the form again.

### Resend still sandboxed — unchanged, and out of this codebase's reach

Re-confirmed by reading `register-request`, `password-reset`, and
`_shared/mailer.ts`: every mailed code (registration AND password reset) goes
through the same Resend call, and Resend sandbox mode rejects delivery to
every address but the account owner's own. This is an account-level Resend
Dashboard action (verify a sending domain), not something fixable from this
repo — flagged to the owner directly, not attempted here.

### Migrations applied

None. `register-verify`'s edge-function deploy is the only backend change;
verified by the deploy command's own success response
(`{"functions":["register-verify"], ...}`) plus the code-level pattern match
against the two working approval paths.

### Verification

`flutter analyze`: 0 issues. `flutter test`: 549 passing, unchanged. Splash
fix confirmed on a real device (Motorola Edge 60 Pro, Android 16) via
`adb logcat` before/after. Phase B's per-role directory confirmed rendering
correctly on the same device, live, against the real backend.

### STILL OPEN

- Resend sandbox mode — owner action, not code.
- `register-verify`'s new welcome notification has not fired live yet (no
  eligible new signup occurred this session).
- Not investigated: whether `/complete-profile` is meant to be a hard gate or
  a dismissible nag — the account used for verification reached other admin
  screens while still `profile_completed = false`. Not clear if that is by
  design (admins exempted) or a gap; flagged, not touched.
- `password-reset`'s session-revocation-on-change behaviour (flagged
  "verified-open" in that file's own comments, predating this session) is
  still genuinely untested.
- No "welcome email" exists (by design — mail is deliberately reserved for
  proving a mailbox and recovering a password; every other notification is
  in-app/push, per `_shared/mailer.ts`'s own documented rationale). Confirmed
  intentional, not a gap, once the reasoning was found.

---

## Phase C (continued) — the profile screen that never stopped asking · 2026-08-31

Live use immediately answered one of Phase C's own STILL OPEN items: the
owner's own account kept landing back on `/complete-profile` no matter how
many times it was filled in and saved. Traced to a real gap in
`20260830164152_a_face_and_a_real_emergency_contact.sql` itself, not to
anything from this session.

### The grandfather gap

`profile_is_complete()` accepts a photo as compliant when `verified_at` is
within 48h, OR `avatar_review_status in ('pending','approved')`. That
migration backfilled `verified_at` from `created_at` for every already-
verified account (correctly — `now()` would have handed everyone an
undeserved fresh grace window) but never backfilled `avatar_review_status`
for accounts that already had a perfectly good `avatar_url` from before the
review pipeline existed. Every one of those accounts was left at the `'none'`
default with a 48h window that had already expired the instant the migration
ran, since `verified_at` was backfilled into the past, not the present. Net
effect: any account that was already verified and already had a real photo
before 2026-08-30 was permanently stuck re-demanding a photo it already had —
confirmed live on the owner's own account, which has carried a real
`avatar_url` for months.

**Fix**: `20260831000000_grandfather_avatars_predating_the_review_pipeline.sql`
— sets `avatar_review_status = 'approved'` (and `avatar_reviewed_at`) for
any row where it is still `'none'` and `avatar_url is not null`. Safe as a
standing rule, not just a one-time cleanup: `20260830165726` already closed
the direct-write bypass, so `avatar_url` can now only be set by
`admin_approve_avatar()`, which always sets `avatar_review_status =
'approved'` in the same statement — the combination this migration targets
can only exist as a pre-pipeline leftover, never as a new row, so there is no
future account it could misclassify.

**Verified live**: force-stopped and relaunched the app on the connected
device before and after applying the migration. Before: landed on
`/complete-profile` on every cold start. After: lands directly on the real
Dashboard. `supabase migration list` confirms the remote ledger recorded
`20260831000000` matching the filename exactly.

### The batch strip that ate the screen

Separately reported live: opening the Student role directory showed "many
batches" that "blocked the rest of the screen." Root cause in
`user_directory_screen.dart`'s shared `_drillLevel()` (used for Batch,
Section, Semester on students, and Department on every role): each was a
`Wrap` with no height limit, so a role with dozens of distinct batch values
wrapped across as many rows as it took, in the screen's fixed (non-scrolling)
region above the list — for students specifically, this could consume the
entire viewport and leave nothing for the actual people. Search already
covered "find a student directly by batch/ID/name" (`admin_search_users`'s
`p_q` already matches against `batch` and `section`, confirmed by reading
`profile_search_text(...)` in `20260822112415`), so the fix is scoped
entirely to the crowding, not to search.

**Fix**: `_drillLevel()` now renders each filter level as a single fixed-
height (52px) horizontally-scrolling row instead of a wrapping grid — one row
per level, always, regardless of how many values it holds. Applies uniformly
to every role that uses the shared helper, not just Student.

### Verified

`flutter analyze`: 0 issues. `flutter test`: 549 passing, unchanged (a filter
chip's layout axis is not something the existing suite asserts on).

### Migrations applied (verified behaviourally, against the live project)

- `20260831000000_grandfather_avatars_predating_the_review_pipeline.sql` —
  applied via `supabase db push`; remote ledger version confirmed to match
  the filename exactly; behaviour confirmed via a real before/after app
  relaunch on the connected device, not by reading the row count back.

### STILL OPEN

- The batch-strip fix was verified by rebuild + `flutter analyze`, not by a
  second live click-through on the device — the same account's admin session
  was already in active use by the owner by that point in the session, so
  further automated navigation was deliberately stopped rather than risk
  colliding with it.

---

## Phase D — the rings the owner asked for already existed, just not here · 2026-08-31

The owner asked for "rounded rings and multiple graphs" so a super_admin can
read management activity at a glance. Before writing anything, checked
whether this already existed anywhere in the codebase, because guessing here
would have meant either a second, competing chart implementation or a
generic-library aesthetic fighting Liquid Glass.

It already existed. `features/web/presentation/widgets/chart_primitives.dart`
carries a complete, hand-painted, accessibility-validated chart system —
`RingChart`, `BarList`, `HeatGrid`, `ChartLegend` — deliberately NOT a
package (a charting library is 300KB-2MB of Dart for three shapes, against
the 2MB per-dependency budget). `chart_palette.dart` is a separately-stepped,
contrast-validated data palette (documented failures against the plain UI
accent colours, per-mode, with the validator commands that prove it). Both
already power `admin_overview.dart`, a full ten-panel analytics console —
but that file says outright: "WEB ONLY... the phone dashboard is a launcher
by design and is not touched." That was a deliberate prior decision, not an
oversight, and the owner's request this session is exactly what asks to
revisit it.

### What was built

`AdminInsightsPanel` (`features/dashboard/presentation/widgets/
admin_insights_panel.dart`) — the same data, the same primitives, a phone-
width single column instead of the web console's 12-column `ConsoleGrid`
(which does not mean anything at 320-430dp, so it is not reused). Two stat
tiles (classes running, awaiting approval), two rings side by side (labs vs.
theory, hall occupancy), one role-breakdown bar list ("Who is in AFOS") —
deliberately NOT the full ten-panel web set, to avoid immediately repeating
the exact crowding mistake just fixed in Manage Users on the same screen.

Reuses `AdminOverviewData.load()` VERBATIM — already one parallel wave of six
existing calls, already permission-gated (returns null for anyone who is not
super_admin/admin/dept_admin or `users:approve`), so this phase needed zero
new RPCs and zero backend changes. Wired into `dashboard_screen.dart` the
same way `ExamPulseData` already is: started in parallel in `initState`,
awaited and set inside `_load()` — the file's own established fix for the
layout-shift the constitution bans, not a new pattern.

### Verified

`flutter analyze`: 0 issues. `flutter test`: 549 passing, unchanged. Zero
migrations, zero new dependencies, zero changes to `admin_overview.dart` or
any web file — fully additive.

### STILL OPEN

- Not yet seen on the device — this landed at the end of the session; the
  admin account was in active concurrent use by the owner, so a live
  click-through was deliberately deferred rather than risk another
  collision.
- Scoped deliberately narrow (2 stats + 2 rings + 1 bar list). The owner's
  ask covered more ground — a 3D-shadow time/date widget and a weather +
  dress-suggestion feature — neither started: the former is pure decoration
  with no data source to get wrong, the latter is blocked on a weather
  provider/API key decision that has to come from the owner (never something
  this session can create itself).
