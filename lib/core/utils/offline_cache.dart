import 'dart:async';
import '../services/connectivity_service.dart';
import '../services/local_cache_service.dart';

/// Wraps a live Supabase `.stream()`-backed query with a local cache: emits
/// the last-cached rows immediately (if any), then subscribes to the live
/// stream only while online. Without this, a `.stream()` never emits at all
/// with no connection, leaving the screen's loading shimmer showing forever
/// while offline instead of the last-known data.
Stream<List<Map<String, dynamic>>> cachedListStream({
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
/// offline (or on a failed fetch), refreshes the cache on a successful
/// online fetch.
Future<List<Map<String, dynamic>>> cachedListFetch({
  required String cacheKey,
  required Future<List<Map<String, dynamic>>> Function() liveFetch,
}) async {
  if (!ConnectivityService.instance.isOnline.value) {
    return LocalCacheService.instance.getList(cacheKey)?.data ?? [];
  }
  try {
    final fresh = await liveFetch();
    await LocalCacheService.instance.putList(cacheKey, fresh);
    return fresh;
  } catch (_) {
    return LocalCacheService.instance.getList(cacheKey)?.data ?? [];
  }
}

/// Single-object variant of [cachedListFetch] (e.g. a `.single()` profile
/// fetch) — returns null only when there's genuinely neither a live result
/// nor a cached one.
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
