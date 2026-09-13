import '../../../../config/supabase_config.dart';
import '../../../../core/services/connectivity_service.dart';
import '../../../../core/utils/offline_cache.dart';

/// Mirrors the realtime pattern used by ScheduleRepository.watchSchedule —
/// keeps transport_routes live so admin uploads (parse-routine edge
/// function) appear to students/teachers without a manual refresh.
class TransportRepository {
  final _client = SupabaseConfig.client;

  /// Cached for offline viewing — deliberately NOT watchLiveStatus below,
  /// since a stale cached bus GPS position offline would be actively
  /// misleading rather than merely unavailable.
  Stream<List<Map<String, dynamic>>> watchRoutes() {
    return cachedListStream(
      cacheKey: 'transport_routes',
      liveStream: () => _client
          .from('transport_routes')
          .stream(primaryKey: ['id'])
          .order('route_number')
          .map((list) => list.where((r) => r['is_active'] == true)
              .map((r) => Map<String, dynamic>.from(r)).toList()),
    );
  }

  /// Latest status row per route, keyed by route_id — there's no explicit
  /// "current" flag on transport_live_status, so the most recently
  /// updated row per route is treated as the live one.
  Stream<Map<String, Map<String, dynamic>>> watchLiveStatus() {
    // .asBroadcastStream() -- this bypasses cachedListStream (deliberately,
    // see the comment above watchRoutes), so it doesn't get that helper's
    // broadcast wrapping; a raw Supabase .stream() is single-subscription,
    // same class of "already listened to" risk fixed at the root in
    // offline_cache.dart's cachedListStream.
    return _client
        .from('transport_live_status')
        .stream(primaryKey: ['id'])
        .order('updated_at', ascending: false)
        .map((rows) {
      final byRoute = <String, Map<String, dynamic>>{};
      for (final r in rows) {
        final routeId = r['route_id'] as String?;
        if (routeId != null && !byRoute.containsKey(routeId)) byRoute[routeId] = r;
      }
      return byRoute;
    }).asBroadcastStream();
  }

  /// Cached per route: was a plain uncached fetch, so the Map tab specifically
  /// (the only consumer of this) went blank offline even though watchRoutes
  /// above — every OTHER Transport tab's data source — already falls back to
  /// its last-known rows. Stop coordinates change only on a routine
  /// re-upload, so a slightly-stale cached path is a reasonable trade for not
  /// losing the map entirely.
  Future<List<Map<String, dynamic>>> fetchStops(String routeId) => cachedListFetch(
        cacheKey: 'transport_stops_$routeId',
        liveFetch: () async {
          final res = await _client
              .from('transport_stops')
              .select()
              .eq('route_id', routeId)
              .order('stop_order') as List;
          return res.cast<Map<String, dynamic>>();
        },
      );

  /// The current import's metadata (semester + imported_at) for the "Schedule
  /// for <semester> · Updated <date>" header. Null if nothing imported yet.
  ///
  /// Cached (Tier 1, offline policy): this was the one piece of the Map tab
  /// left uncached when fetchStops was fixed — the header blanked offline
  /// even though the stops it labels did not.
  Future<Map<String, dynamic>?> fetchCurrentMeta() => cachedMapFetch(
        cacheKey: 'transport_current_meta',
        liveFetch: () async {
          final res = await _client
              .from('transport_schedule_meta')
              .select()
              .eq('is_current', true)
              .order('imported_at', ascending: false)
              .limit(1) as List;
          if (res.isEmpty) throw StateError('no transport meta yet');
          return Map<String, dynamic>.from(res.first);
        },
      );

  /// Bulk offline prefetch (Phase C, offline policy): after this device has
  /// been online once, warms the per-route stop cache for EVERY active
  /// route, not only the one a user happened to open. Before this, a route
  /// nobody had tapped while online simply had nothing cached — "only the
  /// route someone loaded is available offline". Fire-and-forget by design:
  /// a slow or failing route must never block opening Transport, and one
  /// route's failure must not stop the rest from warming.
  Future<void> prefetchAllStops() async {
    if (!ConnectivityService.instance.isOnline.value) return;
    try {
      final routes = await _client
          .from('transport_routes')
          .select('id')
          .eq('is_active', true) as List;
      for (final r in routes) {
        final id = (r as Map)['id'] as String?;
        if (id == null) continue;
        try {
          await fetchStops(id);
        } catch (_) {
          // Best-effort per route — one bad route must not stop the rest.
        }
      }
    } catch (_) {
      // Best-effort overall — this is a background warmer, not a load path.
    }
  }
}
