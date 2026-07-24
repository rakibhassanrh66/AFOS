import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// One device-remembered account's quick-login state.
class RememberedAccount {
  final String userId, email, sessionJson;
  final String? fullName, avatarUrl;
  const RememberedAccount({
    required this.userId, required this.email, required this.sessionJson,
    this.fullName, this.avatarUrl,
  });

  Map<String, dynamic> toJson() => {
    'userId': userId, 'email': email, 'sessionJson': sessionJson,
    'fullName': fullName, 'avatarUrl': avatarUrl,
  };

  factory RememberedAccount.fromJson(Map<String, dynamic> j) => RememberedAccount(
    userId: j['userId'] as String,
    email: j['email'] as String,
    sessionJson: j['sessionJson'] as String,
    fullName: j['fullName'] as String?,
    avatarUrl: j['avatarUrl'] as String?,
  );
}

/// On-device secure store for biometric quick-login — now **multi-account**:
/// a user testing/using several roles (student, teacher, admin, ...) can
/// enable quick-login for each one without the next account overwriting the
/// last. Holds, all in the platform-encrypted keystore (Android Keystore /
/// iOS Keychain), never leaving the device:
///  - a list of remembered accounts (userId, email, display info, and each
///    one's serialized Supabase **session JSON** — never any biometric data),
///  - which account was last active (the cold-start unlock default),
///  - an "already asked once" flag (so we don't nag after login).
class BiometricTokenStore {
  BiometricTokenStore._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _kAccounts = 'biometric_accounts';
  static const _kLastActive = 'biometric_last_active';
  static const _kPrompted = 'biometric_prompted';

  /// Set by an intentional account switch around its sign-out + recover
  /// step, so bootstrap.dart's reactive signedOut listener (which otherwise
  /// forgets whichever account just signed out) skips that one sign-out
  /// instead of un-remembering the account being switched TO.
  static bool switchingAccounts = false;

  static Future<List<RememberedAccount>> listAccounts() async {
    final raw = await _storage.read(key: _kAccounts);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => RememberedAccount.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveAccounts(List<RememberedAccount> accounts) =>
      _storage.write(key: _kAccounts, value: jsonEncode(accounts.map((a) => a.toJson()).toList()));

  static Future<bool> isEnabled() async => (await listAccounts()).isNotEmpty;

  static Future<bool> isEnabledFor(String userId) async =>
      (await listAccounts()).any((a) => a.userId == userId);

  /// Remembers (or updates) one account's quick-login session, leaving
  /// every other already-remembered account untouched.
  static Future<void> remember({
    required String userId, required String email, required String sessionJson,
    String? fullName, String? avatarUrl,
  }) async {
    final accounts = await listAccounts();
    accounts.removeWhere((a) => a.userId == userId);
    accounts.add(RememberedAccount(
      userId: userId, email: email, sessionJson: sessionJson, fullName: fullName, avatarUrl: avatarUrl));
    await _saveAccounts(accounts);
    await _storage.write(key: _kLastActive, value: userId);
  }

  static Future<RememberedAccount?> byUserId(String userId) async {
    for (final a in await listAccounts()) {
      if (a.userId == userId) return a;
    }
    return null;
  }

  static Future<RememberedAccount?> byEmail(String email) async {
    for (final a in await listAccounts()) {
      if (a.email.toLowerCase() == email.toLowerCase()) return a;
    }
    return null;
  }

  static Future<String?> lastActiveUserId() => _storage.read(key: _kLastActive);

  static Future<RememberedAccount?> lastActiveAccount() async {
    final id = await lastActiveUserId();
    return id == null ? null : byUserId(id);
  }

  static Future<void> setLastActive(String userId) => _storage.write(key: _kLastActive, value: userId);

  /// Forgets ONE account — used both for an explicit "forget this account"
  /// and by bootstrap.dart's reactive sign-out wipe, which only removes the
  /// account that actually just signed out, not the whole remembered list.
  static Future<void> forget(String userId) async {
    final accounts = await listAccounts();
    accounts.removeWhere((a) => a.userId == userId);
    await _saveAccounts(accounts);
    if (await lastActiveUserId() == userId) await _storage.delete(key: _kLastActive);
  }

  /// Wipes every remembered account. Not called anywhere by default anymore
  /// (a plain logout now only forgets the one account that logged out) —
  /// kept for an explicit "forget all devices/accounts" action if ever added.
  static Future<void> forgetAll() async {
    await _storage.delete(key: _kAccounts);
    await _storage.delete(key: _kLastActive);
  }

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
