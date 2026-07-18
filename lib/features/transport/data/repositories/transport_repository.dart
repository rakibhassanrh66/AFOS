import '../../../../config/supabase_config.dart';
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

  Future<List<Map<String, dynamic>>> fetchStops(String routeId) async {
    final res = await _client
        .from('transport_stops')
        .select()
        .eq('route_id', routeId)
        .order('stop_order') as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// The current import's metadata (semester + imported_at) for the "Schedule
  /// for <semester> · Updated <date>" header. Null if nothing imported yet.
  Future<Map<String, dynamic>?> fetchCurrentMeta() async {
    try {
      final res = await _client
          .from('transport_schedule_meta')
          .select()
          .eq('is_current', true)
          .order('imported_at', ascending: false)
          .limit(1) as List;
      return res.isNotEmpty ? Map<String, dynamic>.from(res.first) : null;
    } catch (_) {
      return null;
    }
  }
}
