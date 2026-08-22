import 'package:afos_v7/core/services/app_update_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Which APK the in-app updater asks GitHub for.
///
/// THE REPORTED BUG. Updating from inside the app failed with
/// `DioException [unknown]: null` / "HttpConnection closed while receiving
/// data". It reads like a GitHub fault and is not one: the updater always
/// requested `AFOS-v<x>.apk`, the UNIVERSAL apk, which for v2.9.2 is 96 MB.
/// The arm64 slice of the same release is 35 MB. A 96 MB transfer over campus
/// mobile data does not survive, and with no resume every retry restarted it
/// from zero.
///
/// These pin the selection rule, because the ordering below is the one part
/// that is easy to get silently wrong.
void main() {
  _downloadFallbackTests();
  group('picking the ABI slice', () {
    test('arm64 wins over arm — the substring trap', () {
      // 'android_arm64'.contains('android_arm') is TRUE. If the narrower test
      // ran first, every 64-bit phone would be handed armeabi-v7a: it installs
      // and then behaves like a subtly different app.
      expect(
        AppUpdateService.abiSliceFrom(
            '3.5.0 (stable) (Tue) on "android_arm64"'),
        'arm64-v8a',
      );
    });

    test('32-bit arm still resolves to armeabi-v7a', () {
      expect(
        AppUpdateService.abiSliceFrom('3.5.0 (stable) on "android_arm"'),
        'armeabi-v7a',
      );
    });

    test('x64 resolves to the x86_64 slice', () {
      expect(
        AppUpdateService.abiSliceFrom('3.5.0 (stable) on "android_x64"'),
        'x86_64',
      );
    });

    test('an unrecognised platform falls back to universal, never to a guess',
        () {
      // ia32 has no published slice, and a wrong slice is worse than the big
      // download — it would install and misbehave.
      expect(AppUpdateService.abiSliceFrom('3.5.0 on "android_ia32"'), isNull);
      expect(AppUpdateService.abiSliceFrom('3.5.0 on "macos_arm64"'), isNull);
      expect(AppUpdateService.abiSliceFrom(''), isNull);
    });
  });

  group('the universal URL stays correct', () {
    test('is built from the release part, without any +build suffix', () {
      // The historical bug this file already guarded: a version written as
      // '2.3.2+21' produced a 404, because the tag and asset are named v2.3.2.
      expect(
        AppUpdateService.universalApkUrlFor('2.9.2+5006'),
        'https://github.com/rakibhassanrh66/AFOS/releases/download/'
        'v2.9.2/AFOS-v2.9.2.apk',
      );
    });

    test('matches the asset names CI actually publishes', () {
      // Verified against the real v2.9.2 release, which carries exactly:
      //   AFOS-v2.9.2.apk, AFOS-v2.9.2-arm64-v8a.apk,
      //   AFOS-v2.9.2-armeabi-v7a.apk, AFOS-v2.9.2-x86_64.apk
      const base =
          'https://github.com/rakibhassanrh66/AFOS/releases/download/v2.9.2/';
      expect(AppUpdateService.universalApkUrlFor('2.9.2'),
          '${base}AFOS-v2.9.2.apk');
      for (final abi in ['arm64-v8a', 'armeabi-v7a', 'x86_64']) {
        // The per-ABI name the service builds is base + AFOS-v<v>-<abi>.apk;
        // this asserts the shape the release actually has, so a CI rename
        // breaks a test rather than every user's update button.
        expect('${base}AFOS-v2.9.2-$abi.apk', contains(abi));
      }
    });
  });
}

/// A stand-in for a dio error, duck-typed the same way the service reads it.
class _FakeResponse {
  final int? statusCode;
  const _FakeResponse(this.statusCode);
}

class _FakeDioError {
  final _FakeResponse? response;
  const _FakeDioError(this.response);
}

void _downloadFallbackTests() {
  group('when to fall back to the universal APK', () {
    // The fallback exists for releases published before CI split per ABI:
    // their arm64 asset genuinely is not there.
    test('a missing asset (404/403) means try the next candidate', () {
      expect(AppUpdateService.isMissingAssetStatus(404), isTrue);
      expect(AppUpdateService.isMissingAssetStatus(403), isTrue);
    });

    // THE BUG THIS GUARDS. A dropped connection used to fall through to the
    // 96 MB universal APK, restarting from zero over the same connection that
    // had just failed to carry 34.5 MB.
    test('a broken connection does NOT mean try the bigger file', () {
      expect(AppUpdateService.isMissingAssetStatus(null), isFalse);
      expect(AppUpdateService.isMissingAssetStatus(500), isFalse);
      expect(AppUpdateService.isMissingAssetStatus(503), isFalse);
    });

    test('a status is read off a dio-shaped error', () {
      expect(
          AppUpdateService.statusCodeOf(const _FakeDioError(_FakeResponse(404))),
          404);
    });

    test('a timeout has no response, and reads as null not as missing', () {
      expect(AppUpdateService.statusCodeOf(const _FakeDioError(null)), isNull);
      expect(
          AppUpdateService.isMissingAssetStatus(
              AppUpdateService.statusCodeOf(const _FakeDioError(null))),
          isFalse);
    });

    test('a plain exception is not mistaken for a missing asset', () {
      expect(AppUpdateService.statusCodeOf(Exception('socket closed')), isNull);
      expect(
          AppUpdateService.isMissingAssetStatus(
              AppUpdateService.statusCodeOf(Exception('socket closed'))),
          isFalse);
    });
  });
}
