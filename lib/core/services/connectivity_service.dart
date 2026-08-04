import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Single shared source of truth for online/offline state -- replaces the
/// dead, never-wired `connectivity_plus` import that only `offline_banner.dart`
/// used to hold privately. Both the read-cache layer (skip a network fetch
/// attempt while offline, serve cache immediately) and the write-outbox
/// flush trigger key off this same notifier.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);

  Future<void> init() async {
    isOnline.value = _resolve(await Connectivity().checkConnectivity());
    Connectivity().onConnectivityChanged.listen((results) {
      final value = _resolve(results);
      if (value != isOnline.value) isOnline.value = value;
    });
  }

  /// Re-reads the platform's connectivity and republishes it.
  ///
  /// [init] is awaited before the first frame and the change stream only fires
  /// on a TRANSITION, so a wrong answer at startup is latched for the entire
  /// session with nothing to correct it. This is the escape hatch for callers
  /// that have evidence contradicting the flag — see [cachedListFetch], which
  /// calls it before it is willing to act on "offline".
  Future<bool> recheck() async {
    final value = _resolve(await Connectivity().checkConnectivity());
    if (value != isOnline.value) isOnline.value = value;
    return value;
  }

  /// True when ANY transport is up.
  ///
  /// The empty-list case is deliberately online, not offline. `Iterable.any`
  /// answers `false` for `[]`, and connectivity_plus does return an empty list
  /// rather than `[ConnectivityResult.none]` on some Android configurations —
  /// so a device with perfectly good network resolved to offline, and stayed
  /// there. Downstream that is not a cosmetic error: [cachedListFetch] skips
  /// the network entirely while offline, so every cached screen quietly served
  /// an empty list and rendered its "nothing here yet" state over a database
  /// full of the user's data.
  ///
  /// An empty list means the platform told us nothing, and "unknown" must fail
  /// towards attempting the fetch: a needless request on a genuinely offline
  /// device costs one quick error, while a skipped request on an online device
  /// costs the user their entire page.
  ///
  /// Public and static so `connectivity_resolve_test` can drive the real rule
  /// rather than a copy of it. Everything else here needs the platform channel;
  /// this is the whole of the decision and it is pure, so it is the one piece
  /// worth pinning — the bug was exactly one character of it.
  static bool resolveConnectivity(List<ConnectivityResult> results) =>
      results.isEmpty || results.any((r) => r != ConnectivityResult.none);

  bool _resolve(List<ConnectivityResult> results) => resolveConnectivity(results);
}
