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

  /// Reads the stored session, and treats ANY failure as "no session".
  ///
  /// THIS BRICKED THE APP. `hasAccessToken` is the first thing
  /// `SupabaseAuth.initialize` calls, and it was an unguarded `await
  /// _storage.read(...)`. When the read throws, the exception propagates
  /// through `Supabase.initialize` -> `bootstrap()` -> `main()`, so `runApp`
  /// is never reached: no Flutter frame is ever drawn and the user sits on the
  /// native launch icon forever, with no error, no crash dialog, and nothing
  /// to tap. Observed live as:
  ///
  ///   PlatformException(Exception encountered, read,
  ///   javax.crypto.BadPaddingException: OPENSSL_internal:BAD_DECRYPT)
  ///   #2 SecureSessionLocalStorage.hasAccessToken
  ///   #3 SupabaseAuth.initialize  #4 Supabase.initialize
  ///   #5 bootstrap  #6 main
  ///
  /// HOW IT HAPPENS TO REAL USERS. flutter_secure_storage encrypts with a key
  /// held in the Android Keystore, while the ciphertext lives in ordinary app
  /// storage. The two can be separated:
  ///   * Android auto-backup restores the ciphertext to a new device or a
  ///     reinstall; the Keystore key is device-bound and does not come with it.
  ///   * Changing the screen lock or re-enrolling a fingerprint can invalidate
  ///     the key while the ciphertext stays exactly where it was.
  /// In both cases the bytes are intact and undecryptable — which is precisely
  /// BAD_DECRYPT. This is not an exotic edge case; it is the ordinary
  /// new-phone path.
  ///
  /// SO IT SELF-HEALS. An entry that cannot be decrypted can never be decrypted
  /// again, so keeping it only guarantees the same failure on every future
  /// launch. Deleting it costs the user one sign-in; keeping it costs them the
  /// app. `initialize` below already reasoned this way about migration failure
  /// ("must not brick startup... Throwing here would not be [recoverable]") —
  /// that reasoning was simply never applied to the other four methods.
  Future<String?> _readOrHeal() async {
    try {
      return await _storage.read(key: persistSessionKey);
    } catch (e) {
      debugPrint('[SecureSessionLocalStorage] unreadable session discarded: $e');
      try {
        await _storage.delete(key: persistSessionKey);
      } catch (_) {
        // Even the delete can fail on a wedged keystore. Reporting "no
        // session" is still correct and still lets the app start.
      }
      return null;
    }
  }

  @override
  Future<bool> hasAccessToken() async => (await _readOrHeal()) != null;

  @override
  Future<String?> accessToken() => _readOrHeal();

  @override
  Future<void> removePersistedSession() async {
    try {
      await _storage.delete(key: persistSessionKey);
    } catch (e) {
      // Signing out must always succeed from the user's point of view. The
      // in-memory session is cleared by the caller regardless.
      debugPrint('[SecureSessionLocalStorage] delete failed: $e');
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    try {
      await _storage.write(key: persistSessionKey, value: persistSessionString);
    } catch (e) {
      // Failing to REMEMBER a session is a lost convenience: the user stays
      // signed in for this run and signs in again next launch. Failing to
      // start the app is not a trade worth making for it.
      debugPrint('[SecureSessionLocalStorage] persist failed: $e');
    }
  }
}
