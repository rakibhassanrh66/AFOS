import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/features/transport/data/transport_excel_parser.dart';
import 'package:afos_v7/features/transport/data/transport_time_parser.dart';
import 'package:afos_v7/features/transport/data/models/transport_schedule.dart';

/// Enforcement tests for the exact, verified real-sheet routes R4 / R13 / R15
/// (from the DIU Summer-2026 transport .xlsx). These pin the parser's expected
/// output — ordered stops, both-direction trip times, and the per-trip notes
/// that used to be dropped/detached — so the parsing can never silently
/// regress. See also `transport_time_parser_test.dart` for the malformed-time
/// and note-merge unit cases.
void main() {
  late ParsedTransportSchedule parsed;

  setUpAll(() {
    final bytes = File('test/fixtures/transport_summer2026.xlsx').readAsBytesSync();
    parsed = TransportExcelParser.parse(bytes);
  });

  TransportRoute routeNo(String no) => parsed.routes.firstWhere((r) => r.routeNo == no);
  List<String?> times(List<Trip> trips) => trips.where((t) => !t.isEmpty).map((t) => t.time).toList();

  test('R4 (regular): every stop, 2 to-DSC trips, 3 from-DSC trips with the 6:10 note intact', () {
    final r4 = routeNo('R4');
    expect(r4.scheduleType, ScheduleType.regular);
    expect(r4.routeName, 'ECB Chattor <> Mirpur <> DSC');

    expect(r4.stops, [
      'ECB Chattor', 'Kalshi More', 'Mirpur 12', 'Mirpur 10', 'Mirpur 02',
      'Mirpur 01 - Sony Cinema Hall', 'Commerce College', 'Gudaraghat', 'Beribadh',
      'Estern Housing', 'Birulia', 'Akran', 'Daffodil Smart City',
    ]);

    expect(times(r4.toDscTrips), ['7:00 AM', '10:00 AM']);

    // "4.20.00 PM" parses to 4:20 PM (not garbage), and 6:10 PM keeps its full
    // note instead of splitting into an orphan time-less trip.
    final from = r4.fromDscTrips.where((t) => !t.isEmpty).toList();
    expect(from.map((t) => t.time), ['1:30 PM', '4:20 PM', '6:10 PM']);
    final t610 = from.firstWhere((t) => t.time == '6:10 PM');
    expect(t610.note, contains('Will go upto'));
    expect(t610.note, contains('Only 1 Bus Assigned For ECB'));
  });

  test('R13 (shuttle): 4 to-DSC trips, both from-DSC notes extracted', () {
    final r13 = routeNo('R13');
    expect(r13.scheduleType, ScheduleType.shuttle);
    expect(r13.routeName, 'Mirpur-1, Sony Cinema Hall <> DSC');

    expect(times(r13.toDscTrips), ['7:00 AM', '8:30 AM', '10:00 AM', '12:00 PM']);

    final from = r13.fromDscTrips.where((t) => !t.isEmpty).toList();
    expect(from.map((t) => t.time), ['11:15 AM', '4:20 PM']);
    // Notes must survive (kept verbatim — the source omits the space in
    // "Mirpur-1only"; we don't fabricate one).
    expect(from[0].note, contains('Mirpur-1'));
    expect(from[1].note, contains('Mirpur-10'));
  });

  test('R15 (shuttle): both pickup points as stops, 4 to-DSC trips, both notes', () {
    final r15 = routeNo('R15');
    expect(r15.scheduleType, ScheduleType.shuttle);
    // Both Uttara pickups are stops on the same route; DSC is the destination.
    expect(r15.stops, contains('Uttara Moylar Mor'));
    expect(r15.stops, contains('Uttara Metro rail Center'));
    expect(r15.stops.last, 'Daffodil Smart City');

    expect(times(r15.toDscTrips), ['7:00 AM', '8:30 AM', '10:00 AM', '12:00 PM']);

    final from = r15.fromDscTrips.where((t) => !t.isEmpty).toList();
    expect(from.map((t) => t.time), ['11:15 AM', '4:20 PM']);
    expect(from[0].note, contains('Uttara Moylar Mor'));
    expect(from[1].note, contains('Bangladesh medical'));
  });

  test('a stop appears exactly once — DSC is never duplicated', () {
    for (final r in parsed.routes) {
      final dsc = r.stops.where((s) => s.toLowerCase().contains('daffodil')).length;
      expect(dsc, lessThanOrEqualTo(1), reason: '${r.routeNo} has $dsc DSC stops');
    }
  });

  group('malformed / merged time+note cases (spec-enforced)', () {
    test('dot forms parse: 4.20.00 PM -> 4:20 PM, 4.20 PM -> 4:20 PM', () {
      expect(TransportTimeParser.parseTrip('4.20.00 PM').time, '4:20 PM');
      expect(TransportTimeParser.parseTrip('4.20 PM').time, '4:20 PM');
      expect(TransportTimeParser.parseTrip('11:15:00 AM').time, '11:15 AM');
    });

    test('a time and its note split across sub-rows merge into ONE trip', () {
      final trips = TransportTimeParser.parseTripColumn(
          '6:10 PM\nWill go upto Mirpur-1,10&Pallabi   (Only 1 Bus Assigned For ECB)');
      expect(trips.length, 1);
      expect(trips.first.time, '6:10 PM');
      expect(trips.first.note, contains('Will go upto'));
      expect(trips.first.note, contains('Only 1 Bus Assigned For ECB'));
    });

    test('Coming Soon -> comingSoon status, no time', () {
      final t = TransportTimeParser.parseTrip('Coming Soon');
      expect(t.status, TripStatus.comingSoon);
      expect(t.time, isNull);
    });
  });
}
