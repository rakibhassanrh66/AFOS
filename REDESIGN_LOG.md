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
