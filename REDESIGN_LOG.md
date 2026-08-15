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

**Next:** Phase 2 batch 1 — migrate 3 screens. Suggested first batch, chosen as
the highest slop-per-screen from `UI_INVENTORY.md`:
`dashboard_screen.dart` (slop 24), `library_screen.dart` (19),
`clubs_screen.dart` (15). Fresh session, branch `redesign/p2-batch1`.

---
