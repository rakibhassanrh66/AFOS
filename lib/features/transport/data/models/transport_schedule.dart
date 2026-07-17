/// Normalized transport-schedule model — the single clean shape both the
/// Excel importer (primary) and the PDF fallback parse into, and what the
/// upload validation + Supabase write operate on.
library;

/// The one canonical campus destination. "DSC" (Route Name column) and
/// "Daffodil Smart City" (last stop in Route Details) are the SAME place and
/// must never be shown as two stops.
const String kCanonicalDestination = 'Daffodil Smart City';

enum TripStatus { scheduled, comingSoon }

extension TripStatusX on TripStatus {
  String get wire => this == TripStatus.comingSoon ? 'coming_soon' : 'scheduled';
  static TripStatus fromWire(String? s) =>
      s == 'coming_soon' ? TripStatus.comingSoon : TripStatus.scheduled;
}

/// One trip instance for a route in one direction. Multiple trips stack in the
/// Start/Departure columns of a route block.
class Trip {
  /// Canonical display time, e.g. "7:00 AM". Null when [status] is comingSoon.
  final String? time;

  /// Per-trip note/exception extracted from a parenthetical, e.g.
  /// "Students bus", "Only 1 Bus Assigned For ECB". Kept verbatim (typos and
  /// all) so nothing meaningful is lost.
  final String? note;

  final TripStatus status;

  const Trip({this.time, this.note, this.status = TripStatus.scheduled});

  bool get isComingSoon => status == TripStatus.comingSoon;

  /// True when this carries neither a time nor a coming-soon marker — i.e.
  /// nothing worth persisting (blank cell).
  bool get isEmpty => time == null && status == TripStatus.scheduled && (note == null || note!.isEmpty);

  Map<String, dynamic> toJson() => {
        'time': time,
        'note': note,
        'status': status.wire,
      };

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        time: j['time'] as String?,
        note: j['note'] as String?,
        status: TripStatusX.fromWire(j['status'] as String?),
      );

  @override
  String toString() => 'Trip(${status.wire}, ${time ?? '-'}${note != null ? ', "$note"' : ''})';
}

enum ScheduleType { regular, shuttle, friday }

extension ScheduleTypeX on ScheduleType {
  String get wire => switch (this) {
        ScheduleType.regular => 'regular',
        ScheduleType.shuttle => 'shuttle',
        ScheduleType.friday => 'friday',
      };
  String get label => switch (this) {
        ScheduleType.regular => 'Regular Routes',
        ScheduleType.shuttle => 'Shuttle Service',
        ScheduleType.friday => 'Friday Schedule',
      };
  static ScheduleType fromWire(String? s) => switch (s) {
        'shuttle' => ScheduleType.shuttle,
        'friday' => ScheduleType.friday,
        _ => ScheduleType.regular,
      };
}

/// One parsed route block. `route_no` is only unique within
/// (semester, scheduleType) — the natural key.
class TransportRoute {
  final String semester;
  final ScheduleType scheduleType;
  final String routeNo;      // "R1", "R11", "F1"
  final String routeName;    // "Dhanmondi <> DSC"
  final List<String> stops;  // ordered, canonicalized (ends at kCanonicalDestination)
  final List<Trip> toDscTrips;
  final List<Trip> fromDscTrips;

  const TransportRoute({
    required this.semester,
    required this.scheduleType,
    required this.routeNo,
    required this.routeName,
    required this.stops,
    required this.toDscTrips,
    required this.fromDscTrips,
  });

  String get destination => kCanonicalDestination;

  Map<String, dynamic> toRouteRow() => {
        'semester': semester,
        'schedule_type': scheduleType.wire,
        'route_number': routeNo,
        'route_name': routeName,
        'route_details': stops.join(' > '),
        'stops': stops.map((s) => {'name': s}).toList(),
        'to_dsc_trips': toDscTrips.map((t) => t.toJson()).toList(),
        'from_dsc_trips': fromDscTrips.map((t) => t.toJson()).toList(),
        'is_active': true,
      };
}

/// Result of parsing a whole file: the routes plus the header metadata.
class ParsedTransportSchedule {
  final String semester;
  final String? campus;
  final List<TransportRoute> routes;
  const ParsedTransportSchedule({required this.semester, this.campus, required this.routes});
}
