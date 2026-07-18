import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// On-device secure store for the biometric quick-login state. Holds only:
///  - an enabled flag,
///  - a "already asked once" flag (so we don't nag after login),
///  - the serialized Supabase **session JSON** (never any biometric data),
/// all in the platform-encrypted keystore (Android Keystore / iOS Keychain).
/// Nothing here ever leaves the device.
class BiometricTokenStore {
  BiometricTokenStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kEnabled = 'biometric_enabled';
  static const _kSession = 'biometric_session';
  static const _kPrompted = 'biometric_prompted';

  /// Enable quick-login: store the current session JSON + the flag.
  static Future<void> enable(String sessionJson) async {
    await _storage.write(key: _kSession, value: sessionJson);
    await _storage.write(key: _kEnabled, value: 'true');
  }

  /// Disable + wipe the stored session (on toggle-off or any logout).
  static Future<void> clear() async {
    await _storage.delete(key: _kSession);
    await _storage.delete(key: _kEnabled);
    // Deliberately keep _kPrompted so we don't re-nag after a normal logout.
  }

  static Future<bool> isEnabled() async => (await _storage.read(key: _kEnabled)) == 'true';
  static Future<String?> readSession() async => _storage.read(key: _kSession);

  static Future<bool> wasPrompted() async => (await _storage.read(key: _kPrompted)) == 'true';
  static Future<void> markPrompted() async => _storage.write(key: _kPrompted, value: 'true');
}

/// Thin wrapper over `local_auth`. Biometric matching happens entirely inside
/// the OS; this only returns pass/fail. Fully disabled on web (no hardware).
class BiometricAuth {
  BiometricAuth._();
  static final _auth = LocalAuthentication();

  /// True only when this device can actually do a biometric check.
  static Future<bool> canUse() async {
    if (kIsWeb) return false;
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final can = await _auth.canCheckBiometrics;
      return can;
    } catch (_) {
      return false;
    }
  }

  /// Prompts the OS biometric check. Returns true on success, false on
  /// cancel/failure/unavailable (never throws to the caller).
  static Future<bool> authenticate(String reason) async {
    if (kIsWeb) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: false),
      );
    } catch (_) {
      return false;
    }
  }
}
