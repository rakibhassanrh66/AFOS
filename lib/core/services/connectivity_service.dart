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

  bool _resolve(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}
