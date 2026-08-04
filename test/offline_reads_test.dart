import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:afos_v7/core/services/connectivity_service.dart';
import 'package:afos_v7/core/services/local_cache_service.dart';
import 'package:afos_v7/core/utils/error_formatter.dart';
import 'package:afos_v7/core/utils/offline_cache.dart';

/// Guards the two faults that made loaded screens render as empty ones.
///
/// Neither had a test, and both are a single character away from returning.
void main() {
  group('resolveConnectivity', () {
    // THE BUG. This was `results.any((r) => r != none)`, and `Iterable.any`
    // answers `false` for an empty list. connectivity_plus returns `[]` rather
    // than `[none]` on some Android configurations, so a device with perfectly
    // good network resolved to OFFLINE before the first frame — and because the
    // change stream only fires on a transport TRANSITION, nothing ever
    // corrected it. Downstream, cachedListFetch skips the network while
    // offline, so every cached screen served an empty list and rendered its
    // "nothing here yet" state over a database full of the user's data.
    test('an empty list is ONLINE, not offline', () {
      expect(ConnectivityService.resolveConnectivity(const []), isTrue,
          reason: 'the platform told us nothing; "unknown" must fail towards '
              'attempting the fetch, not towards showing an empty page');
    });

    test('an explicit none is offline', () {
      expect(
          ConnectivityService.resolveConnectivity(const [ConnectivityResult.none]),
          isFalse);
    });

    test('any live transport is online', () {
      for (final r in const [
        ConnectivityResult.wifi,
        ConnectivityResult.mobile,
        ConnectivityResult.ethernet,
      ]) {
        expect(ConnectivityService.resolveConnectivity([r]), isTrue, reason: '$r');
      }
    });

    test('a mixed list with one live transport is online', () {
      expect(
          ConnectivityService.resolveConnectivity(
              const [ConnectivityResult.none, ConnectivityResult.wifi]),
          isTrue);
    });
  });

  group('friendlyError', () {
    // OfflineNoDataException carries no message of its own, so the class-dump
    // fallback at the bottom of friendlyError would turn it into "Something
    // went wrong — please try again." — the exact dead end it was introduced to
    // replace. It has to be matched ahead of the generic branches.
    test('maps OfflineNoDataException to an offline notice, not the generic', () {
      final msg = friendlyError(const OfflineNoDataException());
      expect(msg, contains('offline'));
      expect(msg, isNot(contains('Something went wrong')));
    });
  });

  group('cachedListFetch', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('afos_cache_test');
      Hive.init(dir.path);
      await Hive.openBox(LocalCacheService.boxName);
    });

    tearDownAll(() async {
      await Hive.close();
      await dir.delete(recursive: true);
    });

    setUp(() async {
      await Hive.box(LocalCacheService.boxName).clear();
      // Online, so these exercise the fetch path rather than the offline branch.
      // The offline branch calls ConnectivityService.recheck(), which needs the
      // connectivity_plus platform channel — resolveConnectivity above is the
      // whole of the decision it makes, and is covered directly.
      ConnectivityService.instance.isOnline.value = true;
    });

    test('a successful fetch is returned and cached', () async {
      final rows = await cachedListFetch(
        cacheKey: 'k',
        liveFetch: () async => [
          {'id': '1'}
        ],
      );
      expect(rows, [
        {'id': '1'}
      ]);
      expect(LocalCacheService.instance.getList('k')?.data, [
        {'id': '1'}
      ]);
    });

    // THE OTHER BUG. This used to `return []` on a failed fetch, which made "the
    // query blew up" and "you genuinely own nothing" produce the identical
    // screen: a calm empty state, with no error and nothing to retry. Every
    // caller already sits inside a try that renders an ErrorView.
    test('a failed fetch with nothing cached RETHROWS rather than returning []',
        () async {
      await expectLater(
        cachedListFetch(
            cacheKey: 'k', liveFetch: () async => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );
    });

    test('a failed fetch prefers the cache over an error', () async {
      await LocalCacheService.instance.putList('k', [
        {'id': 'cached'}
      ]);
      final rows = await cachedListFetch(
          cacheKey: 'k', liveFetch: () async => throw StateError('boom'));
      expect(rows, [
        {'id': 'cached'}
      ]);
    });
  });
}
