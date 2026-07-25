import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Briefly holds a just-registered user's credentials so the login screen
/// can prefill them after signup redirects there. Consuming always deletes
/// the stored values so they never linger on disk beyond that one hand-off.
///
/// Hardening notes — this stores a real, working password, so it is the most
/// sensitive thing the app writes to disk:
///
///  - **Keystore-backed.** A bare `FlutterSecureStorage()` on Android falls
///    back to plain SharedPreferences-with-a-cipher rather than the hardware
///    keystore. `encryptedSharedPreferences: true` matches what
///    BiometricTokenStore already asks for (biometric_lock.dart), so the two
///    stores no longer disagree about how carefully to hold a credential.
///  - **TTL.** The hand-off it exists for happens seconds after signup. If
///    the app is killed between the two screens the value would otherwise sit
///    there indefinitely, so anything older than [_ttl] is treated as absent
///    and wiped. A prefill that silently doesn't happen is a trivial cost;
///    an indefinitely-stored password is not.
///  - **Wiped at sign-out.** [clear] is called from the signedOut chokepoint
///    in bootstrap.dart, so a stale entry can't outlive the session it
///    belonged to.
class PendingCredentialsStore {
  PendingCredentialsStore._();
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _emailKey = 'afos_pending_login_email';
  static const _passwordKey = 'afos_pending_login_password';
  static const _savedAtKey = 'afos_pending_login_saved_at';

  /// Generous enough to survive a slow signup round-trip and a cold restart
  /// in between, short enough that a forgotten value doesn't persist.
  static const _ttl = Duration(minutes: 15);

  static Future<void> save(String email, String password) async {
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _passwordKey, value: password);
    await _storage.write(
        key: _savedAtKey, value: DateTime.now().toUtc().toIso8601String());
  }

  static Future<(String, String)?> consume() async {
    final email = await _storage.read(key: _emailKey);
    final password = await _storage.read(key: _passwordKey);
    final savedAt = await _storage.read(key: _savedAtKey);
    // Cleared unconditionally, including on the expiry and malformed paths —
    // an entry that can't be used is exactly the kind that shouldn't be left
    // behind.
    await clear();
    if (email == null || password == null) return null;
    final at = savedAt == null ? null : DateTime.tryParse(savedAt);
    if (at == null || DateTime.now().toUtc().difference(at) > _ttl) {
      // Entries written before the TTL existed have no timestamp, so they
      // land here too and are discarded rather than trusted.
      debugPrint('[PendingCredentialsStore] discarded expired credentials');
      return null;
    }
    return (email, password);
  }

  /// Drops anything held, whether or not it was ever consumed.
  static Future<void> clear() async {
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passwordKey);
    await _storage.delete(key: _savedAtKey);
  }
}
