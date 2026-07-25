import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
import 'core/auth/secure_session_storage.dart';
import 'core/utils/pending_credentials_store.dart';
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

  // Edge-to-edge, declared explicitly.
  //
  // The app ships targetSdk 36, and from Android 15 the platform ENFORCES
  // edge-to-edge and ignores windowOptOutEdgeToEdgeEnforcement — so the app
  // has been drawing behind the status and gesture bars regardless, while
  // never once calling SystemChrome or setting a single window flag. The
  // result was the platform picking its own contrast scrim over surfaces the
  // app had already frosted, and layout code guessing at insets it never
  // declared it was consuming.
  //
  // Transparent bars let the app's own LiquidBackdrop show through, and
  // MediaQuery.padding then reports the real bar heights, which is exactly
  // what AppShell's clearance and the slide menu's positioning read. Icon
  // brightness is NOT set here (it would be wrong for one of the two themes);
  // each theme declares it via appBarTheme.systemOverlayStyle.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

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
  // First launch after an update (in-app or sideloaded) starts with a clean
  // read-cache instead of a possibly-stale one from the old version — see
  // LocalCacheService.clearIfVersionChanged's own doc comment for why this
  // is scoped to ONLY that cache, never the outbox or secure storage.
  await LocalCacheService.instance.clearIfVersionChanged(AppConfig.appVersion);
  await Hive.openBox(OutboxService.boxName);

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    // The session (including the long-lived refresh token) goes in the
    // platform keystore rather than the default SharedPreferences file. Web
    // keeps the default: flutter_secure_storage still lands in localStorage
    // there, so it would add a migration risk for no security gain. See
    // secure_session_storage.dart for the migration that stops this from
    // signing existing users out.
    // The key MUST be the one supabase_flutter would have generated itself
    // ("sb-<project-ref>-auth-token", see Supabase.initialize) — that is the
    // SharedPreferences entry existing installs already hold, and the
    // migration reads it by name. Inventing a new key here would silently
    // migrate nothing and sign every existing user out on update.
    authOptions: FlutterAuthClientOptions(
      localStorage: kIsWeb
          ? null
          : SecureSessionLocalStorage(
              persistSessionKey:
                  'sb-${Uri.parse(SupabaseConfig.url).host.split('.').first}-auth-token',
            ),
    ),
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
  // Tracked separately from the event stream because a `signedOut` event's
  // own `data.session` is already null -- this is the only way to know
  // WHICH account just signed out, so only that one gets forgotten below
  // instead of every remembered account on the device.
  String? lastKnownUserId = Supabase.instance.client.auth.currentUser?.id;
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    syncOneSignalIdentity(data.session?.user.id);
    syncLocationSharing(data.session?.user.id);
    if (data.session?.user.id != null) {
      BadgeService.start();
    } else {
      BadgeService.stop();
    }
    // Chokepoint for forgetting a biometric quick-login token on a real
    // sign-out (settings/menu logout, reset-password, or a silent session
    // drop): only the account that actually just signed out is forgotten,
    // so other remembered accounts on this device stay switchable. An
    // intentional account switch (account_switcher_sheet.dart) sets
    // `switchingAccounts` around its own sign-out + recover step so this
    // skips it entirely -- it isn't a logout, it's a hand-off to the next
    // account. (recoverSession/auto-restore emit signedIn, not signedOut,
    // so a biometric unlock never trips this either.)
    if (data.event == AuthChangeEvent.signedOut) {
      if (lastKnownUserId != null && !BiometricTokenStore.switchingAccounts) {
        BiometricTokenStore.forget(lastKnownUserId!);
      }
      AppConfigService.instance.reset();
      // Same chokepoint reasoning as the biometric token above: a signup
      // whose login hand-off never completed would otherwise leave a real
      // password on disk until its TTL expired. Unlike the token, this is
      // cleared even during an account switch -- a pending credential
      // belongs to one signup, never to whichever account comes next.
      PendingCredentialsStore.clear();
    }
    if (data.session?.user.id != null) lastKnownUserId = data.session!.user.id;
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
