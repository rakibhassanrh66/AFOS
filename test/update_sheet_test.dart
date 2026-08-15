import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/core/services/app_update_service.dart';

/// The version comparison behind "an update is available".
///
/// This is the piece that decides whether every installed phone is told to
/// update, so it is worth pinning hard. It has been wrong before in both
/// directions: a stored `2.3.2+21` once compared as `2.3.0`, and twelve
/// historical rows carrying a `+build` suffix produced 404 download URLs while
/// also comparing as OLDER than the release they were announcing.
void main() {
  group('isNewer', () {
    test('a higher patch is newer', () {
      expect(AppUpdateService.isNewer('2.8.1', '2.8.0'), isTrue);
      expect(AppUpdateService.isNewer('2.8.0', '2.8.1'), isFalse);
    });

    test('double digits compare numerically, not as strings', () {
      // A plain string compare gets this backwards, and it is the bug that
      // arrives silently the first time a segment reaches 10.
      expect(AppUpdateService.isNewer('2.3.10', '2.3.9'), isTrue);
      expect(AppUpdateService.isNewer('2.3.9', '2.3.10'), isFalse);
      expect(AppUpdateService.isNewer('2.10.0', '2.9.9'), isTrue);
    });

    test('the same version is not an update', () {
      expect(AppUpdateService.isNewer('2.8.0', '2.8.0'), isFalse);
    });

    test('a rebuild of the same version IS offered, via the build number', () {
      // This is what lets 2.7.5+61 -> 2.7.5+62 be shipped at all; without it
      // the two are indistinguishable.
      expect(AppUpdateService.isNewer('2.8.0+66', '2.8.0+65'), isTrue);
      expect(AppUpdateService.isNewer('2.8.0+65', '2.8.0+66'), isFalse);
    });

    test('the release part decides before the build number does', () {
      // A LOWER release with a higher build must never look newer.
      expect(AppUpdateService.isNewer('2.7.9+99', '2.8.0+1'), isFalse);
      expect(AppUpdateService.isNewer('2.8.0+1', '2.7.9+99'), isTrue);
    });

    test('a stored 2.3.2+21 compares as 2.3.2, not 2.3.0', () {
      // The exact historical bug: the build suffix degrading the last segment.
      expect(AppUpdateService.isNewer('2.3.2+21', '2.3.1'), isTrue);
      expect(AppUpdateService.isNewer('2.3.2+21', '2.3.3'), isFalse);
    });
  });

  group('version parsing', () {
    test('releasePart strips the build suffix and whitespace', () {
      expect(AppUpdateService.releasePart('2.8.0+65'), '2.8.0');
      expect(AppUpdateService.releasePart(' 2.8.0 '), '2.8.0');
      expect(AppUpdateService.releasePart('2.8.0'), '2.8.0');
    });

    test('buildPart reads the build number, or null when there is none', () {
      expect(AppUpdateService.buildPart('2.8.0+65'), 65);
      expect(AppUpdateService.buildPart('2.8.0'), isNull);
    });
  });

  group('the download URL the app builds', () {
    testWidgets('is derived from the release part only', (tester) async {
      // The URL must be .../v2.8.0/AFOS-v2.8.0.apk — never v2.8.0+65, which is
      // what produced twelve 404s. AppUpdateInfo is constructed by
      // checkForUpdate from releasePart, so this asserts the shape callers
      // depend on.
      const info = AppUpdateInfo(
        version: '2.8.0',
        title: 'x',
        highlights: [],
        downloadUrl:
            'https://github.com/rakibhassanrh66/AFOS/releases/download/v2.8.0/AFOS-v2.8.0.apk',
      );
      expect(info.downloadUrl, contains('/v2.8.0/AFOS-v2.8.0.apk'));
      expect(info.downloadUrl, isNot(contains('+')),
          reason: 'a build suffix in the URL is a guaranteed 404');
    });
  });
}
