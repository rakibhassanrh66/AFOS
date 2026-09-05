import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/core/perf/device_profile.dart';

/// The tier classifier, exercised without a device.
///
/// The part worth testing here is not the plumbing — it is the JUDGEMENT: how
/// many late frames make a phone "low-end", and how long we watch before
/// saying so. Get that wrong in either direction and the fix is worse than the
/// bug: too eager and a flagship loses its glass for one unlucky GC pause; too
/// lax and the phone this was written for never benefits at all.
///
/// `FrameTiming` is constructible directly, so the rules can be driven with
/// synthetic frames.
void main() {
  final profile = DeviceProfile.instance;

  /// A frame whose build+raster totals [work].
  ///
  /// FrameTiming takes absolute vsync-relative timestamps in microseconds, in
  /// the order: vsyncStart, buildStart, buildFinish, rasterStart, rasterFinish.
  /// Build is charged 1us and the rest goes to raster, so `work` lands where
  /// the classifier reads it.
  FrameTiming frame(Duration work) => FrameTiming(
        vsyncStart: 0,
        buildStart: 0,
        buildFinish: 1,
        rasterStart: 1,
        rasterFinish: work.inMicroseconds,
        rasterFinishWallTime: work.inMicroseconds,
      );

  List<FrameTiming> frames(int n, Duration work) =>
      List.generate(n, (_) => frame(work));

  const fast = Duration(milliseconds: 4);
  const slow = Duration(milliseconds: 40);

  setUp(() => profile.debugReset());

  test('an undecided device is never treated as low-end', () {
    // The tier starts unknown and must read as capable: penalising a phone for
    // the first second of its life would strip the glass off every launch.
    expect(profile.tier.value, PerfTier.unknown);
    expect(profile.isLowEnd, isFalse);
  });

  test('warm-up frames are ignored, so a slow launch is not a slow phone', () {
    // Every app's first frames are slow -- shader warm-up, first layout, the
    // splash transition. Feed nothing BUT slow warm-up frames and the verdict
    // must still be pending.
    profile.debugFeed(frames(DeviceProfile.debugWarmupFrames, slow));
    expect(profile.tier.value, PerfTier.unknown);
    expect(profile.isLowEnd, isFalse);
  });

  test('a device that holds its budget is classified high', () {
    profile.debugFeed(frames(DeviceProfile.debugWarmupFrames, slow));
    profile.debugFeed(frames(DeviceProfile.debugSampleSize, fast));
    expect(profile.tier.value, PerfTier.high);
    expect(profile.isLowEnd, isFalse);
  });

  test('a device missing a fifth of its frames is classified low', () {
    profile.debugFeed(frames(DeviceProfile.debugWarmupFrames, slow));
    final n = DeviceProfile.debugSampleSize;
    profile.debugFeed(frames((n * 0.5).round(), slow));
    profile.debugFeed(frames(n - (n * 0.5).round(), fast));
    expect(profile.tier.value, PerfTier.low);
    expect(profile.isLowEnd, isTrue);
  });

  test('an occasional late frame does not cost a good phone its quality', () {
    // 5% late is normal everywhere: a GC pause, an image decode landing, the
    // OS scheduling something else. This is the regression guard against a
    // future "make it more sensitive" tweak.
    profile.debugFeed(frames(DeviceProfile.debugWarmupFrames, slow));
    final n = DeviceProfile.debugSampleSize;
    final late = (n * 0.05).round();
    profile.debugFeed(frames(late, slow));
    profile.debugFeed(frames(n - late, fast));
    expect(profile.tier.value, PerfTier.high);
  });

  test('the verdict is final — a later bad patch does not re-classify', () {
    profile.debugFeed(frames(DeviceProfile.debugWarmupFrames, slow));
    profile.debugFeed(frames(DeviceProfile.debugSampleSize, fast));
    expect(profile.tier.value, PerfTier.high);
    // One heavy screen (a map, a PDF render) must not strip the app's visual
    // identity for the rest of the session.
    profile.debugFeed(frames(DeviceProfile.debugSampleSize, slow));
    expect(profile.tier.value, PerfTier.high);
  });

  test('high refresh is handed back when the device cannot hold that budget', () {
    // A 120Hz panel on a weak GPU: 8.3ms budget, frames landing at 12ms. Fast
    // enough for 60Hz, nowhere near fast enough for what it opted into. The
    // tier stays HIGH -- the phone is fine -- but the refresh opt-in goes back.
    profile.debugReset(displayBudget: const Duration(microseconds: 8333));
    profile.debugFeed(frames(DeviceProfile.debugWarmupFrames, slow));
    profile.debugFeed(
        frames(DeviceProfile.debugSampleSize, const Duration(milliseconds: 12)));
    expect(profile.tier.value, PerfTier.high,
        reason: '12ms comfortably holds 60Hz, so this is not a low-end device');
    expect(profile.debugBackedOff, isTrue,
        reason: '12ms cannot hold the 8.3ms budget it opted into, so the '
            'high-refresh request must be withdrawn');
  });

  test('a device holding 120Hz keeps it', () {
    profile.debugReset(displayBudget: const Duration(microseconds: 8333));
    profile.debugFeed(frames(DeviceProfile.debugWarmupFrames, slow));
    profile.debugFeed(frames(DeviceProfile.debugSampleSize, fast));
    expect(profile.tier.value, PerfTier.high);
    expect(profile.debugBackedOff, isFalse);
  });
}
