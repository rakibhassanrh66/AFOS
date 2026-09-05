import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';

/// How much this particular phone can actually afford to draw.
///
/// ---------------------------------------------------------------------------
/// THE PROBLEM THIS EXISTS FOR, IN THE OWNER'S WORDS
///
/// "i used a lower end phone and it suck in every way lag feel ... but
/// perfectly works in newer phone."
///
/// That is the signature of an app with ONE quality setting, tuned on the
/// fastest device in the room. Everything AFOS draws is unconditional: Liquid
/// Glass composes a Gaussian blur with a saturation matrix on every frame the
/// shell is visible, skeleton loaders run a `ShaderMask` sweep per row while
/// data is in flight, and `bootstrap()` opted every Android device into its
/// panel's highest refresh rate. On a flagship all of that is free. On an
/// entry-level phone each one is a real cost, and they land together.
///
/// `audit/PERF_BASELINE.md` records the measurements that shaped this app —
/// every one of them taken on a "motorola edge 60 pro, Android 16". The budget
/// was never tested on the hardware that was failing it.
///
/// ---------------------------------------------------------------------------
/// WHY THIS MEASURES INSTEAD OF ASKING
///
/// There is no reliable way to ask Android "are you slow". SoC model strings
/// are a maintenance treadmill and wrong the moment a new chip ships;
/// RAM and core count correlate badly with GPU fill rate, which is what blur
/// actually costs. `MediaQuery.devicePixelRatio` says nothing about throughput.
///
/// So this watches what the device is ACTUALLY achieving, through
/// [SchedulerBinding.addTimingsCallback] — the same data `flutter run --profile`
/// reports, available in release builds at no cost. A phone that cannot hold a
/// 60Hz budget while doing ordinary work is slow, whatever it is called.
///
/// ---------------------------------------------------------------------------
/// THE HIGH-REFRESH TRAP, which is the specific bug here
///
/// `bootstrap()` called `FlutterDisplayMode.setHighRefreshRate()` for every
/// Android device, unconditionally. On a flagship that is the right call. On a
/// budget phone with a 90Hz panel — an extremely common combination in this
/// price bracket, and the exact device the complaint came from — it **halves
/// the frame budget from 16.6ms to 11.1ms** while leaving the GPU exactly as
/// slow as it was. Opting into a higher refresh rate a device cannot sustain
/// does not make it smoother; it converts frames that would have been on time
/// into frames that are late, which is felt as stutter rather than as a lower
/// frame rate.
///
/// So the opt-in stays — it is genuinely better on capable hardware — but it is
/// now REVERSIBLE. If the device turns out to be missing the budget it just
/// signed up for, [_backOffRefreshRate] drops it back down.
enum PerfTier {
  /// Not enough frames observed yet. Treated as [high] so a capable device is
  /// never penalised for the first second of its life.
  unknown,

  /// Comfortably holding its frame budget. Full visual quality.
  high,

  /// Missing frames often enough that a person feels it. Expensive optional
  /// effects should stand down.
  low,
}

class DeviceProfile {
  DeviceProfile._();
  static final DeviceProfile instance = DeviceProfile._();

  /// The current verdict. A [ValueNotifier] so surfaces can rebuild the moment
  /// the tier is decided, rather than being stuck with whatever was true when
  /// they first built.
  final ValueNotifier<PerfTier> tier = ValueNotifier(PerfTier.unknown);

  /// Convenience for the common read. [PerfTier.unknown] is deliberately NOT
  /// low: an undecided device gets full quality.
  bool get isLowEnd => tier.value == PerfTier.low;

  // ------------------------------------------------------------ the thresholds

  /// Frames to ignore before sampling starts.
  ///
  /// The first frames of any app are slow on every device — shader warm-up,
  /// first layout, image decodes, the route transition off the splash. Judging
  /// a phone on those would classify a flagship as low-end.
  static const int _warmupFrames = 60;

  /// How many frames to weigh before deciding.
  static const int _sampleSize = 180;

  /// The 60Hz budget. A device that cannot hold THIS while doing ordinary work
  /// is slow by any definition, regardless of what its panel claims.
  static const Duration _budget60 = Duration(microseconds: 16667);

  /// Share of sampled frames allowed to miss [_budget60] before the device is
  /// called low-end. Not zero: a few late frames are normal on every device
  /// (a GC pause, a decode landing, the OS scheduling something else).
  static const double _missRatioForLow = 0.20;

  /// Share allowed to miss the HIGH-refresh budget before the refresh-rate
  /// opt-in is withdrawn. Lower bar than [_missRatioForLow], because backing
  /// off to 60Hz is cheap and reversible whereas dropping visual quality is a
  /// visible change.
  static const double _missRatioForBackOff = 0.15;

  int _seen = 0;
  int _sampled = 0;
  int _missed60 = 0;
  int _missedDisplay = 0;
  bool _decided = false;
  bool _backedOff = false;
  bool _started = false;

  /// Whether a real frame callback is attached.
  ///
  /// Tracked separately from [_started] so the detach below can never touch
  /// `SchedulerBinding.instance` when nothing was ever attached — which is both
  /// wrong on its own terms and, under `flutter test`, an outright throw
  /// ("the instance getter is only available once that binding has been
  /// initialized"). The classifier is pure arithmetic and must stay callable
  /// without a binding.
  bool _attached = false;

  /// The budget the device is actually being asked to hit, from the live
  /// display mode. Falls back to 60Hz when unknown.
  Duration _displayBudget = _budget60;

  /// Begins watching. Safe to call more than once.
  ///
  /// Deliberately NOT awaited by `bootstrap()`: this must never sit between the
  /// user and the first frame. It costs one callback per frame and allocates
  /// nothing per frame.
  void start() {
    if (_started || kIsWeb) return;
    _started = true;
    _attached = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    unawaited(_readDisplayBudget());
  }

  Future<void> _readDisplayBudget() async {
    try {
      final mode = await FlutterDisplayMode.active;
      if (mode.refreshRate > 0) {
        _displayBudget =
            Duration(microseconds: (1000000 / mode.refreshRate).round());
      }
    } catch (_) {
      // Not Android, no plugin, or no mode reported. The 60Hz default stands,
      // which only ever makes this LESS eager to intervene.
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_decided && _backedOff) {
      _detach();
      return;
    }
    for (final t in timings) {
      if (++_seen <= _warmupFrames) continue;

      // build + raster, NOT totalSpan: totalSpan includes time the frame spent
      // waiting for vsync, which is not work the app did and would make an idle
      // app look overloaded.
      final work = t.buildDuration + t.rasterDuration;
      if (work > _budget60) _missed60++;
      if (work > _displayBudget) _missedDisplay++;

      if (++_sampled < _sampleSize) continue;
      _decide();
      return;
    }
  }

  void _decide() {
    if (_decided) return;
    _decided = true;
    _detach();

    final miss60 = _missed60 / _sampled;
    final missDisplay = _missedDisplay / _sampled;

    tier.value = miss60 >= _missRatioForLow ? PerfTier.low : PerfTier.high;

    if (missDisplay >= _missRatioForBackOff) {
      unawaited(_backOffRefreshRate());
    }

    debugPrint('[perf] tier=${tier.value.name} '
        'missed60=${(miss60 * 100).toStringAsFixed(0)}% '
        'missedDisplay=${(missDisplay * 100).toStringAsFixed(0)}% '
        'budget=${_displayBudget.inMicroseconds}us n=$_sampled');
  }

  /// Stop watching, but only if we ever started. See [_attached].
  void _detach() {
    if (!_attached) return;
    _attached = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  /// Give back the refresh rate this device cannot sustain — ONE STEP, not all
  /// the way down.
  ///
  /// `FlutterDisplayMode.setLowRefreshRate()` jumps to the device's LOWEST
  /// mode, which on a 120/90/60 panel means 60 and throws away a 90Hz mode that
  /// may be perfectly holdable. Measured on the development device (motorola
  /// edge 60 pro): at 120Hz it missed its 8.3ms budget on 40% of frames while
  /// missing the 60Hz budget on only 6% — so it genuinely could not hold 120,
  /// but there was no evidence it could not hold 90, and nothing had asked.
  ///
  /// So: pick the highest supported mode STRICTLY BELOW the current refresh
  /// rate, at the same resolution. If that one also turns out to be too much,
  /// there is no second attempt — this runs once per session by design, because
  /// a display mode that changes repeatedly is worse than either setting.
  Future<void> _backOffRefreshRate() async {
    if (_backedOff) return;
    _backedOff = true;
    try {
      final active = await FlutterDisplayMode.active;
      final modes = await FlutterDisplayMode.supported;

      // Same physical resolution only: `supported` can include other
      // resolutions, and quietly changing those would be a far bigger change
      // than the smoothness problem being solved.
      final lower = modes
          .where((m) =>
              m.width == active.width &&
              m.height == active.height &&
              m.refreshRate < active.refreshRate - 1)
          .toList()
        ..sort((a, b) => b.refreshRate.compareTo(a.refreshRate));

      if (lower.isEmpty) {
        debugPrint('[perf] no lower refresh mode to step down to');
        return;
      }
      await FlutterDisplayMode.setPreferredMode(lower.first);
      debugPrint('[perf] stepped down ${active.refreshRate.round()}Hz -> '
          '${lower.first.refreshRate.round()}Hz');
    } catch (_) {
      // Best effort. Failing to back off costs smoothness, never correctness.
    }
  }

  /// Test seam. Feeds synthetic timings so the classification rules can be
  /// exercised without a device — the rules are the part worth testing, and
  /// they are pure arithmetic over frame durations.
  @visibleForTesting
  void debugFeed(List<FrameTiming> timings) => _onTimings(timings);

  @visibleForTesting
  void debugReset({Duration? displayBudget}) {
    _seen = 0;
    _sampled = 0;
    _missed60 = 0;
    _missedDisplay = 0;
    _decided = false;
    _backedOff = false;
    _started = true; // never attach a real callback from a test
    _attached = false;
    _displayBudget = displayBudget ?? _budget60;
    tier.value = PerfTier.unknown;
  }

  @visibleForTesting
  bool get debugBackedOff => _backedOff;

  @visibleForTesting
  static int get debugWarmupFrames => _warmupFrames;

  @visibleForTesting
  static int get debugSampleSize => _sampleSize;
}
