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
