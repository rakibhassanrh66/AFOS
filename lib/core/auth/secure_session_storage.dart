import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists the Supabase session in the platform keystore instead of
/// SharedPreferences.
///
/// WHY. supabase_flutter's default [SharedPreferencesLocalStorage] writes the
/// whole session — access token, **refresh token** and user payload — into the
/// app's SharedPreferences XML file. A refresh token is a long-lived
/// credential: anyone who reads that file can keep minting access tokens until
/// it is revoked server-side. On a rooted device, an emulator, or a device
/// backup that file is readable. BiometricTokenStore already stores its
/// per-account session JSON in the keystore for exactly this reason
/// (biometric_lock.dart:41) — this brings the *primary* session in line with
/// it, so the app no longer protects its convenience copy more carefully than
/// the real one.
///
/// MIGRATION. Swapping stores would otherwise sign out every existing user on
/// the update, because their session lives in the old location and the new one
/// starts empty. [initialize] therefore moves an existing SharedPreferences
/// session into the keystore once, then removes the plaintext copy — which is
/// also what finally gets the old plaintext token off disk for users who
/// already have one.
///
/// WEB is deliberately NOT routed through this: flutter_secure_storage on web
/// still ends up in localStorage, so it buys nothing there, and bootstrap.dart
/// keeps the default implementation for that platform.
class SecureSessionLocalStorage extends LocalStorage {
  SecureSessionLocalStorage({required this.persistSessionKey});

  final String persistSessionKey;

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  @override
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getString(persistSessionKey);
      if (legacy == null) return;
      // Only adopt the legacy session if the keystore has nothing newer —
      // otherwise a stale SharedPreferences entry left by a failed earlier
      // migration could overwrite the session actually in use.
      if (await _storage.read(key: persistSessionKey) == null) {
        await _storage.write(key: persistSessionKey, value: legacy);
      }
      await prefs.remove(persistSessionKey);
      debugPrint('[SecureSessionLocalStorage] migrated session out of SharedPreferences');
    } catch (e) {
      // A migration failure must not brick startup: the user simply lands on
      // the login screen, which is recoverable. Throwing here would not be.
      debugPrint('[SecureSessionLocalStorage] migration skipped: $e');
    }
  }

  @override
  Future<bool> hasAccessToken() async =>
      (await _storage.read(key: persistSessionKey)) != null;

  @override
  Future<String?> accessToken() => _storage.read(key: persistSessionKey);

  @override
  Future<void> removePersistedSession() =>
      _storage.delete(key: persistSessionKey);

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: persistSessionKey, value: persistSessionString);
}
