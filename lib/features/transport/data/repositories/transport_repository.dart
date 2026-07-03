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
}
