import 'models/transport_schedule.dart';

/// Turns route-level trip times into **per-stop** times, using the minute
/// offsets an admin recorded in `transport_stop_offsets`.
///
/// The whole point of this file is honesty about what the source data does and
/// does not say. The DIU sheet gives two time columns per route and neither is
/// a per-stop time:
///
///  * `to_dsc_trips` is the **"Start Time"** — when the bus leaves the route's
///    FIRST stop, heading to campus.
///  * `from_dsc_trips` is when the bus leaves **campus**, heading out.
///
/// So for a mid-route stop like "Mirpur 10" on R4, the sheet's 7:00 AM is when
/// the bus left *ECB Chattor*, not when it reaches Mirpur 10. Without a
/// recorded offset there is genuinely no way to compute the latter, and this
/// class will return null rather than guess — the UI then falls back to a
/// sentence that states only what is actually known.
///
/// Everything here is pure + static so it can be unit-tested directly.
class StopTimeCalculator {
  StopTimeCalculator._();

  /// Minutes past midnight for a canonical "7:00 AM" / "1:30 PM" display time,
  /// or null if it isn't one (e.g. a coming-soon trip with no time).
  static int? parseDisplayTime(String? display) {
    if (display == null) return null;
    final m = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*([AaPp])\.?[Mm]\.?\s*$').firstMatch(display);
    if (m == null) return null;
    var hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2)!);
    if (hour < 1 || hour > 12 || minute > 59) return null;
    final isPm = m.group(3)!.toLowerCase() == 'p';
    if (hour == 12) hour = 0;
    return (hour + (isPm ? 12 : 0)) * 60 + minute;
  }

  /// Formats minutes-past-midnight back into the app's canonical display form.
  /// Wraps at 24h so a late-evening trip plus a long offset can't produce
  /// "25:10 PM".
  static String formatMinutes(int minutesPastMidnight) {
    final total = minutesPastMidnight % (24 * 60);
    final h24 = total ~/ 60;
    final minute = total % 60;
    final period = h24 >= 12 ? 'PM' : 'AM';
    var h12 = h24 % 12;
    if (h12 == 0) h12 = 12;
    return '$h12:${minute.toString().padLeft(2, '0')} $period';
  }

  /// Shifts a trip's time by [offsetMinutes], preserving its note and status.
  ///
  /// Returns null when the shift can't be made truthfully — no offset recorded,
  /// or the trip carries no parseable time (a "coming soon" slot). Callers must
  /// treat null as "we don't know", never as zero.
  static Trip? shift(Trip trip, int? offsetMinutes) {
    if (offsetMinutes == null) return null;
    final base = parseDisplayTime(trip.time);
    if (base == null) return null;
    return Trip(
      time: formatMinutes(base + offsetMinutes),
      note: trip.note,
      status: trip.status,
    );
  }

  /// Shifts a whole direction's trips. Returns null if ANY of them can't be
  /// shifted, so the UI never shows a half-real list where some chips are true
  /// per-stop times and others are silently still route-level ones.
  static List<Trip>? shiftAll(List<Trip> trips, int? offsetMinutes) {
    if (offsetMinutes == null || trips.isEmpty) return null;
    final out = <Trip>[];
    for (final t in trips) {
      // Coming-soon slots legitimately carry no time; keep them as-is rather
      // than discarding the whole direction over them.
      if (t.isComingSoon) {
        out.add(t);
        continue;
      }
      final shifted = shift(t, offsetMinutes);
      if (shifted == null) return null;
      out.add(shifted);
    }
    return out;
  }
}

/// The admin-recorded timings for one stop on one route.
class StopOffset {
  final String routeNumber;
  final String scheduleType;
  final String stopName;

  /// Minutes after the route's start time that the bus reaches this stop,
  /// inbound. Null = not recorded yet.
  final int? minutesFromOrigin;

  /// Minutes after leaving campus that the bus reaches this stop, outbound.
  /// Null = not recorded yet.
  final int? minutesFromDsc;

  const StopOffset({
    required this.routeNumber,
    required this.scheduleType,
    required this.stopName,
    this.minutesFromOrigin,
    this.minutesFromDsc,
  });

  bool get isEmpty => minutesFromOrigin == null && minutesFromDsc == null;

  factory StopOffset.fromRow(Map<String, dynamic> r) => StopOffset(
        routeNumber: r['route_number'] as String? ?? '',
        scheduleType: r['schedule_type'] as String? ?? 'regular',
        stopName: r['stop_name'] as String? ?? '',
        minutesFromOrigin: (r['minutes_from_origin'] as num?)?.toInt(),
        minutesFromDsc: (r['minutes_from_dsc'] as num?)?.toInt(),
      );

  Map<String, dynamic> toRow() => {
        'route_number': routeNumber,
        'schedule_type': scheduleType,
        'stop_name': stopName,
        'minutes_from_origin': minutesFromOrigin,
        'minutes_from_dsc': minutesFromDsc,
      };

  /// Key used to look an offset up: route + schedule type + stop name.
  static String keyFor(String routeNumber, String scheduleType, String stopName) =>
      '$routeNumber|$scheduleType|${stopName.toLowerCase()}';

  String get key => keyFor(routeNumber, scheduleType, stopName);
}
