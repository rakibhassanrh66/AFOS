import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Briefly holds a just-registered user's credentials so the login screen
/// can prefill them after signup redirects there. Consuming always deletes
/// the stored values so they never linger on disk beyond that one hand-off.
class PendingCredentialsStore {
  PendingCredentialsStore._();
  static const _storage = FlutterSecureStorage();
  static const _emailKey = 'afos_pending_login_email';
  static const _passwordKey = 'afos_pending_login_password';

  static Future<void> save(String email, String password) async {
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _passwordKey, value: password);
  }

  static Future<(String, String)?> consume() async {
    final email = await _storage.read(key: _emailKey);
    final password = await _storage.read(key: _passwordKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _passwordKey);
    if (email == null || password == null) return null;
    return (email, password);
  }
}
