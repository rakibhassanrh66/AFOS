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
  // A first attempt at this fix skipped the logout() call on this
  // process's very first sync (no in-memory previous uid to compare
  // against yet), which looked right for "no change happened" but doesn't
  // hold: a cold start with an already-persisted session never fires
  // onAuthStateChange at all, so if the device's OneSignal subscription
  // was already wrongly bound to a *different* account from before this
  // process even started, that first sync would just call login() again
  // for the same uid and never force the rebind — confirmed live, this
  // exact case left it stuck. Unconditionally logging out before logging
  // in whenever a sync actually needs to run (regardless of whether this
  // process has ever synced before) closes that gap too; logout() is a
  // safe no-op when nothing was bound yet.
  String? oneSignalUid;
  void syncOneSignalIdentity(String? uid) {
    if (uid == oneSignalUid) return;
    OneSignal.logout();
    if (uid != null) OneSignal.login(uid);
    oneSignalUid = uid;
  }

  syncOneSignalIdentity(Supabase.instance.client.auth.currentUser?.id);
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    syncOneSignalIdentity(data.session?.user.id);
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
