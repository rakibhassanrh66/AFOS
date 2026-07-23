import '../../../config/supabase_config.dart';
import 'models/transport_schedule.dart';

enum IssueLevel { ok, warning, error }

class RouteIssue {
  final String routeNo;
  final ScheduleType type;
  final IssueLevel level;
  final String message;
  const RouteIssue(this.routeNo, this.type, this.level, this.message);
}

/// The QA gate: every parsed route is validated BEFORE anything is written, so
/// missing/unparseable data is surfaced for admin review in the upload screen
/// instead of being silently persisted (the actual root cause of the old
/// "database is wrong" problem).
class TransportValidation {
  final List<RouteIssue> issues;
  const TransportValidation(this.issues);

  bool get hasErrors => issues.any((i) => i.level == IssueLevel.error);
  bool get hasWarnings => issues.any((i) => i.level == IssueLevel.warning);
  int get errorCount => issues.where((i) => i.level == IssueLevel.error).length;
  int get warningCount => issues.where((i) => i.level == IssueLevel.warning).length;

  IssueLevel levelFor(TransportRoute r) {
    var worst = IssueLevel.ok;
    for (final i in issues) {
      if (i.routeNo == r.routeNo && i.type == r.scheduleType) {
        if (i.level == IssueLevel.error) return IssueLevel.error;
        if (i.level == IssueLevel.warning) worst = IssueLevel.warning;
      }
    }
    return worst;
  }

  List<String> messagesFor(TransportRoute r) => issues
      .where((i) => i.routeNo == r.routeNo && i.type == r.scheduleType && i.level != IssueLevel.ok)
      .map((i) => i.message)
      .toList();
}

class TransportImportService {
  TransportImportService._();

  static TransportValidation validate(ParsedTransportSchedule parsed) {
    final issues = <RouteIssue>[];
    final seen = <String>{};

    for (final r in parsed.routes) {
      final key = '${r.scheduleType.wire}|${r.routeNo}';
      if (!seen.add(key)) {
        issues.add(RouteIssue(r.routeNo, r.scheduleType, IssueLevel.error,
            'Duplicate ${r.routeNo} in the ${r.scheduleType.label} section'));
      }

      final to = r.toDscTrips.where((t) => !t.isEmpty).toList();
      final from = r.fromDscTrips.where((t) => !t.isEmpty).toList();

      if (to.isEmpty && from.isEmpty) {
        issues.add(RouteIssue(r.routeNo, r.scheduleType, IssueLevel.error,
            'No trip times found for either direction'));
      } else if (to.isEmpty) {
        issues.add(RouteIssue(r.routeNo, r.scheduleType, IssueLevel.warning, 'No "To DSC" times'));
      } else if (from.isEmpty) {
        issues.add(RouteIssue(r.routeNo, r.scheduleType, IssueLevel.warning, 'No "From DSC" times'));
      }

      // Trips that carry a note but no time and aren't "coming soon" are
      // unparseable times worth a human look.
      final unparseable = [...r.toDscTrips, ...r.fromDscTrips]
          .where((t) => t.time == null && t.status == TripStatus.scheduled && (t.note?.isNotEmpty ?? false));
      if (unparseable.isNotEmpty) {
        issues.add(RouteIssue(r.routeNo, r.scheduleType, IssueLevel.warning,
            'Some times could not be read: ${unparseable.map((t) => t.note).join('; ')}'));
      }

      if (r.stops.isEmpty) {
        issues.add(RouteIssue(r.routeNo, r.scheduleType, IssueLevel.warning, 'No stops listed'));
      }
      if (r.routeName.trim().isEmpty) {
        issues.add(RouteIssue(r.routeNo, r.scheduleType, IssueLevel.warning, 'Missing route name'));
      }
    }

    if (parsed.routes.isEmpty) {
      issues.add(const RouteIssue('—', ScheduleType.regular, IssueLevel.error,
          'No routes were parsed from this file'));
    }
    return TransportValidation(issues);
  }

  /// Writes the validated schedule under the caller's admin RLS
  /// (`admin_write_routes` / `admin_write_transport_meta`). Upserts every route
  /// on the (semester, schedule_type, route_number) key, removes routes for
  /// this semester that are no longer present, and records the import metadata.
  static Future<void> write(ParsedTransportSchedule parsed) async {
    final client = SupabaseConfig.client;
    final now = DateTime.now().toIso8601String();
    final semester = parsed.semester;

    final rows = parsed.routes.map((r) => {
          ...r.toRouteRow(),
          'imported_at': now,
          'updated_at': now,
        }).toList();

    if (rows.isNotEmpty) {
      await client.from('transport_routes').upsert(
            rows,
            onConflict: 'semester,schedule_type,route_number',
          );
    }

    // Mirror each route's ordered stop list into `transport_stops`.
    //
    // This step never existed. The importer only ever wrote the `stops` jsonb
    // on `transport_routes`, so `transport_stops` was populated exactly once by
    // a legacy import and never again — which is why `fetchStops()` returned an
    // empty list for every route and the map could not draw a thing.
    //
    // `transport_stops` is the row-per-stop form the map reads (it is where
    // latitude/longitude live), so it has to be kept in step with every upload
    // or it goes stale the moment a route's stops change.
    await _syncStops(parsed);

    // Remove stale routes for this semester (schedule_type,route_number no
    // longer in the file). Fetch current, diff, delete by id.
    final existing = await client
        .from('transport_routes')
        .select('id, schedule_type, route_number')
        .eq('semester', semester) as List;
    final keep = parsed.routes.map((r) => '${r.scheduleType.wire}|${r.routeNo}').toSet();
    final staleIds = existing
        .where((e) => !keep.contains('${e['schedule_type']}|${e['route_number']}'))
        .map((e) => e['id'])
        .toList();
    for (final id in staleIds) {
      await client.from('transport_routes').delete().eq('id', id);
    }

    // Record import metadata; mark this the current schedule.
    await client.from('transport_schedule_meta').update({'is_current': false}).eq('is_current', true);
    await client.from('transport_schedule_meta').insert({
      'semester': semester,
      'campus': parsed.campus,
      'imported_at': now,
      'uploaded_by': SupabaseConfig.uid,
      'is_current': true,
    });
  }

  /// Mirrors each imported route's ordered stop list into `transport_stops`,
  /// the row-per-stop table the map reads (and the only place latitude /
  /// longitude can live).
  ///
  /// Deliberately **preserves existing coordinates**: a stop that already has
  /// lat/long keeps it, because geocoding is expensive and manual corrections
  /// must survive a routine re-upload. Only the name and ordering are refreshed.
  ///
  /// Rows are keyed on (route_id, stop_order) — the natural key added in
  /// migration `20260722072545`, which is also what makes this upsert idempotent
  /// rather than duplicating the whole list on every import.
  static Future<void> _syncStops(ParsedTransportSchedule parsed) async {
    final client = SupabaseConfig.client;

    // Resolve the ids of the routes just written, so stops attach to the right
    // parent even on a first-time import where the caller has no ids yet.
    final saved = await client
        .from('transport_routes')
        .select('id, schedule_type, route_number')
        .eq('semester', parsed.semester) as List;
    final idByKey = {
      for (final r in saved) '${r['schedule_type']}|${r['route_number']}': r['id'] as String,
    };

    final stopRows = <Map<String, dynamic>>[];
    final routeIds = <String>[];
    for (final route in parsed.routes) {
      final routeId = idByKey['${route.scheduleType.wire}|${route.routeNo}'];
      if (routeId == null) continue;
      routeIds.add(routeId);
      for (var i = 0; i < route.stops.length; i++) {
        final name = route.stops[i].trim();
        if (name.isEmpty) continue;
        stopRows.add({
          'route_id': routeId,
          'stop_name': name,
          // 1-based, matching the backfill migration.
          'stop_order': i + 1,
        });
      }
    }

    if (stopRows.isNotEmpty) {
      await client.from('transport_stops').upsert(stopRows, onConflict: 'route_id,stop_order');
    }

    // Drop stops left over from a previous, longer version of a route —
    // upserting alone would leave the tail of the old list orphaned in place.
    for (final routeId in routeIds) {
      final count = stopRows.where((s) => s['route_id'] == routeId).length;
      await client.from('transport_stops').delete().eq('route_id', routeId).gt('stop_order', count);
    }
  }
}
