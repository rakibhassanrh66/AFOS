/// Turns the `my_exam_schedule()` payload plus the term's room allocations
/// into the rows the seat-plan screen draws.
///
/// This is a separate object for the same reason `ExamPulseData` is: the rule
/// worth pinning is which exams may appear, and a widget that fetches its own
/// data cannot be asked that question in a test. The bug it exists to prevent
/// was found live on 2026-08-22 — with two exam terms in the table, a screen
/// that selected allocations by batch+section alone showed the *previous*
/// period's rooms under the heading "upcoming".
library;

class ExamRoomSeats {
  final String room;
  final int seats;
  const ExamRoomSeats(this.room, this.seats);
}

class ExamSessionView {
  final DateTime? date;
  final String? slotLabel, slotStart, slotEnd, courseCode, courseTitle;
  final String? teacherInitial;
  final List<ExamRoomSeats> rooms;

  const ExamSessionView({
    this.date,
    this.slotLabel,
    this.slotStart,
    this.slotEnd,
    this.courseCode,
    this.courseTitle,
    this.teacherInitial,
    this.rooms = const [],
  });

  /// Compared date-to-date, never as an instant: an exam that started at
  /// 09:00 today is still today's exam at 14:00 and must not drop out of
  /// "upcoming" while the student is still in the building.
  bool isPast({DateTime? now}) {
    final d = date;
    if (d == null) return false;
    final n = now ?? DateTime.now();
    return DateTime(d.year, d.month, d.day)
        .isBefore(DateTime(n.year, n.month, n.day));
  }

  /// The one question this screen exists to answer. Kept explicit so the
  /// difference between "no room" and "room not yet known" is never left to
  /// an empty list rendering as blank space.
  bool get hasRooms => rooms.isNotEmpty;
}

class ExamSeatView {
  /// Null when no exam term is published at all — which is a different
  /// message from a published term that lists nothing for this batch.
  final Map<String, dynamic>? term;
  final List<ExamSessionView> sessions;

  const ExamSeatView({this.term, this.sessions = const []});

  bool get isOver => term?['isOver'] == true;

  /// "Final · Summer 2026", as the routine document names itself. The screen
  /// had no term label at all while there was only ever one term.
  String get termLabel {
    final t = term;
    if (t == null) return '';
    String cap(Object? v) {
      final s = '${v ?? ''}'.trim();
      return s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}';
    }

    // Season and year are one phrase ("Summer 2026"), so only the exam type
    // is separated off — "Final · Summer · 2026" reads as three unrelated
    // facts rather than one period's name.
    final when = [cap(t['season']), '${t['year'] ?? ''}'.trim()]
        .where((p) => p.isNotEmpty)
        .join(' ');
    return [cap(t['type']), when].where((p) => p.isNotEmpty).join(' · ');
  }

  int upcomingCount({DateTime? now}) =>
      sessions.where((s) => !s.isPast(now: now)).length;

  /// [schedule] is the raw `my_exam_schedule()` object; [allocations] are
  /// `exam_room_allocations` rows ALREADY bounded to the same term's window.
  ///
  /// The exam list comes from the schedule and never from the allocations:
  /// that is what stops a stale period's rows from inventing sessions. An
  /// allocation that matches no exam in the term is dropped rather than
  /// shown, and an exam with no allocation is kept with no rooms — the
  /// student still needs to know the exam exists.
  static ExamSeatView from(
    Map<String, dynamic> schedule,
    List<Map<String, dynamic>> allocations,
  ) {
    final term = (schedule['term'] as Map?)?.cast<String, dynamic>();
    final exams = ((schedule['exams'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

    final byExam = <String, List<Map<String, dynamic>>>{};
    for (final a in allocations) {
      (byExam['${a['exam_date']}_${a['course_code']}'] ??= []).add(a);
    }

    final sessions = <ExamSessionView>[];
    for (final e in exams) {
      final alloc = byExam['${e['date']}_${e['code']}'] ?? const [];
      sessions.add(ExamSessionView(
        date: DateTime.tryParse('${e['date']}'),
        slotLabel: e['slot'] as String?,
        slotStart: e['start'] as String?,
        slotEnd: e['end'] as String?,
        courseCode: e['code'] as String?,
        courseTitle: e['title'] as String?,
        teacherInitial:
            alloc.isEmpty ? null : alloc.first['teacher_initial'] as String?,
        rooms: [
          for (final a in alloc)
            ExamRoomSeats('${a['room_no'] ?? '-'}', a['seats'] as int? ?? 0),
        ],
      ));
    }

    sessions.sort((a, b) =>
        (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)));
    return ExamSeatView(term: term, sessions: sessions);
  }
}
