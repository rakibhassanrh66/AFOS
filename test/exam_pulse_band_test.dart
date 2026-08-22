import 'package:afos_v7/features/dashboard/presentation/widgets/exam_pulse_band.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The examination band that sits between the dashboard's search field and its
/// module tiles.
///
/// The rules worth pinning are the ones about when it must NOT appear. A band
/// that keeps announcing an exam period which finished last week is worse than
/// no band, and it is the kind of thing nobody notices until a student turns up
/// to an empty hall.
void main() {
  String iso(DateTime d) => d.toIso8601String().split('T').first;

  ExamPulseData build({
    required DateTime start,
    required DateTime end,
    List<Map<String, dynamic>> exams = const [],
    List<Map<String, dynamic>> duties = const [],
    String role = 'student',
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return ExamPulseData(
      role: role,
      term: {
        'id': 'a-term',
        'type': 'final',
        'season': 'summer',
        'year': 2026,
        'startsOn': iso(start),
        'endsOn': iso(end),
        'isOver': end.isBefore(today),
        'isLive': !start.isAfter(today) && !end.isBefore(today),
      },
      exams: exams,
      duties: duties,
    );
  }

  Map<String, dynamic> exam(DateTime d,
          {String code = 'CSE326',
          String slot = 'A',
          List<String> rooms = const []}) =>
      {
        'date': iso(d),
        'slot': slot,
        'start': '09:00:00',
        'end': '11:00:00',
        'code': code,
        'title': 'Social and Professional Issues in Computing',
        'batch': '65',
        'rooms': rooms,
      };

  Future<void> pump(WidgetTester t, ExamPulseData? data,
      {bool reduceMotion = false}) async {
    t.view.physicalSize = const Size(900, 1400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: ExamPulseBand(data: data),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 400));
  }

  group('when the band must stay silent', () {
    testWidgets('no data at all', (t) async {
      await pump(t, null);
      expect(find.byType(ExamPulseBand), findsOneWidget);
      expect(find.textContaining('Exam'), findsNothing);
    });

    testWidgets('no published term', (t) async {
      await pump(t, const ExamPulseData());
      expect(find.textContaining('exam'), findsNothing);
    });

    testWidgets('THE TERM HAS FINISHED — nothing is shown at all', (t) async {
      // The rule that matters most. A finished exam period must vanish rather
      // than advertise a date that has already passed.
      final now = DateTime.now();
      await pump(
        t,
        build(
          start: now.subtract(const Duration(days: 20)),
          end: now.subtract(const Duration(days: 3)),
          exams: [exam(now.subtract(const Duration(days: 5)))],
        ),
      );
      expect(find.textContaining('Final'), findsNothing);
      expect(find.text('Exam today'), findsNothing);
      expect(find.text('Next exam'), findsNothing);
    });

    testWidgets('a live term with nothing left to sit shows nothing', (t) async {
      final now = DateTime.now();
      await pump(
        t,
        build(
          start: now.subtract(const Duration(days: 4)),
          end: now.add(const Duration(days: 4)),
          exams: [exam(now.subtract(const Duration(days: 2)))],
        ),
      );
      expect(find.text('Exam today'), findsNothing);
      expect(find.text('Next exam'), findsNothing);
    });
  });

  group('when there is something to say', () {
    testWidgets('an exam today reads "Exam today" and names the room',
        (t) async {
      final now = DateTime.now();
      await pump(
        t,
        build(
          start: now.subtract(const Duration(days: 2)),
          end: now.add(const Duration(days: 5)),
          exams: [exam(now, rooms: ['G1-001', 'G1-002'])],
        ),
      );
      expect(find.text('Exam today'), findsOneWidget);
      expect(find.text('CSE326'), findsOneWidget);
      // The room is the entire reason the routine and the seat plan were
      // joined; without it the card is just a date the student already knew.
      expect(find.textContaining('G1-001'), findsOneWidget);
    });

    testWidgets('a future exam reads "Next exam", not "today"', (t) async {
      final now = DateTime.now();
      await pump(
        t,
        build(
          start: now.subtract(const Duration(days: 1)),
          end: now.add(const Duration(days: 9)),
          exams: [exam(now.add(const Duration(days: 3)))],
        ),
      );
      expect(find.text('Next exam'), findsOneWidget);
      expect(find.text('Exam today'), findsNothing);
    });

    testWidgets('an unpublished seat plan is stated, not left blank',
        (t) async {
      final now = DateTime.now();
      await pump(
        t,
        build(
          start: now.subtract(const Duration(days: 1)),
          end: now.add(const Duration(days: 5)),
          exams: [exam(now, rooms: const [])],
        ),
      );
      expect(find.text('Seat plan not published yet'), findsOneWidget);
    });

    testWidgets('a teacher sees their own duty count and rooms', (t) async {
      final now = DateTime.now();
      await pump(
        t,
        build(
          role: 'teacher',
          start: now.subtract(const Duration(days: 1)),
          end: now.add(const Duration(days: 6)),
          exams: [exam(now.add(const Duration(days: 2)))],
          duties: [
            {'date': iso(now), 'room': 'G1-004', 'code': 'CSE121'},
            {'date': iso(now), 'room': 'G1-005', 'code': 'CSE121'},
          ],
        ),
      );
      expect(find.text('Your invigilation'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.textContaining('G1-004'), findsOneWidget);
    });
  });

  group('the term name', () {
    test('reads back as the routine header states it', () {
      final now = DateTime.now();
      final d = build(
          start: now.subtract(const Duration(days: 1)),
          end: now.add(const Duration(days: 1)));
      expect(d.termName, 'Final Summer 2026');
    });
  });

  group('derived values', () {
    test('perDay fills the gaps so the line reads as a timeline', () {
      final base = DateTime(2026, 8, 19);
      final d = build(
        start: base,
        end: DateTime(2026, 8, 23),
        exams: [
          exam(base),
          exam(base),
          exam(base.add(const Duration(days: 4))),
        ],
      );
      final pts = d.perDay;
      // 19th through 23rd inclusive, with the empty days kept as zeroes.
      expect(pts.length, 5);
      expect(pts.first.count, 2);
      expect(pts[1].count, 0);
      expect(pts.last.count, 1);
    });

    test('next ignores anything today or earlier', () {
      final now = DateTime.now();
      final d = build(
        start: now.subtract(const Duration(days: 2)),
        end: now.add(const Duration(days: 5)),
        exams: [
          exam(now, code: 'TODAY'),
          exam(now.add(const Duration(days: 2)), code: 'SOON'),
          exam(now.add(const Duration(days: 4)), code: 'LATER'),
        ],
      );
      expect(d.next!['code'], 'SOON');
    });
  });
}
