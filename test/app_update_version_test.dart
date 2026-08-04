import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/core/services/app_update_service.dart';

/// Pins the version handling behind the in-app updater.
///
/// This is the logic that decides BOTH whether an update is offered and what
/// URL it is downloaded from, and it was silently wrong for twelve of the
/// fifteen rows in `app_releases`.
void main() {
  group('releasePart', () {
    // THE BUG. `app_releases.version` kept being written with the build number
    // (`2.3.2+21`, `2.1.0+17`, and four more are still in the table). The
    // download URL is built from this string, and the git tag / release asset
    // are named `v2.3.2` / `AFOS-v2.3.2.apk` — so every one of those rows sent
    // the user to a 404, which the app surfaced as a failed update.
    test('drops the build suffix', () {
      expect(AppUpdateService.releasePart('2.3.2+21'), '2.3.2');
      expect(AppUpdateService.releasePart('2.7.5+61'), '2.7.5');
    });

    test('leaves a clean version alone', () {
      expect(AppUpdateService.releasePart('2.6.2'), '2.6.2');
    });

    test('tolerates whitespace', () {
      expect(AppUpdateService.releasePart(' 2.6.2 '), '2.6.2');
    });
  });

  group('buildPart', () {
    test('reads the build number when present', () {
      expect(AppUpdateService.buildPart('2.7.5+61'), 61);
    });

    test('is null when there is none', () {
      expect(AppUpdateService.buildPart('2.7.5'), isNull);
    });
  });

  group('isNewer', () {
    test('compares segments numerically, not as strings', () {
      // A string compare gets this backwards: '9' > '1' lexicographically.
      expect(AppUpdateService.isNewer('2.3.10', '2.3.9'), isTrue);
      expect(AppUpdateService.isNewer('2.3.9', '2.3.10'), isFalse);
    });

    // THE SECOND HALF OF THE BUG. `'2.3.2+21'.split('.')` makes the last
    // segment the string '2+21'; int.tryParse returns null and it counted as
    // 0 — so the stored version compared as 2.3.0, i.e. OLDER than the release
    // it was announcing, and the update was never offered.
    test('a stored +build version is not degraded to .0', () {
      expect(AppUpdateService.isNewer('2.3.2+21', '2.3.1'), isTrue,
          reason: '2.3.2+21 must compare as 2.3.2, not 2.3.0');
      expect(AppUpdateService.isNewer('2.3.2+21', '2.3.2'), isFalse,
          reason: 'same release, and the local side has no build to compare');
    });

    test('the build number breaks a tie when both sides have one', () {
      expect(AppUpdateService.isNewer('2.7.5+62', '2.7.5+61'), isTrue);
      expect(AppUpdateService.isNewer('2.7.5+61', '2.7.5+61'), isFalse);
      expect(AppUpdateService.isNewer('2.7.5+60', '2.7.5+61'), isFalse);
    });

    test('an older release is never offered', () {
      // The live table's newest row was 2.5.5 while the app was on 2.7.5.
      expect(AppUpdateService.isNewer('2.5.5', '2.7.5'), isFalse);
    });

    test('a shorter version string is padded, not misread', () {
      expect(AppUpdateService.isNewer('3', '2.9.9'), isTrue);
      expect(AppUpdateService.isNewer('2.9', '2.9.0'), isFalse);
    });
  });
}
