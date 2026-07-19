import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/features/transport/data/models/transport_schedule.dart';
import 'package:afos_v7/features/transport/data/stop_time_calculator.dart';

/// Locks the per-stop timing maths, and — more importantly — locks the rule
/// that the app NEVER invents a time it doesn't have.
///
/// Background: the DIU sheet gives only two numbers per route (the start time
/// at the route's first stop, and the departure time from campus). For R4 the
/// 7:00 AM / 10:00 AM figures are ECB Chattor's departures; Mirpur 10 is the
/// 4th stop. Presenting those as "Mirpur 10's times" would be wrong, so a
/// missing offset must always surface as null, never as a silent zero.
void main() {
  group('parseDisplayTime', () {
    test('parses canonical AM/PM display times', () {
      expect(StopTimeCalculator.parseDisplayTime('7:00 AM'), 7 * 60);
      expect(StopTimeCalculator.parseDisplayTime('10:00 AM'), 10 * 60);
      expect(StopTimeCalculator.parseDisplayTime('1:30 PM'), 13 * 60 + 30);
      expect(StopTimeCalculator.parseDisplayTime('6:10 PM'), 18 * 60 + 10);
    });

    test('handles the 12-hour boundaries', () {
      expect(StopTimeCalculator.parseDisplayTime('12:00 AM'), 0);
      expect(StopTimeCalculator.parseDisplayTime('12:30 AM'), 30);
      expect(StopTimeCalculator.parseDisplayTime('12:00 PM'), 12 * 60);
      expect(StopTimeCalculator.parseDisplayTime('12:45 PM'), 12 * 60 + 45);
    });

    test('rejects anything that is not a real display time', () {
      for (final bad in [null, '', 'Coming soon', '25:00 AM', '7:75 AM', '0:30 AM', '7.00 PM', 'soon']) {
        expect(StopTimeCalculator.parseDisplayTime(bad), isNull, reason: 'input: $bad');
      }
    });
  });

  group('formatMinutes', () {
    test('round-trips through the canonical format', () {
      for (final t in ['7:00 AM', '10:00 AM', '1:30 PM', '6:10 PM', '12:00 PM', '12:05 AM']) {
        final mins = StopTimeCalculator.parseDisplayTime(t)!;
        expect(StopTimeCalculator.formatMinutes(mins), t);
      }
    });

    test('wraps past midnight instead of emitting an impossible hour', () {
      // 11:50 PM + 30 min must not become "24:20 PM".
      final base = StopTimeCalculator.parseDisplayTime('11:50 PM')!;
      expect(StopTimeCalculator.formatMinutes(base + 30), '12:20 AM');
    });
  });

  group('shift — the real per-stop answer', () {
    test('R4: Mirpur 10 at +18 min turns 7:00/10:00 into 7:18/10:18', () {
      final trips = [const Trip(time: '7:00 AM'), const Trip(time: '10:00 AM')];
      final shifted = StopTimeCalculator.shiftAll(trips, 18)!;
      expect(shifted.map((t) => t.time).toList(), ['7:18 AM', '10:18 AM']);
    });

    test('outbound: campus departures shift by the from-campus offset', () {
      final trips = [
        const Trip(time: '1:30 PM'),
        const Trip(time: '4:20 PM'),
        const Trip(time: '6:10 PM', note: 'Only 1 Bus Assigned For ECB'),
      ];
      final shifted = StopTimeCalculator.shiftAll(trips, 18)!;
      expect(shifted.map((t) => t.time).toList(), ['1:48 PM', '4:38 PM', '6:28 PM']);
      // The note travels with its trip — it describes the run, not the time.
      expect(shifted.last.note, 'Only 1 Bus Assigned For ECB');
    });

    test('a zero offset (the origin stop) is a real answer, not "unknown"', () {
      final shifted = StopTimeCalculator.shiftAll([const Trip(time: '7:00 AM')], 0)!;
      expect(shifted.single.time, '7:00 AM');
    });

    test('coming-soon slots survive the shift untouched', () {
      final trips = [
        const Trip(time: '7:00 AM'),
        const Trip(status: TripStatus.comingSoon),
      ];
      final shifted = StopTimeCalculator.shiftAll(trips, 15)!;
      expect(shifted.first.time, '7:15 AM');
      expect(shifted.last.isComingSoon, isTrue);
      expect(shifted.last.time, isNull);
    });
  });

  group('never fabricates a time', () {
    test('no recorded offset yields null, NOT the unshifted route time', () {
      final trips = [const Trip(time: '7:00 AM'), const Trip(time: '10:00 AM')];
      expect(StopTimeCalculator.shiftAll(trips, null), isNull);
      expect(StopTimeCalculator.shift(trips.first, null), isNull);
    });

    test('a null offset is never treated as zero', () {
      // The bug this guards: falling back to `offset ?? 0` would relabel ECB
      // Chattor's 7:00 AM departure as Mirpur 10's, which is simply false.
      final unknown = StopTimeCalculator.shiftAll([const Trip(time: '7:00 AM')], null);
      final atOrigin = StopTimeCalculator.shiftAll([const Trip(time: '7:00 AM')], 0);
      expect(unknown, isNull);
      expect(atOrigin, isNotNull);
      expect(unknown, isNot(equals(atOrigin)));
    });

    test('an unparseable time yields null even when an offset exists', () {
      expect(StopTimeCalculator.shift(const Trip(time: 'Coming soon'), 10), isNull);
      expect(StopTimeCalculator.shift(const Trip(), 10), isNull);
    });

    test('one unshiftable trip discards the whole direction, never a half-real list', () {
      // Mixing true per-stop times with untouched route-level ones in the same
      // row would be indistinguishable to the rider — so it's all or nothing.
      final trips = [const Trip(time: '7:00 AM'), const Trip(time: 'garbage')];
      expect(StopTimeCalculator.shiftAll(trips, 12), isNull);
    });

    test('an empty direction stays empty rather than becoming a fake entry', () {
      expect(StopTimeCalculator.shiftAll(const [], 12), isNull);
    });
  });

  group('StopOffset', () {
    test('key is route + schedule type + case-insensitive stop name', () {
      expect(StopOffset.keyFor('R4', 'regular', 'Mirpur 10'),
          StopOffset.keyFor('R4', 'regular', 'mirpur 10'));
      expect(StopOffset.keyFor('R4', 'regular', 'Mirpur 10'),
          isNot(StopOffset.keyFor('R4', 'friday', 'Mirpur 10')));
      expect(StopOffset.keyFor('R4', 'regular', 'Mirpur 10'),
          isNot(StopOffset.keyFor('R13', 'regular', 'Mirpur 10')));
    });

    test('round-trips through the wire row', () {
      const o = StopOffset(
        routeNumber: 'R4',
        scheduleType: 'regular',
        stopName: 'Mirpur 10',
        minutesFromOrigin: 18,
        minutesFromDsc: 22,
      );
      final back = StopOffset.fromRow(o.toRow());
      expect(back.routeNumber, 'R4');
      expect(back.scheduleType, 'regular');
      expect(back.stopName, 'Mirpur 10');
      expect(back.minutesFromOrigin, 18);
      expect(back.minutesFromDsc, 22);
    });

    test('a row with no timings reports itself empty', () {
      const o = StopOffset(routeNumber: 'R4', scheduleType: 'regular', stopName: 'Mirpur 10');
      expect(o.isEmpty, isTrue);
      expect(
        const StopOffset(
          routeNumber: 'R4', scheduleType: 'regular', stopName: 'X', minutesFromDsc: 0,
        ).isEmpty,
        isFalse,
      );
    });
  });
}
