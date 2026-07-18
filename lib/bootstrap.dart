import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'config/routes/app_router.dart';
import 'config/supabase_config.dart';
import 'core/di/injection.dart';
import 'core/auth/biometric_lock.dart';
import 'core/services/app_config_service.dart';
import 'core/services/badge_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/local_cache_service.dart';
import 'core/services/onesignal_web_bridge.dart';
import 'core/services/outbox_handlers.dart';
import 'core/services/outbox_service.dart';
import 'core/services/sos_location_service.dart';

// onesignal_flutter only declares android/ios platform implementations --
// calling its native channel on any other platform (including Windows/
// macOS/Linux desktop, not just web) throws MissingPluginException.
bool get _isMobile =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Shared app init sequence, extracted from main.dart so both the real
/// entry point and the integration_test suite call the exact same
/// bootstrap and can never drift apart. Callers must invoke the
/// appropriate binding init (WidgetsFlutterBinding.ensureInitialized() for
/// the real app, IntegrationTestWidgetsFlutterBinding.ensureInitialized()
/// for tests) before calling this.
Future<void> bootstrap() async {
  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  // Opt into the device's native high refresh rate (90/120Hz) on Android —
  // Flutter otherwise caps rendering at 60Hz there even on faster panels.
  // Best-effort (a device without a high-Hz mode just stays at its default);
  // iOS ProMotion is handled by the engine automatically, no call needed.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
    } catch (_) {}
  }

  // Real installed version, so UI/feedback metadata can't drift from
  // pubspec.yaml. Best-effort: keep the compiled-in fallback on failure.
  try {
    AppConfig.appVersion = (await PackageInfo.fromPlatform()).version;
  } catch (_) {}

  await Hive.initFlutter();
  await Hive.openBox(LocalCacheService.boxName);
  await Hive.openBox(OutboxService.boxName);

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  // Single shared online/offline signal for the read-cache layer and the
  // write-outbox flush trigger -- see connectivity_service.dart.
  await ConnectivityService.instance.init();
  registerOutboxHandlers();
  ConnectivityService.instance.isOnline.addListener(() {
    if (ConnectivityService.instance.isOnline.value) OutboxService.instance.flush();
  });

  // The app's own OneSignal Web SDK (wired in web/index.html)
  // self-initializes via its script tag instead of the native plugin.
  // Desktop targets get no push at all -- best-effort, no plugin backs it.
  if (kIsWeb) {
    await OneSignalWebBridge.requestPermission();
  } else if (_isMobile) {
    OneSignal.initialize(AppConfig.oneSignalAppId);
    OneSignal.Notifications.requestPermission(true);
    // Tapping the actual OS push banner (app backgrounded or fully killed)
    // must land on the same screen the in-app notification bell does --
    // both are driven by the same `deep_link_route` value the backend
    // already stamps onto every notification (see send-notification's
    // OneSignal `data` payload).
    OneSignal.Notifications.addClickListener((event) {
      final route = event.notification.additionalData?['deep_link_route'] as String?;
      if (route != null && route.isNotEmpty) AppRouter.router.push(route);
    });
  }

  await SosLocationService.initialize();
  // Best-effort, opt-out ambient layer for the SOS system's "who's nearby"
  // resolution -- defaults to on (matches user_locations.sharing_enabled's
  // DB default) unless the user explicitly disabled it in Settings. A
  // failed lookup (e.g. no row yet for a brand-new account) is treated as
  // "on" rather than silently leaving a real emergency feature off.
  Future<void> syncLocationSharing(String? uid) async {
    if (uid == null) { await SosLocationService.stop(); return; }
    try {
      final row = await Supabase.instance.client.from('user_locations')
          .select('sharing_enabled').eq('user_id', uid).maybeSingle();
      final enabled = row == null ? true : (row['sharing_enabled'] as bool? ?? true);
      if (enabled) { await SosLocationService.start(); } else { await SosLocationService.stop(); }
    } catch (_) {
      await SosLocationService.start();
    }
  }

  // Targeted push (routine updates, mentorship, lost&found, approvals) is
  // sent via OneSignal's external_id, which must be tied to the Supabase
  // user id for the whole session, not just at sign-in — otherwise a
  // cold start with an already-valid session never re-associates the
  // device with that user after an app restart.
  //
  // Confirmed live via OneSignal's own view-subscription API: when a
  // second, different account logs into the same physical device, the
  // device's one real push subscription stays attached to whichever
  // account had it *first* — the new account shows zero subscriptions at
  // all, so it can never receive push. Calling login(newUid) without an
  // explicit logout() first for the *previous* uid doesn't move the
  // subscription over; only an explicit logout()-then-login() sequence
  // does. The old code only called logout() on an explicit
  // AuthChangeEvent.signedOut, which an abrupt session drop (e.g. a
  // failed token refresh) doesn't reliably emit — so switching accounts
  // that way silently left the subscription stuck on the old identity.
  //
  // A second attempt at this fix unconditionally called logout() before
  // every login(), on the theory that a cold start with an already-persisted
  // session never fires onAuthStateChange, so the in-memory oneSignalUid
  // (reset to null on every process start) could never be trusted alone.
  // That overcorrected: OneSignal's own SDK-side identity already survives
  // an app restart (it's persisted device-side, not just in this Dart
  // variable), so calling logout() on every single cold start — even when
  // the device was ALREADY correctly bound to this exact uid from last
  // time — orphans that binding and mints a brand new OneSignal User each
  // launch. Confirmed live: this is exactly what produced the recurring
  // "One or more Aliases claimed by another User" 409 on every subsequent
  // launch, since the external_id was now claimed by multiple competing
  // OneSignal User records and the SDK doesn't auto-merge them — this is
  // the real root cause of "push worked once, never again." Querying
  // OneSignal's own getExternalId() (its actual current state, not our
  // in-memory guess) before deciding whether to rebind avoids both bugs:
  // skip entirely when it's already correct, only logout()-then-login()
  // when it's genuinely a different account.
  String? oneSignalUid;
  Future<void> syncOneSignalIdentity(String? uid) async {
    if (uid == oneSignalUid) return;
    if (kIsWeb) {
      if (uid != null) {
        await OneSignalWebBridge.login(uid);
      } else {
        await OneSignalWebBridge.logout();
      }
      oneSignalUid = uid;
      return;
    }
    if (!_isMobile) {
      oneSignalUid = uid;
      return;
    }
    final current = await OneSignal.User.getExternalId();
    if (current != uid) {
      if (current != null) OneSignal.logout();
      if (uid != null) OneSignal.login(uid);
    }
    oneSignalUid = uid;
  }

  syncOneSignalIdentity(Supabase.instance.client.auth.currentUser?.id);
  if (Supabase.instance.client.auth.currentUser != null) {
    BadgeService.start();
    syncLocationSharing(Supabase.instance.client.auth.currentUser?.id);
  }
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    syncOneSignalIdentity(data.session?.user.id);
    syncLocationSharing(data.session?.user.id);
    if (data.session?.user.id != null) {
      BadgeService.start();
    } else {
      BadgeService.stop();
    }
    // Single chokepoint for wiping the biometric quick-login token: any real
    // sign-out (settings/menu logout, reset-password, or a silent session
    // drop) fires signedOut here, so the stored session can never outlive the
    // account it belonged to. (recoverSession/auto-restore emit signedIn, not
    // signedOut, so a biometric unlock never trips this.)
    if (data.event == AuthChangeEvent.signedOut) {
      BiometricTokenStore.clear();
      AppConfigService.instance.reset();
    }
    // Clicking the emailed password-reset link establishes a real session
    // and fires this event exactly once -- there was previously nothing
    // listening for it at all, so the recovery token in the link just sat
    // there unused and the user landed "logged in" with no way to actually
    // set a new password.
    if (data.event == AuthChangeEvent.passwordRecovery) {
      AppRouter.router.push('/reset-password');
    }
  });

  configureDependencies();
}
