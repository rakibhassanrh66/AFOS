# RELEASE_NOTES — AFOS redesign

Branch series `redesign/*`, 2026-08-15. Phases 0–9 of the redesign doctrine.

## Verification, at the gate

| check | result |
|---|---|
| `flutter analyze` | **0 issues** (baseline was 0 — no regression) |
| `flutter test` | **335 passing** (baseline 282, +53) |
| `flutter build apk --split-per-abi --release` | succeeds |
| `flutter build web` | succeeds |
| APK signature | permanent cert `2f49802b7533aa2f193b30de86edd7f124c3ebbf0e6196fb0c05ca614a03623f` |
| Schema / RLS / auth / repository contracts changed | **zero lines** |

## Against the Phase 0 baseline

| metric | Phase 0 | now |
|---|---:|---:|
| Emoji in UI copy | 52 | **0** (3 doc comments quote what was removed) |
| Hardcoded `Color(0x..)` outside theme | 21 | **2**, both in comments |
| Raw `Duration(milliseconds:)` | 66 | **26** (7 are the token file itself) |
| `EdgeInsetsDirectional` (RTL) | **0** | **240** |
| Reduced-motion references | 9 | **122** |
| Haptic call sites | 3 | **102** |
| Symmetric card-tier radii | 21 | **0** |
| Screens with an empty state | 34 | **50 / 62** |
| Tests | 282 | **335** |

## Against the performance budget

| budget | result |
|---|---|
| Android cold start < 1800 ms | **664 ms** to first frame rasterized — **PASS** |
| Frame budget, raster/UI < 8 ms | No jank observed in profile mode; **no timeline capture per screen** — partially verified |
| APK per-ABI < 28 MB | **34.1 MB** arm64 — **FAIL, 6.1 MB over** |
| Web FCP < 1800 ms / TTI < 2800 ms | ~4 MB gzipped before first paint — **FAIL by arithmetic**, not browser-verified |
| No new dependency over 2 MB | **PASS** — no dependency added in any phase |

The two failures are located precisely, not estimated: see `PERF_BASELINE.md`.
`mobile_scanner`'s bundled ML Kit is 5.5 MB of the APK and serves one tab; its
Play-Services variant would close nearly the entire gap. That is a product
decision about how the VR-ID scanner behaves, so it is flagged, not taken.

## Awaiting your decision

`db/proposed/001_route_geometry_cache.sql` — **unapplied**. Adds three columns to
`transport_routes` so road geometry is fetched once for the university instead of
once per device, and so the app stops depending on a third-party routing service
at runtime.

## Honestly unfinished

1. **Android vs web side-by-side** — no browser on this machine.
2. **Teacher / staff / dept_admin / exam_controller screens never opened** by a
   role that can reach them.
3. **The new map line, on screen** — unit-tested, and a live OSRM call returns a
   correct 21 km Dhaka route, but nobody has looked at it.
4. **The command palette, in a browser** — ranking is tested, the APK was measured
   to prove it does not ship to Android; the keys have not been pressed.
5. **APK size and web payload** over budget, as above.
6. **P2-04** — 33 screens query Supabase inline. Deliberate, documented in
   `CONTRACT_MAP.md` with the conditions to revisit.
