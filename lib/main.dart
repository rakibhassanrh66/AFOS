import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'bootstrap.dart';
import 'config/app_config.dart';
import 'config/routes/app_router.dart';
import 'config/theme/dark_theme.dart';
import 'config/theme/light_theme.dart';
import 'features/settings/bloc/theme_bloc.dart';

/// THE APP ALWAYS RENDERS SOMETHING. THAT IS THE RULE THIS ENFORCES.
///
/// This was `await bootstrap(); runApp(...)`, which means any throw inside
/// bootstrap skips `runApp` entirely. Flutter then never produces a frame, so
/// Android keeps showing the launch icon from `LaunchTheme` — forever. No
/// crash dialog (the process is alive and healthy), no error, nothing to tap,
/// and nothing in the UI to report. The app is simply frozen.
///
/// That is exactly what shipped: `flutter_secure_storage` threw BAD_DECRYPT
/// reading the saved session, the exception travelled
/// `hasAccessToken -> Supabase.initialize -> bootstrap -> main`, and the app
/// bricked on a black launch screen for anyone whose Keystore key had been
/// invalidated — a new phone, a restored backup, a changed screen lock.
///
/// The specific cause is fixed at its source in secure_session_storage.dart.
/// This guard is here because the NEXT unguarded await in bootstrap must not
/// be able to do the same thing. Sixteen things are initialised in there —
/// Hive, connectivity, OneSignal, display mode, package info — and any one of
/// them throwing should cost a feature, not the whole app.
///
/// A visible error is not a nice failure, but it is a REPORTABLE one, and it
/// is strictly better than a frozen launch icon that looks like a hung phone.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? failure;
  try {
    await bootstrap();
  } catch (e, st) {
    failure = e;
    // Full trace to logcat: this is the only channel left when startup fails,
    // and it is what turned "the app freezes" into a one-line diagnosis.
    debugPrint('[main] bootstrap failed, starting in degraded mode: $e\n$st');
  }
  runApp(failure == null ? const AFOSApp() : _StartupFailureApp(error: failure));
}

/// Shown only when [bootstrap] threw. Deliberately depends on nothing that
/// bootstrap sets up — no theme bloc, no router, no Supabase — because any of
/// those may be exactly what failed.
class _StartupFailureApp extends StatelessWidget {
  final Object error;
  const _StartupFailureApp({required this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF0B1020),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Color(0xFFF87171), size: 44),
                const SizedBox(height: 16),
                const Text(
                  'AFOS could not start',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Something failed while setting the app up. Close AFOS and '
                  'open it again. If it keeps happening, clear the app’s '
                  'storage in Android Settings → Apps → AFOS → '
                  'Storage, then sign in again.',
                  style: TextStyle(color: Color(0xFFB6BECD), height: 1.5),
                ),
                const SizedBox(height: 20),
                // The real message, on screen. Without this the only copy is
                // in logcat, which a student cannot reach.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: SelectableText(
                    '$error',
                    style: const TextStyle(
                        color: Color(0xFF8FA0B8),
                        fontSize: 12,
                        fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
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
