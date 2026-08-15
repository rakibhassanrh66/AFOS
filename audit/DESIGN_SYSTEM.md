# DESIGN_SYSTEM — the token layer

Phase 1 output, 2026-08-15. Everything Phase 2 consumes lives here.

**This phase added scales, it did not replace the palette.** Liquid Glass stays
(decided 2026-08-15). What was missing was never the colours — it was the four
systems below, none of which existed: a motion ladder, a spacing scale, a light
source, and a numeric type role.

---

## 1. Motion — `lib/config/theme/motion.dart`

Before: two constants (`motionFast` 200ms, `motionStandard` 280ms) and **66 raw
`Duration(milliseconds:)` literals**. Nothing encoded mass, so a 40px chip and a
full-screen sheet moved at the same speed.

| Token | Duration | Spring | Use |
|---|---:|---|---|
| `AppMotion.instant` | 90ms | — | press state, ripple, toggle |
| `AppMotion.tight` | 160ms | — | chip, badge, icon swap |
| `AppMotion.base` | 240ms | `springBase` (380/30) | card expand, tab switch |
| `AppMotion.slow` | 380ms | `springSlow` (260/26) | sheet, dialog, page push |
| `AppMotion.hero` | 620ms | `springHero` (180/22) | splash → home, shared element |
| `AppMotion.stagger` | 40ms/item | — | list entry, **capped at 6 items** |

Curves: `standard` (easeOutCubic), `exit` (easeInCubic), `inOut` (easeInOutCubic).
Press: `pressScale` 0.97, `pressDuration` = `instant`.

**Read every duration through `AppMotion.durationOf(context, …)`.** Reading the
constants directly is a bug — that is what makes reduced-motion work. The audit
found 9 `disableAnimations` references against ~66 durations, which is why the
setting currently does almost nothing.

### The legacy constants now alias this ladder

`LiquidGlass.motionFast/motionStandard/pressDuration` no longer *define*
anything; they point at rungs, so the app has one motion system instead of two.
The re-basing, stated because it is a real change in feel:

| constant | was | now |
|---|---:|---|
| `motionFast` | 200ms | `tight` 160ms |
| `motionStandard` | 280ms | `base` 240ms |
| `pressDuration` | 120ms | `instant` 90ms |
| `motionCurve`, `pressScale`, `entranceScaleFrom` | — | identical, no change |

**Deliberately deferred to Phase 4:** `motionStandard` is used both for small
movement (tab indicator, card fades) *and* for every page route and sheet. The
ladder says those are different rungs — `base` vs `slow`. Retiming navigation
from 280ms to 380ms is a 36% slowdown that has to be felt on a device, not
asserted in a token file. Page routes and sheets follow `base` today, exactly as
before.

---

## 2. Depth — `lib/config/theme/depth.dart`

One light source: **top-left, 20° above horizon**, forever.

Before: shadows were hand-written per widget (`blurRadius: 18, offset: Offset(0, 6)`
in one file, `8 / Offset(0, 3)` in the next) and **every one dropped straight
down**. A scene lit from directly overhead has no direction, so nothing read as
*above* anything — depth came out as blur radius, which the constitution bans.

| Level | Height | Shadow | Radius | Use |
|---:|---:|---|---|---|
| 0 | — | none | 8 (cut) | flush with parent |
| 1 | 2 | dy 2, dx 0.8 | 14 control | list row, control |
| 2 | 5 | dy 5, dx 2 + bloom | 22 card | card |
| 3 | 12 | dy 12, dx 4.8 + bloom | 28 sheet | sheet, dialog |
| 4 | 22 | dy 22, dx 8.8 + bloom | 28 sheet | floating / modal |

Three rules the tests enforce:
- **Shadows fall down AND right.** The horizontal offset is what sells the light.
- **Higher = longer and softer and *fainter*.** Increasing opacity with height is
  what produces muddy UI.
- **The brand ambient bloom starts at level 2**, so list rows do not glow.

`AppDepth.surface(context, level:)` returns colour + radius + rim + shadow in one
call. `AppDepth.rim()` adds the lit top-left edge — a raised surface needs both
shadow and rim, or it reads as a cut-out rather than a panel.

Radius routes through `LiquidGlass.signatureRadius`, so the AFOS silhouette
(three corners large, top-right cut to 8) survives at every level.

---

## 3. Spacing — `lib/config/theme/spacing.dart`

Before: no scale existed. The same relationship was 10 in one file, 11 in
another, 14 in a third.

`4 · 8 · 12 · 16 · 24 · 32 · 48` — roughly geometric, because perceived
difference is ratio-based (4→8 reads; 44→48 is invisible).

- `AppSpace.xs … xxxl`, plus `gapMd` / `vGapLg` const `SizedBox`es so gaps are
  owned by layout rather than by per-child margins (which collapse or double).
- `AppSpace.screenH` — one screen-edge padding, so every screen's content aligns
  to the same vertical line.
- `AppSpace.minTouchTarget` = 48. The audit found map stop markers painted at
  14px acting as their own tap target.
- `AppSpace.isOnScale(v)` — used by the test so an off-scale value fails CI.

---

## 4. Typography — the third role

Existing: DM Sans (display/body) + JetBrains Mono. Unchanged.

Added: **tabular numeric**, because the audit found **zero** uses of
`FontFeature.tabularFigures()` in 188 files. DM Sans ships proportional figures,
so a `1` is narrower than a `0`, and every number that changes in place visibly
jitters:

- the transport "next bus in 9m" → "10m" countdown
- CGPA/SGPA as marks land
- live class-status timers
- seat numbers, student IDs and grade columns, which must align down a column

`AppTextStyles.numericLarge / numericMedium / numericSmall` — same family, same
sizes as their prose counterparts, so swapping a `Text` changes alignment and
nothing else. Also carries `slashedZero` so `0` and `O` are distinguishable on an
ID. **This is a rendering defect fix, not a style preference.**

Prose styles deliberately keep proportional figures — inside a sentence that is
correct.

---

## 5. Haptics — `lib/core/haptics/app_haptics.dart`

Before: **3** `HapticFeedback` calls across 62 screens, answering to nothing.

| Call | Feel | Means |
|---|---|---|
| `AppHaptics.selection()` | selectionClick | a discrete choice landed |
| `AppHaptics.success()` | mediumImpact | something irreversible completed |
| `AppHaptics.warning()` | heavyImpact | destructive confirm, or refused |
| `AppHaptics.threshold()` | selectionClick | a drag will snap if released |

**Fires on COMMIT, never on press.** A press already has a visual answer (0.97
scale); buzzing on touch-down also fires when the user slides off to cancel —
confirming something that never happened.

No-ops on web (no haptics API) and when `AppHaptics.enabled` is false. That
notifier is per-session for now; binding it to `user_settings` needs a repository
write, which is outside Phase 1's scope.

---

## Verification

- `flutter analyze` — 0 issues
- `flutter test` — **302 passing** (282 before, +20 in `test/design_system_test.dart`)
- `flutter build web` — succeeds
- Scope gate: `git status` shows **zero** screens, repositories, models or blocs
  touched. Only `lib/config/theme/**`, `lib/core/haptics/**` and one test file.

## What Phase 2 must do with this

Migrating a screen means replacing its raw values with these tokens — not adding
tokens alongside the old numbers. A screen is done when it contains no
`Duration(milliseconds:`, no `Color(0x`, no off-scale `EdgeInsets`, and reads its
durations through `AppMotion.durationOf`.
