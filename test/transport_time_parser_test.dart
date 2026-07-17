import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/features/transport/data/transport_time_parser.dart';
import 'package:afos_v7/features/transport/data/models/transport_schedule.dart';

void main() {
  group('TransportTimeParser.parseTrip', () {
    test('plain 12h with AM/PM', () {
      expect(TransportTimeParser.parseTrip('7:00 AM').time, '7:00 AM');
      expect(TransportTimeParser.parseTrip('1:30 PM').time, '1:30 PM');
    });

    test('hh:mm:ss AM/PM drops the seconds', () {
      final t = TransportTimeParser.parseTrip('11:15:00 AM');
      expect(t.time, '11:15 AM');
      expect(t.status, TripStatus.scheduled);
    });

    test('dot form with redundant seconds "4.20.00 PM" == 4:20 PM', () {
      expect(TransportTimeParser.parseTrip('4.20.00 PM').time, '4:20 PM');
    });

    test('dot form "10.50 AM" == 10:50 AM', () {
      expect(TransportTimeParser.parseTrip('10.50 AM').time, '10:50 AM');
    });

    test('trailing parenthetical note on same line (irregular spacing)', () {
      final t = TransportTimeParser.parseTrip('1:30 PM                    ( Students bus)');
      expect(t.time, '1:30 PM');
      expect(t.note, 'Students bus');
    });

    test('note on a start time, with the real "Strat" typo, kept verbatim', () {
      final t = TransportTimeParser.parseTrip('10:00 AM ( Strat from Polashbari U Turn )');
      expect(t.time, '10:00 AM');
      expect(t.note, 'Strat from Polashbari U Turn');
    });

    test('note after a newline with irregular spacing', () {
      final t = TransportTimeParser.parseTrip('1:30 PM\n   ( Students bus)');
      expect(t.time, '1:30 PM');
      expect(t.note, 'Students bus');
    });

    test('long shortened-route note', () {
      final t = TransportTimeParser.parseTrip(
          '9:40 AM (will go upto Bangladesh medical U Turn Azampur only)');
      expect(t.time, '9:40 AM');
      expect(t.note, 'will go upto Bangladesh medical U Turn Azampur only');
    });

    test('capacity note', () {
      final t = TransportTimeParser.parseTrip('8:00 AM (Only 1 Bus Assigned For ECB)');
      expect(t.time, '8:00 AM');
      expect(t.note, 'Only 1 Bus Assigned For ECB');
    });

    test('"Coming Soon" -> comingSoon, null time (any spacing/case)', () {
      final t = TransportTimeParser.parseTrip('  coming   soon ');
      expect(t.status, TripStatus.comingSoon);
      expect(t.time, isNull);
    });

    test('stray whitespace / non-breaking space is tolerated', () {
      final t = TransportTimeParser.parseTrip('  7:00 AM \t');
      expect(t.time, '7:00 AM');
    });

    test('blank cell -> empty trip', () {
      expect(TransportTimeParser.parseTrip('').isEmpty, isTrue);
      expect(TransportTimeParser.parseTrip(null).isEmpty, isTrue);
      expect(TransportTimeParser.parseTrip('   ').isEmpty, isTrue);
    });

    test('24h value with no meridiem derives PM', () {
      expect(TransportTimeParser.parseTrip('16:20').time, '4:20 PM');
      expect(TransportTimeParser.parseTrip('13:00').time, '1:00 PM');
    });

    test('typed hour/minute cell', () {
      expect(TransportTimeParser.fromHourMinute(7, 0).time, '7:00 AM');
      expect(TransportTimeParser.fromHourMinute(13, 30).time, '1:30 PM');
      expect(TransportTimeParser.fromHourMinute(12, 0).time, '12:00 PM');
      expect(TransportTimeParser.fromHourMinute(0, 15).time, '12:15 AM');
    });

    test('excel day-fraction serial time', () {
      // 0.5 == noon, 0.29166.. == 7:00 AM
      expect(TransportTimeParser.fromDayFraction(0.5).time, '12:00 PM');
      expect(TransportTimeParser.fromDayFraction(7 / 24).time, '7:00 AM');
    });
  });

  group('TransportTimeParser.parseTripColumn', () {
    test('stacked sub-rows -> multiple trips', () {
      final trips = TransportTimeParser.parseTripColumn('7:00 AM\n1:30 PM ( Students bus)');
      expect(trips.length, 2);
      expect(trips[0].time, '7:00 AM');
      expect(trips[1].time, '1:30 PM');
      expect(trips[1].note, 'Students bus');
    });

    test('single line with several times falls back to token scan', () {
      final trips = TransportTimeParser.parseTripColumn('7:00 AM   9:40 AM   1:30 PM');
      expect(trips.map((t) => t.time), ['7:00 AM', '9:40 AM', '1:30 PM']);
    });

    test('coming-soon column', () {
      final trips = TransportTimeParser.parseTripColumn('Coming Soon');
      expect(trips.length, 1);
      expect(trips.first.status, TripStatus.comingSoon);
    });
  });
}
