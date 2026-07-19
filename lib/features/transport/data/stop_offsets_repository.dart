import '../../../config/supabase_config.dart';
import 'stop_time_calculator.dart';

/// Reads/writes the admin-recorded per-stop bus timings
/// (`transport_stop_offsets`). Kept deliberately thin — the interesting logic
/// (what a timing means, and when we're allowed to compute one) lives in
/// [StopTimeCalculator].
class StopOffsetsRepository {
  StopOffsetsRepository._();

  static const _table = 'transport_stop_offsets';

  /// All recorded timings, indexed by [StopOffset.keyFor] for O(1) lookup while
  /// rendering. The table holds at most a few hundred rows (one per stop per
  /// route), so a single fetch is cheaper than per-route queries.
  ///
  /// Returns an empty map on failure rather than throwing: missing timings
  /// degrade the transport screen to its honest route-level wording, which is
  /// strictly better than an error state.
  static Future<Map<String, StopOffset>> fetchAll() async {
    try {
      final rows = await SupabaseConfig.client
          .from(_table)
          .select('route_number, schedule_type, stop_name, minutes_from_origin, minutes_from_dsc');
      final out = <String, StopOffset>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final o = StopOffset.fromRow(r);
        if (o.stopName.isEmpty) continue;
        out[o.key] = o;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Timings for a single route, keyed by lower-cased stop name.
  static Future<Map<String, StopOffset>> fetchForRoute(String routeNumber, String scheduleType) async {
    try {
      final rows = await SupabaseConfig.client
          .from(_table)
          .select('route_number, schedule_type, stop_name, minutes_from_origin, minutes_from_dsc')
          .eq('route_number', routeNumber)
          .eq('schedule_type', scheduleType);
      final out = <String, StopOffset>{};
      for (final r in (rows as List).cast<Map<String, dynamic>>()) {
        final o = StopOffset.fromRow(r);
        if (o.stopName.isEmpty) continue;
        out[o.stopName.toLowerCase()] = o;
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  /// Upserts a route's timings in one round trip, on the
  /// (route_number, schedule_type, stop_name) unique key so re-saving a route
  /// updates rather than duplicates. Rows with nothing recorded are skipped —
  /// an absent row and a row of nulls mean the same thing, and skipping keeps
  /// the table to only what an admin actually filled in.
  ///
  /// Throws on failure so the admin screen can surface a real error instead of
  /// silently claiming a save that didn't happen.
  static Future<int> saveRoute(List<StopOffset> offsets) async {
    final payload = offsets.where((o) => !o.isEmpty).map((o) => o.toRow()).toList();
    if (payload.isEmpty) return 0;
    await SupabaseConfig.client
        .from(_table)
        .upsert(payload, onConflict: 'route_number,schedule_type,stop_name');
    return payload.length;
  }

  /// Clears a single stop's timings (admin corrected an entry back to unknown).
  static Future<void> clearStop(String routeNumber, String scheduleType, String stopName) async {
    await SupabaseConfig.client
        .from(_table)
        .delete()
        .eq('route_number', routeNumber)
        .eq('schedule_type', scheduleType)
        .eq('stop_name', stopName);
  }
}
