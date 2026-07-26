import '../../../../config/supabase_config.dart';

/// Display label for a lab group: batch + section + subgroup.
///
/// Batch 63, section M gives the two lab groups `63M1` and `63M2`. Derived
/// rather than stored, because batch and section already live on the offering
/// and a stored copy would drift the moment either is corrected.
String labGroupLabel(String? batch, String? section, int? subgroup) {
  final base = '${batch ?? ''}${section ?? ''}';
  return subgroup == null ? base : '$base$subgroup';
}

/// One of the four states a student can be in for a session. Kept as plain
/// strings to match the DB CHECK rather than an enum that would need mapping
/// at every boundary.
const kAttendanceStatuses = ['present', 'absent', 'late', 'excused'];

class AttendanceRepository {
  final _client = SupabaseConfig.client;

  // ------------------------------------------------------------- offerings

  /// The teacher's own approved, non-archived offerings.
  ///
  /// Filtered on `teacher_id`, deliberately — the routine's scraped
  /// `teacher_initial` is not an identity and listed other people's classes
  /// (see GradesRepository.getMyTaughtSections for the full story).
  Future<List<Map<String, dynamic>>> fetchMyOfferings() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return [];
    final res = await _client
        .from('course_offerings')
        .select('id, section, batch, department, semester, '
            'courses(code, title, course_type)')
        .eq('teacher_id', uid)
        .eq('status', 'approved')
        .eq('is_archived', false)
        .order('created_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// True when the offering's course is a lab, which is what decides whether
  /// attendance is taken for the whole section or one group at a time.
  static bool isLab(Map<String, dynamic> offering) =>
      (offering['courses'] as Map<String, dynamic>?)?['course_type'] == 'lab';

  // ---------------------------------------------------------------- roster

  /// Approved students on an offering, with their lab group.
  ///
  /// [labSubgroup] narrows to one lab half. Students not yet assigned to a
  /// group are deliberately still returned when filtering, so they are visible
  /// and fixable rather than silently missing from every lab register.
  Future<List<Map<String, dynamic>>> fetchRoster(
    String offeringId, {
    int? labSubgroup,
  }) async {
    final res = await _client
        .from('enrollments')
        .select('id, student_id, lab_subgroup, '
            'profiles!student_id(id, full_name, avatar_url, university_id)')
        .eq('offering_id', offeringId)
        .eq('status', 'approved') as List;

    final rows = res.cast<Map<String, dynamic>>().where((r) {
      if (labSubgroup == null) return true;
      final g = r['lab_subgroup'] as int?;
      return g == null || g == labSubgroup;
    }).toList();

    rows.sort((a, b) {
      final an = ((a['profiles'] as Map?)?['full_name'] as String? ?? '').toLowerCase();
      final bn = ((b['profiles'] as Map?)?['full_name'] as String? ?? '').toLowerCase();
      return an.compareTo(bn);
    });
    return rows;
  }

  /// Splits the offering's unassigned approved enrolments into groups 1 and 2.
  /// Returns how many students were newly assigned.
  Future<int> assignLabGroups(String offeringId) async {
    final res = await _client
        .rpc('assign_lab_groups', params: {'p_offering_id': offeringId});
    return (res as num?)?.toInt() ?? 0;
  }

  /// Manual override for a single student, for the cases the even split gets
  /// wrong (timetable clashes, a student who must sit with a specific half).
  Future<void> setLabSubgroup(String enrollmentId, int? subgroup) =>
      _client.from('enrollments')
          .update({'lab_subgroup': subgroup}).eq('id', enrollmentId);

  // -------------------------------------------------------------- sessions

  Future<List<Map<String, dynamic>>> fetchSessions(String offeringId) async {
    final res = await _client
        .from('attendance_sessions')
        .select('id, session_date, lab_subgroup, topic, created_at, updated_at')
        .eq('offering_id', offeringId)
        .order('session_date', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Creates a session and seeds a record per student, all marked present.
  ///
  /// Present-by-default because in a 50-student section the teacher marks the
  /// handful who are missing, not the 45 who turned up — starting from blank
  /// would mean 45 taps to record a normal day. The seeding is a single bulk
  /// insert so a large section is one round trip.
  ///
  /// The DB's unique index on (offering_id, session_date, lab_subgroup) is
  /// what actually prevents a duplicate register for the same day; this
  /// surfaces it as a readable message instead of a raw 23505.
  Future<String> createSession({
    required String offeringId,
    required DateTime date,
    int? labSubgroup,
    String? topic,
    required List<String> studentIds,
  }) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) throw StateError('Not signed in');

    final String sessionId;
    try {
      final session = await _client.from('attendance_sessions').insert({
        'offering_id': offeringId,
        'session_date': dateOnly(date),
        if (labSubgroup != null) 'lab_subgroup': labSubgroup,
        if (topic != null && topic.trim().isNotEmpty) 'topic': topic.trim(),
        'taken_by': uid,
      }).select('id').single();
      sessionId = session['id'] as String;
    } catch (e) {
      if (e.toString().contains('attendance_sessions_unique_slot')) {
        throw StateError(
            'Attendance for this class has already been taken on that date.');
      }
      rethrow;
    }

    if (studentIds.isNotEmpty) {
      await _client.from('attendance_records').insert([
        for (final sid in studentIds)
          {'session_id': sessionId, 'student_id': sid, 'marked_by': uid},
      ]);
    }
    return sessionId;
  }

  Future<void> deleteSession(String sessionId) =>
      _client.from('attendance_sessions').delete().eq('id', sessionId);

  // --------------------------------------------------------------- records

  Future<List<Map<String, dynamic>>> fetchRecords(String sessionId) async {
    final res = await _client
        .from('attendance_records')
        .select('id, student_id, status, bonus, note, updated_at')
        .eq('session_id', sessionId) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Editable after the fact by design — a teacher marking the wrong row is
  /// the normal case, not an exception. `updated_at` is maintained by a
  /// trigger so a correction is always distinguishable from the original.
  Future<void> updateRecord(
    String recordId, {
    String? status,
    double? bonus,
    String? note,
  }) =>
      _client.from('attendance_records').update({
        if (status != null) 'status': status,
        if (bonus != null) 'bonus': bonus,
        if (note != null) 'note': note.trim(),
        'marked_by': SupabaseConfig.uid,
      }).eq('id', recordId);

  /// Bulk status set for the whole register, for "mark everyone absent" before
  /// picking out the few who came.
  Future<void> setAllStatuses(String sessionId, String status) =>
      _client.from('attendance_records').update({
        'status': status,
        'marked_by': SupabaseConfig.uid,
      }).eq('session_id', sessionId);

  /// `sessionId -> {attended, total}` for a list of sessions, so the session
  /// list can show "42/48" without opening each register. Late counts as
  /// attended; excused is excluded from the total, matching [fetchSummary].
  Future<Map<String, Map<String, int>>> fetchSessionCounts(
      List<String> sessionIds) async {
    if (sessionIds.isEmpty) return {};
    final res = await _client
        .from('attendance_records')
        .select('session_id, status')
        .inFilter('session_id', sessionIds) as List;

    final out = <String, Map<String, int>>{};
    for (final row in res.cast<Map<String, dynamic>>()) {
      final sid = row['session_id'] as String?;
      if (sid == null) continue;
      final tally = out.putIfAbsent(sid, () => {'attended': 0, 'total': 0});
      final status = row['status'] as String? ?? 'present';
      if (status == 'excused') continue;
      tally['total'] = tally['total']! + 1;
      if (status == 'present' || status == 'late') {
        tally['attended'] = tally['attended']! + 1;
      }
    }
    return out;
  }

  // --------------------------------------------------------------- summary

  /// Per-student attendance across every session of an offering.
  ///
  /// Computed here rather than in SQL because the roster is one section (~50)
  /// over one term (~30 sessions) — a couple of thousand rows at the very
  /// most, well inside a single round trip, and keeping it in Dart avoids
  /// another SECURITY DEFINER function to audit.
  ///
  /// Returns `studentId -> {present, late, excused, absent, sessions, bonus,
  /// percent}`. Late counts toward attendance; excused is removed from the
  /// denominator rather than counted as attended.
  Future<Map<String, Map<String, num>>> fetchSummary(String offeringId) async {
    final sessions = await fetchSessions(offeringId);
    if (sessions.isEmpty) return {};
    final ids = sessions.map((s) => s['id'] as String).toList();

    final res = await _client
        .from('attendance_records')
        .select('student_id, status, bonus')
        .inFilter('session_id', ids) as List;

    final out = <String, Map<String, num>>{};
    for (final row in res.cast<Map<String, dynamic>>()) {
      final sid = row['student_id'] as String?;
      if (sid == null) continue;
      final tally = out.putIfAbsent(
          sid,
          () => {
                'present': 0, 'late': 0, 'excused': 0, 'absent': 0,
                'sessions': 0, 'bonus': 0, 'percent': 0,
              });
      final status = row['status'] as String? ?? 'present';
      tally[status] = (tally[status] ?? 0) + 1;
      tally['sessions'] = (tally['sessions'] ?? 0) + 1;
      tally['bonus'] = (tally['bonus'] ?? 0) + ((row['bonus'] as num?) ?? 0);
    }

    for (final tally in out.values) {
      final counted = (tally['sessions'] ?? 0) - (tally['excused'] ?? 0);
      final attended = (tally['present'] ?? 0) + (tally['late'] ?? 0);
      tally['percent'] = counted <= 0 ? 0 : (attended / counted) * 100;
    }
    return out;
  }

  /// `YYYY-MM-DD` in LOCAL time. Deliberately not `toIso8601String()`, which
  /// would render a late-evening class in UTC and file the register under the
  /// following day.
  static String dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
