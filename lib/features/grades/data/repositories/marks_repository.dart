import '../../../../config/supabase_config.dart';
import '../../../notifications/data/repositories/notification_service.dart';

/// Marks, results and CGPA.
///
/// Totals, letter grades and grade points are NEVER computed here — they come
/// from the `enrollment_results` view, which derives them from the components
/// and `grading_scale`. Recomputing them client-side would be a second,
/// silently-diverging implementation of the university's grading policy.
class MarksRepository {
  final _client = SupabaseConfig.client;

  // ------------------------------------------------------------ components

  /// The mark distribution for a course type — 6 components for theory,
  /// 4 for lab, guaranteed by the DB to total exactly 100.
  Future<List<Map<String, dynamic>>> fetchComponents(String courseType) async {
    final res = await _client
        .from('mark_components')
        .select('id, code, label, max_marks, sort_order, is_auto')
        .eq('course_type', courseType)
        .order('sort_order') as List;
    return res.cast<Map<String, dynamic>>();
  }

  // ----------------------------------------------------------------- marks

  /// Every approved student on an offering with their per-component marks.
  ///
  /// Returned as `enrollmentId -> {componentId -> marks}` alongside the roster
  /// so the grid can be built without an N+1 per student.
  Future<({
    List<Map<String, dynamic>> roster,
    Map<String, Map<String, double>> marks,
  })> fetchOfferingMarks(String offeringId) async {
    final enrolments = await _client
        .from('enrollments')
        .select('id, student_id, profiles!student_id(full_name, university_id, avatar_url)')
        .eq('offering_id', offeringId)
        .eq('status', 'approved') as List;

    final roster = enrolments.cast<Map<String, dynamic>>().toList()
      ..sort((a, b) {
        final an = ((a['profiles'] as Map?)?['full_name'] as String? ?? '').toLowerCase();
        final bn = ((b['profiles'] as Map?)?['full_name'] as String? ?? '').toLowerCase();
        return an.compareTo(bn);
      });

    if (roster.isEmpty) return (roster: roster, marks: <String, Map<String, double>>{});

    final res = await _client
        .from('student_marks')
        .select('enrollment_id, component_id, marks')
        .inFilter('enrollment_id', [for (final r in roster) r['id'] as String]) as List;

    final marks = <String, Map<String, double>>{};
    for (final row in res.cast<Map<String, dynamic>>()) {
      final eid = row['enrollment_id'] as String;
      marks.putIfAbsent(eid, () => {})[row['component_id'] as String] =
          ((row['marks'] as num?) ?? 0).toDouble();
    }
    return (roster: roster, marks: marks);
  }

  /// Totals for an offering, straight from the view.
  /// `enrollmentId -> {total, letter, gradePoint}`.
  Future<Map<String, Map<String, dynamic>>> fetchTotals(String offeringId) async {
    final res = await _client
        .from('enrollment_results')
        .select('enrollment_id, total_marks, letter_grade, grade_point')
        .eq('offering_id', offeringId) as List;
    return {
      for (final r in res.cast<Map<String, dynamic>>())
        r['enrollment_id'] as String: {
          'total': ((r['total_marks'] as num?) ?? 0).toDouble(),
          'letter': r['letter_grade'] as String?,
          'gradePoint': (r['grade_point'] as num?)?.toDouble(),
        },
    };
  }

  /// The DB trigger rejects a mark above the component's max, or a component
  /// belonging to the other course type, so an out-of-range value surfaces as
  /// a thrown error rather than being silently clamped.
  Future<void> upsertMark({
    required String enrollmentId,
    required String componentId,
    required double marks,
  }) =>
      _client.from('student_marks').upsert({
        'enrollment_id': enrollmentId,
        'component_id': componentId,
        'marks': marks,
        'updated_by': SupabaseConfig.uid,
      }, onConflict: 'enrollment_id,component_id');

  /// Fills the attendance component from the registers. Returns how many
  /// students were written.
  Future<int> syncAttendanceMarks(String offeringId) async {
    final res = await _client
        .rpc('sync_attendance_marks', params: {'p_offering_id': offeringId});
    return (res as num?)?.toInt() ?? 0;
  }

  // ----------------------------------------------------------- submissions

  Future<Map<String, dynamic>?> fetchSubmission(String offeringId) async =>
      await _client
          .from('offering_result_submissions')
          .select('id, status, submitted_at, reviewed_at, rejection_reason')
          .eq('offering_id', offeringId)
          .maybeSingle();

  /// The teacher's one-click "send it all in". Re-submitting after a rejection
  /// resets the row to pending rather than creating a second one — the table
  /// is unique per offering.
  Future<void> submitResults(String offeringId) async {
    await _client.from('offering_result_submissions').upsert({
      'offering_id': offeringId,
      'status': 'pending',
      'submitted_by': SupabaseConfig.uid,
      'submitted_at': DateTime.now().toIso8601String(),
      'reviewed_by': null,
      'reviewed_at': null,
      'rejection_reason': null,
    }, onConflict: 'offering_id');

    // trg_notify_results_submitted writes the reviewers' in-app rows — before
    // it existed this step told nobody at all, so a class's marks waited on an
    // admin happening to open the screen. This adds the banner a trigger
    // cannot send. pushToUsers, not sendToUsers: the rows are already written.
    try {
      final rows = await _client.rpc('list_role_holders', params: {
        'p_roles': ['super_admin', 'admin', 'exam_controller'],
      }) as List;
      final course = await _client
          .from('course_offerings')
          .select('section, batch, courses(code)')
          .eq('id', offeringId)
          .maybeSingle();
      await NotificationService.pushToUsers(
        userIds: rows
            .map((r) => (r as Map<String, dynamic>)['profile_id'] as String?)
            .whereType<String>()
            .toList(),
        title: 'Results awaiting publication',
        message: '${(course?['courses'] as Map?)?['code'] ?? 'A course'} '
            '(Section ${course?['section'] ?? '?'}) has marks ready to review.',
        deepLink: '/grades',
        category: 'result',
      );
    } catch (_) {
      // Best-effort: the submission is committed and the in-app rows exist.
    }
  }

  // ----------------------------------------------------------------- admin

  Future<List<Map<String, dynamic>>> fetchPendingSubmissions() async {
    final res = await _client
        .from('offering_result_submissions')
        .select('id, offering_id, status, submitted_at, '
            'course_offerings(section, batch, department, '
            'courses(code, title, course_type), profiles!teacher_id(full_name))')
        .eq('status', 'pending')
        .order('submitted_at') as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Approving fires `trg_on_results_approved`, which writes the whole class's
  /// in-app notification in the same transaction — deliberately server-side, so
  /// a backgrounded app cannot lose the announcement.
  ///
  /// The banner is a separate, push-only send: a trigger cannot reach OneSignal
  /// (no pg_net, and the key lives in the edge function's environment), so
  /// without this students would get a silent list entry and no notification on
  /// their phone. `pushToUsers`, not `sendToUsers` — the latter would insert a
  /// second in-app row on top of the trigger's.
  Future<void> reviewSubmission({
    required String submissionId,
    required bool approve,
    String? reason,
  }) async {
    final row = await _client
        .from('offering_result_submissions')
        .update({
          'status': approve ? 'approved' : 'rejected',
          'reviewed_by': SupabaseConfig.uid,
          'reviewed_at': DateTime.now().toIso8601String(),
          if (!approve) 'rejection_reason': reason,
        })
        .eq('id', submissionId)
        .select('offering_id, course_offerings(courses(code))')
        .maybeSingle();

    if (!approve || row == null) return;
    try {
      // list_offering_ENROLLED, not list_offering_audience. The latter is the
      // whole batch+section roster — right for "a new course is open to join",
      // badly wrong here: it would banner every student in the batch that their
      // result was ready, including people who never took the course, while the
      // in-app row from trg_on_results_approved went only to those who did.
      final ids = await _client.rpc('list_offering_enrolled',
          params: {'p_offering_id': row['offering_id']}) as List;
      final code = ((row['course_offerings'] as Map?)?['courses'] as Map?)?['code'] as String?;
      await NotificationService.pushToUsers(
        userIds: ids
            .map((r) => (r as Map<String, dynamic>)['profile_id'] as String?)
            .whereType<String>()
            .toList(),
        title: 'Results published',
        message: '${code ?? 'Your course'} results are now available.',
        deepLink: '/grades',
        category: 'exam',
      );
    } catch (_) {
      // Best-effort: the publication already committed and the in-app rows are
      // written, so a failed banner must not surface as a failed approval.
    }
  }

  // --------------------------------------------------------------- student

  /// Published results for the signed-in student. RLS keeps unpublished
  /// offerings out; the extra status filter is belt-and-braces so a policy
  /// change can't quietly start leaking work-in-progress marks.
  Future<List<Map<String, dynamic>>> fetchMyResults() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return [];
    final res = await _client
        .from('enrollment_results')
        .select('enrollment_id, offering_id, total_marks, letter_grade, '
            'grade_point, credit_hours, course_type, publication_status')
        .eq('student_id', uid)
        .eq('publication_status', 'approved') as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Per-component breakdown for one of the student's published results.
  Future<List<Map<String, dynamic>>> fetchMyBreakdown(String enrollmentId) async {
    final res = await _client
        .from('student_marks')
        .select('marks, mark_components(code, label, max_marks, sort_order)')
        .eq('enrollment_id', enrollmentId) as List;
    final rows = res.cast<Map<String, dynamic>>().toList()
      ..sort((a, b) {
        final ao = ((a['mark_components'] as Map?)?['sort_order'] as int?) ?? 0;
        final bo = ((b['mark_components'] as Map?)?['sort_order'] as int?) ?? 0;
        return ao.compareTo(bo);
      });
    return rows;
  }

  /// Credit-weighted CGPA plus standing and honours, computed server-side from
  /// the counting attempt of each course (a retake supersedes the earlier one).
  Future<Map<String, dynamic>?> fetchMyCgpa() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return null;
    final res = await _client.rpc('student_cgpa', params: {'p_student_id': uid}) as List;
    return res.isEmpty ? null : res.first as Map<String, dynamic>;
  }

  /// Per-semester GPA, one entry per semester the student has results in.
  ///
  /// One RPC per semester rather than a single client-side calculation: the
  /// credit weighting and the retake rule live in `student_sgpa()`, and a
  /// second implementation here would be free to drift from it. A student has
  /// at most twelve semesters and usually far fewer, so the calls are issued
  /// together and the cost is one round-trip's latency.
  Future<Map<int, double>> fetchMySemesterGpas(List<int> semesters) async {
    final uid = SupabaseConfig.uid;
    if (uid == null || semesters.isEmpty) return {};
    final distinct = semesters.toSet().toList();
    final values = await Future.wait([
      for (final s in distinct)
        _client.rpc('student_sgpa', params: {'p_student_id': uid, 'p_semester': s}),
    ]);
    final out = <int, double>{};
    for (var i = 0; i < distinct.length; i++) {
      final v = (values[i] as num?)?.toDouble();
      if (v != null) out[distinct[i]] = v;
    }
    return out;
  }

  /// Course code/title for a set of offerings, for labelling a result list.
  Future<Map<String, Map<String, dynamic>>> fetchOfferingLabels(
      List<String> offeringIds) async {
    if (offeringIds.isEmpty) return {};
    final res = await _client
        .from('course_offerings')
        .select('id, section, batch, semester, courses(code, title)')
        .inFilter('id', offeringIds) as List;
    return {
      for (final r in res.cast<Map<String, dynamic>>()) r['id'] as String: r,
    };
  }
}
