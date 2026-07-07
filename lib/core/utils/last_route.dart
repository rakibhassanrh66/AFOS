import 'package:hive_flutter/hive_flutter.dart';

/// Persists the last real (non-auth, non-splash) screen the user was on, so
/// force-closing the app (rather than logging out) resumes where they left
/// off instead of always dropping back to the dashboard. Reuses the same
/// 'settings' Hive box as ThemeBloc rather than opening a new one.
const _boxKey = 'settings';
const _lastRouteKey = 'last_route';

/// Routes that should never be "resumed into" even if they were the last
/// thing recorded — auth/onboarding screens, or ones that need fresh
/// server-driven state rather than a stale client redirect target.
const excludedFromResume = ['/splash', '/auth', '/complete-profile', '/pending-approval'];

Future<void> saveLastRoute(String path) async {
  if (excludedFromResume.any((p) => path.startsWith(p))) return;
  final box = await Hive.openBox(_boxKey);
  await box.put(_lastRouteKey, path);
}

Future<String?> loadLastRoute() async {
  final box = await Hive.openBox(_boxKey);
  return box.get(_lastRouteKey) as String?;
}
