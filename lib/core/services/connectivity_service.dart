import 'dart:async';
import 'dart:io' show InternetAddress, SocketException;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../../config/supabase_config.dart';

/// Single shared source of truth for online/offline state -- replaces the
/// dead, never-wired `connectivity_plus` import that only `offline_banner.dart`
/// used to hold privately. Both the read-cache layer (skip a network fetch
/// attempt while offline, serve cache immediately) and the write-outbox
/// flush trigger key off this same notifier.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  final ValueNotifier<bool> isOnline = ValueNotifier<bool>(true);
  Timer? _pollTimer;

  Future<void> init() async {
    // NOT awaited, deliberately. This runs in bootstrap before `runApp`, and
    // the probe below can legitimately take its full 4s budget on exactly the
    // network it exists to detect — a connected-but-dead uplink. Awaiting it
    // meant the app painted NOTHING for four seconds on that network, against
    // a 1800ms cold-start budget, to answer a question the whole app is
    // already built to re-ask (`recheck()`).
    //
    // `isOnline` starts optimistic (true), which is the same default the
    // empty-transport case resolves to, so nothing reads a wrong value in the
    // gap — a cached fetch that needs certainty calls `recheck()` itself.
    // The listener and poll below are registered synchronously either way, so
    // a slow first probe can no longer leave this service unwired.
    unawaited(Connectivity()
        .checkConnectivity()
        .then(_checkReal)
        .then((value) => isOnline.value = value)
        .catchError((_) => isOnline.value));
    Connectivity().onConnectivityChanged.listen((results) async {
      final value = await _checkReal(results);
      if (value != isOnline.value) isOnline.value = value;
    });
    // A dead WiFi uplink (router with no WAN, killed connection that never
    // drops the transport itself) never fires onConnectivityChanged -- proven
    // live: blocking all outbound traffic while leaving WiFi "connected" left
    // `isOnline` latched true with nothing to correct it, so every screen
    // just hung waiting on a network that was never coming back instead of
    // falling back to cache. `_checkReal` already dedupes overlapping calls
    // (see `_pendingProbe`), so this can't pile up lookups the way an
    // unguarded periodic probe would.
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 20), (_) => recheck());
  }

  /// Re-reads the platform's connectivity and republishes it.
  ///
  /// [init] is awaited before the first frame and the change stream only fires
  /// on a TRANSITION, so a wrong answer at startup is latched for the entire
  /// session with nothing to correct it. This is the escape hatch for callers
  /// that have evidence contradicting the flag — see [cachedListFetch], which
  /// calls it before it is willing to act on "offline".
  Future<bool> recheck() async {
    final value = await _checkReal(await Connectivity().checkConnectivity());
    if (value != isOnline.value) isOnline.value = value;
    return value;
  }

  Future<bool>? _pendingProbe;

  /// [resolveConnectivity] alone only proves a transport (WiFi/mobile) is UP,
  /// never that it leads anywhere. Connected-to-a-dead-router and
  /// connected-to-the-internet report the identical `ConnectivityResult.wifi`,
  /// so the app believed it was online on a network with no working uplink,
  /// and every live fetch below hung on an unreachable host for however long
  /// the OS socket timeout takes instead of falling back to cache in seconds.
  /// Once the transport is confirmed up, confirm there is actually somewhere
  /// to send a request before trusting it.
  Future<bool> _checkReal(List<ConnectivityResult> results) async {
    if (!resolveConnectivity(results)) return false;
    // A browser only reports a transport as up when it can actually reach the
    // network stack, and `dart:io` DNS lookups aren't available on web anyway.
    if (kIsWeb) return true;
    // A DNS lookup that never resolves (rather than failing fast) ties up a
    // slot in dart:io's native resolver thread pool even after `.timeout`
    // gives up waiting on it -- `onConnectivityChanged` firing a burst of
    // events (flaky WiFi flapping transports several times a second) could
    // pile up enough of these to starve every other blocking I/O call this
    // isolate makes. One probe in flight at a time; a burst rides the result
    // of whichever lookup is already running instead of starting its own.
    final inFlight = _pendingProbe;
    if (inFlight != null) return inFlight;
    final probe = _resolveHost().whenComplete(() => _pendingProbe = null);
    _pendingProbe = probe;
    return probe;
  }

  Future<bool> _resolveHost() async {
    try {
      final host = Uri.parse(SupabaseConfig.url).host;
      final lookup = await InternetAddress.lookup(host).timeout(const Duration(seconds: 4));
      return lookup.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
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
}
