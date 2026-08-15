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
