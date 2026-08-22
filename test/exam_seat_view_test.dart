import 'package:afos_v7/features/exam_seat/data/exam_seat_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards for the seat-plan bug found live on 2026-08-22, mid-finals.
///
/// `exam_room_allocations` held 1632 rows, every one of them from the JUNE
/// mid-term, and the screen selected them by batch+section with no date bound
/// and no term. So a batch-67 student two days from sitting CSE313 was shown
/// three June sessions headed "3 upcoming sessions" — two of them titled only
/// "Exam", because those rows carry no course code — and nothing whatsoever
/// about the exam actually coming.
///
/// The shapes below are copied from the real `my_exam_schedule()` payload and
/// the real allocation rows, not invented.
void main() {
  String iso(DateTime d) => d.toIso8601String().split('T').first;

  final today = DateTime(2026, 8, 22);

  Map<String, dynamic> schedule({
    Map<String, dynamic>? term,
    bool noTerm = false,
    List<Map<String, dynamic>> exams = const [],
  }) =>
      {
        'role': 'student',
        'batch': '67',
        'section': 'D',
        'initial': null,
        'term': noTerm
            ? null
            : term ??
            {
              'id': 'final-term',
              'type': 'final',
              'season': 'summer',
              'year': 2026,
              'department': 'CSE',
              'startsOn': '2026-08-19',
              'endsOn': '2026-08-27',
              'isOver': false,
              'isLive': true,
            },
        'exams': exams,
        'duties': const [],
      };

  Map<String, dynamic> exam(String date, String code, String title) => {
        'date': date,
        'slot': 'B',
        'start': '12:00:00',
        'end': '14:00:00',
        'code': code,
        'title': title,
        'batch': '67',
        'rooms': const [],
      };

  /// A real June row: note course_code null on two of the three, which is why
  /// the old screen rendered cards titled only "Exam".
  Map<String, dynamic> alloc(String date, String? code, String room, int seats,
          {String? initial}) =>
      {
        'exam_date': date,
        'slot_label': 'B',
        'course_code': code,
        'course_title': code == null ? null : 'Some Course',
        'teacher_initial': initial,
        'batch': '67',
        'section': 'D',
        'room_no': room,
        'seats': seats,
      };

  final finalExams = [
    exam('2026-08-20', 'CSE226', 'Numerical Methods'),
    exam('2026-08-23', 'CSE313', 'Compiler Design'),
    exam('2026-08-25', 'CSE311', 'Database Management System'),
  ];

  group('the previous term cannot leak in', () {
    test('June allocations create no sessions of their own', () {
      // Exactly the rows that were on screen: the whole June mid-term.
      final june = [
        alloc('2026-06-28', null, 'G1-011', 8),
        alloc('2026-06-28', null, 'G1-012', 14),
        alloc('2026-06-30', null, 'G1-013', 14),
        alloc('2026-07-02', 'CSE311', 'G1-014', 14),
      ];

      final v = ExamSeatView.from(schedule(exams: finalExams), june);

      expect(v.sessions.length, 3);
      expect(v.sessions.map((s) => s.courseCode),
          ['CSE226', 'CSE313', 'CSE311']);
      // Not one June date survives.
      for (final s in v.sessions) {
        expect(s.date!.month, 8, reason: 'a July/June exam reached the screen');
      }
    });

    test('a June room is never borrowed for an August exam of the same course',
        () {
      // CSE311 sits in both terms. Matching on course code alone would hand
      // the student G1-014 for an exam whose rooms have not been published.
      final v = ExamSeatView.from(
        schedule(exams: finalExams),
        [alloc('2026-07-02', 'CSE311', 'G1-014', 14)],
      );

      final cse311 = v.sessions.firstWhere((s) => s.courseCode == 'CSE311');
      expect(cse311.hasRooms, isFalse);
      expect(cse311.rooms, isEmpty);
    });

    test('every exam still appears when no seat plan exists at all', () {
      // The state the project is actually in: routine published, seat plan
      // not imported. The student must still learn the exam exists.
      final v = ExamSeatView.from(schedule(exams: finalExams), const []);

      expect(v.sessions.length, 3);
      expect(v.sessions.every((s) => !s.hasRooms), isTrue);
    });
  });

  group('enrichment', () {
    test('matching allocations attach rooms, seats and the teacher initial',
        () {
      final v = ExamSeatView.from(schedule(exams: finalExams), [
        alloc('2026-08-23', 'CSE313', 'G1-001', 51, initial: 'SMC'),
        alloc('2026-08-23', 'CSE313', 'G1-004', 12, initial: 'SMC'),
      ]);

      final s = v.sessions.firstWhere((e) => e.courseCode == 'CSE313');
      expect(s.hasRooms, isTrue);
      expect(s.rooms.map((r) => r.room), ['G1-001', 'G1-004']);
      expect(s.rooms.map((r) => r.seats), [51, 12]);
      expect(s.teacherInitial, 'SMC');
    });

    test('an allocation matching no exam in the term is dropped, not shown',
        () {
      final v = ExamSeatView.from(
        schedule(exams: finalExams),
        [alloc('2026-08-23', 'CSE999', 'G1-009', 40)],
      );

      expect(v.sessions.length, 3);
      expect(v.sessions.every((s) => !s.hasRooms), isTrue);
    });
  });

  group('what counts as upcoming', () {
    test("an exam earlier the same day is still not past", () {
      // It starts at 09:00. At 14:00 the student may still be in the
      // building, and the card must not have quietly moved to "Completed".
      final s = ExamSessionView(date: DateTime(2026, 8, 22));
      expect(s.isPast(now: DateTime(2026, 8, 22, 14, 30)), isFalse);
    });

    test('yesterday is past', () {
      final s = ExamSessionView(date: DateTime(2026, 8, 21));
      expect(s.isPast(now: today), isTrue);
    });

    test('upcomingCount counts only what has not happened', () {
      final v = ExamSeatView.from(schedule(exams: finalExams), const []);
      // 20 Aug has gone; 23 and 25 Aug have not.
      expect(v.upcomingCount(now: today), 2);
      expect(v.sessions.length, 3, reason: 'past exams are kept, just labelled');
    });
  });

  group('term labelling', () {
    test('names the period the way the routine document does', () {
      expect(ExamSeatView.from(schedule(), const []).termLabel,
          'Final · Summer 2026');
    });

    test('no published term is distinct from a term with no exams', () {
      final none = ExamSeatView.from(schedule(noTerm: true), const []);
      expect(none.term, isNull);
      expect(none.termLabel, '');

      final empty = ExamSeatView.from(schedule(exams: const []), const []);
      expect(empty.term, isNotNull);
      expect(empty.sessions, isEmpty);
    });

    test('a finished term reports itself over', () {
      final v = ExamSeatView.from(
        schedule(term: {
          'id': 'mid-term',
          'type': 'mid',
          'season': 'summer',
          'year': 2026,
          'startsOn': '2026-06-27',
          'endsOn': iso(DateTime(2026, 7, 4)),
          'isOver': true,
          'isLive': false,
        }),
        const [],
      );
      expect(v.isOver, isTrue);
      expect(v.termLabel, 'Mid · Summer 2026');
    });
  });

  test('sessions come back in date order whatever order the RPC used', () {
    final v = ExamSeatView.from(
      schedule(exams: [finalExams[2], finalExams[0], finalExams[1]]),
      const [],
    );
    expect(v.sessions.map((s) => iso(s.date!)),
        ['2026-08-20', '2026-08-23', '2026-08-25']);
  });
}
