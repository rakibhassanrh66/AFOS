import '../../../../config/supabase_config.dart';

/// Mirrors the realtime pattern used by ScheduleRepository.watchSchedule —
/// keeps transport_routes live so admin uploads (parse-routine edge
/// function) appear to students/teachers without a manual refresh.
class TransportRepository {
  final _client = SupabaseConfig.client;

  Stream<List<Map<String, dynamic>>> watchRoutes() {
    return _client
        .from('transport_routes')
        .stream(primaryKey: ['id'])
        .order('route_number')
        .map((list) => list.where((r) => r['is_active'] == true).toList());
  }

  /// Latest status row per route, keyed by route_id — there's no explicit
  /// "current" flag on transport_live_status, so the most recently
  /// updated row per route is treated as the live one.
  Stream<Map<String, Map<String, dynamic>>> watchLiveStatus() {
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
    });
  }

  Future<List<Map<String, dynamic>>> fetchStops(String routeId) async {
    final res = await _client
        .from('transport_stops')
        .select()
        .eq('route_id', routeId)
        .order('stop_order') as List;
    return res.cast<Map<String, dynamic>>();
  }
}
