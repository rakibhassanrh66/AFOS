import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/app_config.dart';
import 'config/routes/app_router.dart';
import 'config/supabase_config.dart';
import 'config/theme/dark_theme.dart';
import 'config/theme/light_theme.dart';
import 'core/di/injection.dart';
import 'core/services/badge_service.dart';
import 'features/settings/bloc/theme_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations(
      [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);

  await Hive.initFlutter();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
  );

  OneSignal.initialize(AppConfig.oneSignalAppId);
  OneSignal.Notifications.requestPermission(true);

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
    final current = await OneSignal.User.getExternalId();
    if (current != uid) {
      if (current != null) OneSignal.logout();
      if (uid != null) OneSignal.login(uid);
    }
    oneSignalUid = uid;
  }

  syncOneSignalIdentity(Supabase.instance.client.auth.currentUser?.id);
  if (Supabase.instance.client.auth.currentUser != null) BadgeService.start();
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    syncOneSignalIdentity(data.session?.user.id);
    if (data.session?.user.id != null) {
      BadgeService.start();
    } else {
      BadgeService.stop();
    }
  });

  configureDependencies();
  runApp(const AFOSApp());
}

class AFOSApp extends StatelessWidget {
  const AFOSApp({super.key});
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ThemeBloc(),
      child: BlocBuilder<ThemeBloc, ThemeState>(
        builder: (context, state) => MaterialApp.router(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: buildLightTheme(accent: state.accentColor),
          darkTheme: buildDarkTheme(accent: state.accentColor),
          themeMode: state.mode,
          routerConfig: AppRouter.router,
        ),
      ),
    );
  }
}
