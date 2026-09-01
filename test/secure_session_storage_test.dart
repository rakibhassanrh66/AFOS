import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/core/auth/secure_session_storage.dart';

/// A keystore that cannot decrypt must not be able to stop the app.
///
/// THE BUG THIS LOCKS DOWN. `flutter_secure_storage` keeps its ciphertext in
/// ordinary app storage and its key in the Android Keystore, and the two get
/// separated in completely ordinary ways: auto-backup restores the ciphertext
/// to a new phone without the device-bound key, and changing the screen lock
/// or re-enrolling a fingerprint can invalidate the key while the ciphertext
/// stays put. The read then throws BAD_DECRYPT.
///
/// `hasAccessToken` was an unguarded `await _storage.read(...)`, and it is the
/// FIRST thing `SupabaseAuth.initialize` calls. So the throw travelled
/// `hasAccessToken -> Supabase.initialize -> bootstrap -> main`, `runApp` was
/// never reached, and the app hung on Android's launch icon with no crash, no
/// dialog and nothing to tap. Verified on a real device as:
///
///   PlatformException(Exception encountered, read,
///   javax.crypto.BadPaddingException: OPENSSL_internal:BAD_DECRYPT)
///
/// These tests drive the real platform channel that plugin uses, so they fail
/// if the guards are removed from the production class rather than from a copy
/// of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final calls = <String>[];

  void mockStorage({required bool throwOnRead}) {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'read') {
        if (throwOnRead) {
          throw PlatformException(
            code: 'Exception encountered',
            message: 'read',
            details: 'javax.crypto.BadPaddingException: '
                'error:1e000065:Cipher functions:OPENSSL_internal:BAD_DECRYPT',
          );
        }
        return 'a-real-session';
      }
      return null;
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  final storage = SecureSessionLocalStorage(persistSessionKey: 'sb-test-auth-token');

  test('an undecryptable session reports "no session" instead of throwing', () async {
    mockStorage(throwOnRead: true);
    // The assertion is that this RETURNS. Before the fix it threw, and that
    // throw is what never let runApp be reached.
    await expectLater(storage.hasAccessToken(), completion(isFalse));
  });

  test('and it deletes the entry, so the next launch is not the same failure',
      () async {
    mockStorage(throwOnRead: true);
    await storage.hasAccessToken();
    expect(calls, contains('delete'),
        reason: 'an entry that cannot be decrypted can never be decrypted '
            'again; keeping it guarantees the same failure forever');
  });

  test('accessToken survives it too', () async {
    mockStorage(throwOnRead: true);
    await expectLater(storage.accessToken(), completion(isNull));
  });

  test('a healthy keystore still returns the session', () async {
    mockStorage(throwOnRead: false);
    await expectLater(storage.hasAccessToken(), completion(isTrue));
    await expectLater(storage.accessToken(), completion('a-real-session'));
    expect(calls, isNot(contains('delete')),
        reason: 'a readable session must never be discarded');
  });

  test('signing out and persisting cannot throw either', () async {
    mockStorage(throwOnRead: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'wedged', message: call.method);
    });
    // Sign-out must always succeed from the user's side, and failing to
    // REMEMBER a session is a lost convenience, not a reason to crash.
    await expectLater(storage.removePersistedSession(), completes);
    await expectLater(storage.persistSession('x'), completes);
  });
}
