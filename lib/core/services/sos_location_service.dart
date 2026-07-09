import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';

/// Ambient "who's actually nearby" layer for the SOS system (see
/// user_locations table). Runs in a separate background isolate per
/// flutter_background_service's design, so it cannot share the main
/// isolate's already-initialized Supabase client -- it re-initializes its
/// own, which recovers the already-persisted auth session from local
/// storage rather than needing a fresh login. Best-effort and
/// gracefully-degrading: a user who never enables this (or whose OS denies
/// background location) still gets full app access and can still send
/// their own SOS via a fresh one-shot capture at trigger time.
class SosLocationService {
  SosLocationService._();

  static const _notificationId = 9001;
  static const _pingInterval = Duration(minutes: 4);

  // flutter_background_service only supports Android/iOS -- its platform
  // interface throws if touched on any other platform (confirmed by
  // reading its source, and live-reproduced on both web and Windows
  // desktop), which would otherwise crash bootstrap() before runApp() ever
  // gets called. kIsWeb alone isn't enough since desktop targets hit the
  // exact same throw. Non-mobile users still get one-shot
  // capture-at-trigger-time location via SosRepository, just no ambient
  // background layer.
  static bool get _isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<void> initialize() async {
    if (!_isSupportedPlatform) return;
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        // No custom notificationChannelId here on purpose -- passing one
        // makes the plugin skip its own createNotificationChannel() call
        // (it only auto-creates when the id is null), and this app never
        // separately created that channel itself. Referencing a phantom,
        // never-created channel in startForeground() is exactly what threw
        // CannotPostForegroundServiceNotificationException and killed the
        // whole app on a real Android 16 device (live-reproduced). Omitting
        // it lets the plugin create+use its own default channel instead.
        initialNotificationTitle: 'AFOS Campus Safety',
        initialNotificationContent: 'Sharing your location for emergency alerts',
        foregroundServiceNotificationId: _notificationId,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  }

  static Future<void> start() async {
    if (!_isSupportedPlatform) return;
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) await service.startService();
  }

  static Future<void> stop() async {
    if (!_isSupportedPlatform) return;
    final service = FlutterBackgroundService();
    if (await service.isRunning()) service.invoke('stop');
  }
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // Separate isolate -- SupabaseConfig.client (main isolate's singleton)
  // isn't reachable here, so re-initialize against the same project. This
  // recovers the already-persisted session rather than requiring a login.
  await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey);

  Timer? timer;
  service.on('stop').listen((event) {
    timer?.cancel();
    service.stopSelf();
  });

  Future<void> ping() async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final enabled = await Supabase.instance.client
          .from('user_locations').select('sharing_enabled').eq('user_id', uid).maybeSingle();
      if (enabled != null && enabled['sharing_enabled'] == false) return;
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium));
      await Supabase.instance.client.from('user_locations').upsert({
        'user_id': uid,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy_m': pos.accuracy,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Best-effort -- a failed ping just skips this cycle; recipient
      // resolution already discards stale rows (see trigger-sos-alert).
    }
  }

  await ping();
  timer = Timer.periodic(SosLocationService._pingInterval, (_) => ping());
}
