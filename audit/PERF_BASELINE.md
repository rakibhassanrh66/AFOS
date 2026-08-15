# PERF_BASELINE — measured, not estimated

Device: **motorola edge 60 pro, Android 16 (API 36), 1220x2712 @ 450dpi**, over
wireless ADB. Profile build unless stated. Every number here came off that
device or off a real build artifact; nothing is inferred from a rule of thumb.

---

## 1. Startup — PASSES, with 1.1s of headroom

From `flutter run --profile --trace-startup` (`build/start_up_info.json`):

| metric | measured |
|---|---:|
| `timeToFrameworkInitMicros` | **271 ms** |
| `timeToFirstFrameMicros` | **499 ms** |
| `timeToFirstFrameRasterizedMicros` | **664 ms** |

`adb shell am start -W`, cold, four runs: **1065 / 1049 / 1027 ms** (and 984 ms
warm). That figure includes Android's own activity-launch overhead, which the
Flutter timings above exclude.

**Budget: < 1800 ms. Result: PASS at 664 ms**, and this is a *profile* build,
which carries tracing overhead a release build does not.

One structural improvement contributed here and is worth naming: the splash used
to resolve the session, the biometric check and the last route only *after* its
~1.85 s animation finished, so that latency was added to the launch instead of
hidden by it. It now resolves in parallel from `initState`.

---

## 2. APK size — FAILS. And here is exactly where the bytes are.

`flutter build apk --split-per-abi --release`:

| ABI | before this phase | after | budget |
|---|---:|---:|---:|
| `armeabi-v7a` | 31.5 MB | **31.0 MB** | 28 MB |
| `arm64-v8a` | 34.6 MB | **34.1 MB** | 28 MB |
| `x86_64` | 37.1 MB | **36.6 MB** | 28 MB |

**arm64 is 6.1 MB over.** Unzipping it gives the honest breakdown:

| entry | size | what it is | reducible? |
|---|---:|---|---|
| `lib/arm64-v8a/libapp.so` | **13.31 MB** | our own Dart, AOT-compiled | only by deleting features |
| `lib/arm64-v8a/libflutter.so` | **11.05 MB** | the Flutter engine | **no** — fixed cost |
| `classes.dex` | 5.21 MB | Java/Kotlin from plugins | marginally, via R8 tuning |
| `lib/arm64-v8a/libbarhopper_v3.so` | **4.72 MB** | Google ML Kit barcode native lib, from `mobile_scanner` | **yes — see below** |
| `assets/mlkit_barcode_models/*.tflite` | 0.83 MB | ML Kit barcode models | yes, same change |
| `assets/flutter_assets/.../diu_logo.png` | 0.69 MB | the DIU logo | **yes — see below** |

### The two actionable items, neither of which I took unilaterally

1. **`mobile_scanner`'s bundled ML Kit costs ~5.5 MB** (4.72 MB native +
   0.83 MB models) and exists to serve **one tab** — VR-ID → Scan. The package
   offers a Google Play Services–backed variant that downloads the barcode model
   on demand instead of bundling it. That single change is worth roughly 5.5 MB,
   which would take arm64 from 34.1 to ~28.6 MB — essentially the whole gap.
   **Not done here** because it makes scanning depend on Play Services being
   present and on a first-use download, which is a product decision about how
   the VR-ID scanner behaves, not a redesign one.

2. **`diu_logo.png` is 702 KB at 1086x1196** and is rendered at 88px, 52px and
   inside a small badge. This phase added `cacheWidth` at all three sites, which
   fixed the **memory** cost (~5.0 MB of ARGB per decode → ~0.3 MB). The **file**
   is still 702 KB in the APK. Re-exporting it at, say, 512px would save ~0.6 MB.
   **Not done here** because replacing a brand asset is the owner's call, not a
   silent optimisation.

### What this phase did fix, measured

- **`app_icon_source.png` was shipping in the APK for nothing.** A 1024x1024,
  481 KB PNG read only by `flutter_launcher_icons` at build time, bundled as a
  runtime asset because `pubspec.yaml` declared the whole `assets/images/`
  directory. Now listed file-by-file. **−0.5 MB on every ABI**, and it was pure
  dead weight.

---

## 3. Web payload — FAILS, and by arithmetic rather than opinion

Gzipped, from `build/web`:

| file | raw | gzip |
|---|---:|---:|
| `main.dart.js` | 5.58 MB | **1.64 MB** |
| `canvaskit/canvaskit.wasm` | 6.89 MB | **2.77 MB** |
| `canvaskit/chromium/canvaskit.wasm` | 5.49 MB | 2.08 MB |

**~3.7–4.4 MB before first paint.** Budget is FCP < 1800 ms on 4G. No 4G link
delivers 4 MB in 1.8 s, so this misses regardless of anything in `lib/`.

**Not browser-verified, and that is a limitation rather than a claim**: Chrome is
not on PATH on this machine (already documented in CLAUDE.md), Playwright's
Chrome is not installed, and the browser extension is not connected. The payload
figures are real; the FCP that follows from them is inferred.

The lever is the renderer — CanvasKit versus the lighter HTML path, or deferring
the wasm — which changes how the app *looks* on web. Flagged, not taken.

---

## 4. Runtime hygiene — audited, and mostly already correct

| check | result |
|---|---|
| Realtime subscription leaks | **None.** All 13 screens that `.subscribe()` cancel in `dispose()`; the two thinnest (`pending_approval`, `club_chat`) were read line-by-line to confirm. |
| `shrinkWrap: true` on unbounded lists | **None.** All 6 sites bounded — by a query `.limit(20)`, a `ConstrainedBox`, a `Flexible`, or a fixed child count. |
| Images without a decode cap | **Fixed.** All 6 `CachedNetworkImage` sites carry `memCacheWidth`; the 3 `Image.asset` logo sites now carry `cacheWidth`. |
| `setState` after `await` with no `mounted` | **None.** 18/18 register sites closed. |
| Route polyline cost | A snapped route is ~2,000 points; now Douglas–Peucker simplified per zoom level rather than drawn in full at every scale. |

## 5. Deliberately NOT done

**No speculative `const` sprinkling, and no `RepaintBoundary` shuffling.** The
doctrine requires a named rebuild that was removed or a measured frame that got
faster. Cold start passes with 1.1 s of headroom and no jank was observed while
walking the app in profile mode, so there is no measured frame problem to point
at — and "optimising" without one is how a `RepaintBoundary` that was doing real
work gets deleted.

If a specific screen ever *feels* slow, the honest next step is a timeline
capture of that screen, not a pass over all 62.
