import 'dart:async';
import '../services/connectivity_service.dart';
import '../services/local_cache_service.dart';

/// Thrown when a list fetch is skipped because the device is offline and there
/// is nothing cached to serve instead.
///
/// Exists so this case reaches the user as an offline notice with a retry,
/// rather than as an empty list that every screen renders as a calm "nothing
/// here yet". Mapped to its user-facing text in `friendlyError`.
class OfflineNoDataException implements Exception {
  const OfflineNoDataException();
  @override
  String toString() => 'OfflineNoDataException';
}

/// Wraps a live Supabase `.stream()`-backed query with a local cache: emits
/// the last-cached rows immediately (if any), then subscribes to the live
/// stream only while online. Without this, a `.stream()` never emits at all
/// with no connection, leaving the screen's loading shimmer showing forever
/// while offline instead of the last-known data.
///
/// `.asBroadcastStream()` on the way out: an `async*` generator is
/// single-subscription by default, and several screens call this fresh
/// inside build() as a StreamBuilder's `stream:` argument — a second
/// listener attaching before the first one's teardown fully completes (e.g.
/// widget rebuild churn, or fast navigation away/back) throws "Bad state:
/// Stream has already been listened to." live-crashed on schedule_screen.dart
/// even after memoizing the stream reference, tracing back to this shared
/// root, not the call site. Broadcast semantics make a second `.listen()`
/// structurally safe instead of chasing every call site that might re-enter.
Stream<List<Map<String, dynamic>>> cachedListStream({
  required String cacheKey,
  required Stream<List<Map<String, dynamic>>> Function() liveStream,
}) {
  return _cachedListStreamImpl(cacheKey: cacheKey, liveStream: liveStream).asBroadcastStream();
}

Stream<List<Map<String, dynamic>>> _cachedListStreamImpl({
  required String cacheKey,
  required Stream<List<Map<String, dynamic>>> Function() liveStream,
}) async* {
  final cached = LocalCacheService.instance.getList(cacheKey);
  if (cached != null) yield cached.data;
  if (!ConnectivityService.instance.isOnline.value) return;
  await for (final rows in liveStream()) {
    unawaited(LocalCacheService.instance.putList(cacheKey, rows));
    yield rows;
  }
}

/// Same idea for a one-shot fetch: serves the cache immediately while
/// offline, refreshes the cache on a successful online fetch, and falls back
/// to the cache when a live fetch fails.
///
/// A FAILED FETCH WITH NOTHING CACHED RETHROWS. It used to return `[]`, which
/// made "the query blew up" and "you genuinely own nothing" produce the exact
/// same screen: a calm empty state. That is how a teacher's My Course
/// Offerings page could sit there reading "No offerings yet" while the database
/// held two of their courses, with no error, no retry and nothing to report —
/// the caller had already handled the error case and simply never saw one.
///
/// Every caller here already runs inside a `try` that renders an ErrorView with
/// a retry, so rethrowing costs nothing and turns a silent wrong answer into a
/// visible, recoverable one. Cached rows are still preferred over an error when
/// they exist, so genuine offline use is unchanged.
Future<List<Map<String, dynamic>>> cachedListFetch({
  required String cacheKey,
  required Future<List<Map<String, dynamic>>> Function() liveFetch,
}) async {
  if (!ConnectivityService.instance.isOnline.value) {
    // Never act on the cached flag alone. It is set once before the first frame
    // and only updated on a transport TRANSITION, so a wrong reading at startup
    // persists for the whole session -- and the cost of believing it here is a
    // screen that renders empty with no error and no retry. One re-read of the
    // platform state is cheap; see ConnectivityService.recheck.
    final online = await ConnectivityService.instance.recheck();
    if (!online) {
      final cached = LocalCacheService.instance.getList(cacheKey)?.data;
      // Same reasoning as the failed-fetch path below: returning `[]` here made
      // "we never even tried" indistinguishable from "you genuinely own
      // nothing". The caller renders a calm empty state either way and the user
      // has nothing to retry.
      if (cached == null) throw const OfflineNoDataException();
      return cached;
    }
  }
  try {
    final fresh = await liveFetch();
    await LocalCacheService.instance.putList(cacheKey, fresh);
    return fresh;
  } catch (_) {
    final cached = LocalCacheService.instance.getList(cacheKey)?.data;
    if (cached != null) return cached;
    rethrow;
  }
}

/// Single-object variant of [cachedListFetch] (e.g. a `.single()` profile
/// fetch) — returns null only when there's genuinely neither a live result
/// nor a cached one.
///
/// Deliberately still lenient where [cachedListFetch] now rethrows: what this
/// returns is a decoration, not the page. `fetchActiveTerm()` is its main
/// caller and both of ITS callers already treat null as "no term label to
/// show" — making a missing semester name take down the whole My Course
/// Offerings load would be the same class of mistake in the other direction.
Future<Map<String, dynamic>?> cachedMapFetch({
  required String cacheKey,
  required Future<Map<String, dynamic>> Function() liveFetch,
}) async {
  if (!ConnectivityService.instance.isOnline.value) {
    return LocalCacheService.instance.getMap(cacheKey)?.data;
  }
  try {
    final fresh = await liveFetch();
    await LocalCacheService.instance.putMap(cacheKey, fresh);
    return fresh;
  } catch (_) {
    return LocalCacheService.instance.getMap(cacheKey)?.data;
  }
}
