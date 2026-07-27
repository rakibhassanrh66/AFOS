import '../../../../config/supabase_config.dart';
import '../../../../core/utils/offline_cache.dart';
import '../../../../core/utils/postgrest_filters.dart';
import '../../../notifications/data/repositories/notification_service.dart';

/// One scheduled meeting of an offering: a course that meets twice a week is
/// two of these, and a lab split into J1/J2 halves is one per subgroup.
///
/// This exists because a `course_offerings` row used to carry a single
/// (day, start, end, room) tuple inline, which could not express a course
/// meeting more than once a week, a 3-hour lab (stored as two consecutive
/// slots), or a subgroup split — see the 20260725140000 migration.
class OfferingMeeting {
  final String? id;
  final int dayOfWeek; // Sat=0 .. Fri=6 (DIU convention, matches schedule_slots)
  final String startTime; // 'HH:mm'
  final String endTime;
  final String roomNumber;
  final String building;
  final String classType; // 'theory' | 'lab'
  final int labSubgroup; // 0 = not a subgroup, 1/2 = J1/J2

  const OfferingMeeting({
    this.id,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.roomNumber = '',
    this.building = '',
    this.classType = 'theory',
    this.labSubgroup = 0,
  });

  Map<String, dynamic> toInsert(String offeringId) => {
        'offering_id': offeringId,
        'day_of_week': dayOfWeek,
        'start_time': startTime,
        'end_time': endTime,
        'room_number': roomNumber.trim().isEmpty ? null : roomNumber.trim(),
        'building': building.trim().isEmpty ? null : building.trim(),
        'class_type': classType,
        'lab_subgroup': labSubgroup,
      };

  factory OfferingMeeting.fromJson(Map<String, dynamic> j) => OfferingMeeting(
        id: j['id'] as String?,
        dayOfWeek: (j['day_of_week'] as num?)?.toInt() ?? 0,
        startTime: (j['start_time'] as String? ?? '00:00').substring(0, 5),
        endTime: (j['end_time'] as String? ?? '00:00').substring(0, 5),
        roomNumber: j['room_number'] as String? ?? '',
        building: j['building'] as String? ?? '',
        classType: j['class_type'] as String? ?? 'theory',
        labSubgroup: (j['lab_subgroup'] as num?)?.toInt() ?? 0,
      );

  OfferingMeeting copyWith({
    int? dayOfWeek, String? startTime, String? endTime,
    String? roomNumber, String? building, String? classType, int? labSubgroup,
  }) =>
      OfferingMeeting(
        id: id,
        dayOfWeek: dayOfWeek ?? this.dayOfWeek,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        roomNumber: roomNumber ?? this.roomNumber,
        building: building ?? this.building,
        classType: classType ?? this.classType,
        labSubgroup: labSubgroup ?? this.labSubgroup,
      );

  /// Two meetings clash if they share a day and their time ranges overlap.
  bool overlaps(OfferingMeeting other) =>
      dayOfWeek == other.dayOfWeek &&
      startTime.compareTo(other.endTime) < 0 &&
      other.startTime.compareTo(endTime) < 0;
}

/// Teacher self-service course offerings (admin-approved) + student join
/// requests (teacher-approved).
///
/// An approved offering is published into `schedule_slots` -- the table every
/// schedule screen already reads -- one row per meeting, by the
/// `approve_course_offering` RPC. An approved join pins every one of those
/// slots into `user_pinned_slots` via `approve_course_join`. Both are
/// SECURITY DEFINER because they write rows the caller has no RLS path to
/// (a generated routine row; a slot owned by another user), and because a
/// half-applied approval would leave an offering students can join but that
/// never shows on a routine.
class CourseOfferingRepository {
  final _client = SupabaseConfig.client;

  static const _offeringSelect =
      '*, courses(code, title, credit_hours, course_type), '
      'course_offering_meetings(*)';

  // ---------------------------------------------------------------- courses

  Future<List<Map<String, dynamic>>> searchCourses(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    // orIlike, not interpolation: `q` is raw keystrokes from the course-code
    // field, and PostgREST parses `or=(...)` as an expression -- a typed comma
    // errors out (PGRST100) while a typed parenthesis silently returns the
    // wrong rows. See postgrest_filters.dart for the live-verified detail.
    final res = await _client.from('courses').select()
        .or(orIlike(const ['code', 'title'], q)).order('code').limit(8) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Looks up a course by its unique code, creating it on the fly if this is
  /// the first offering ever declared for it -- there's no pre-seeded course
  /// catalog (the `courses` table starts empty), so it builds up organically
  /// the same way `schedule_slots.subject_code` always has.
  ///
  /// Resolves `department_id` when the department code is known; it was
  /// previously always left NULL, which made the registry unusable for any
  /// per-department view.
  Future<String> resolveOrCreateCourse({
    required String code,
    required String title,
    required int creditHours,
    required String courseType,
    String? departmentCode,
  }) async {
    final normalized = code.trim().toUpperCase();
    final existing = await _client.from('courses').select('id').eq('code', normalized).maybeSingle();
    if (existing != null) return existing['id'] as String;

    String? departmentId;
    if (departmentCode != null && departmentCode.trim().isNotEmpty) {
      final dept = await _client.from('departments')
          .select('id').eq('code', departmentCode.trim()).maybeSingle();
      departmentId = dept?['id'] as String?;
    }

    final inserted = await _client.from('courses').insert({
      'code': normalized, 'title': title.trim(), 'credit_hours': creditHours,
      'course_type': courseType, if (departmentId != null) 'department_id': departmentId,
    }).select('id').single();
    return inserted['id'] as String;
  }

  // ------------------------------------------------------------------ terms

  /// The single active academic term. `semester_id` is defaulted server-side
  /// by a trigger, so this is only needed for display.
  ///
  /// `maybeSingle`, not `single`: this is fetched alongside the offering list,
  /// and `single()` throws when the match count is not exactly one. With no
  /// active semester — or two, if an admin activates the next term before
  /// closing the current one — that throw took down the whole My Course
  /// Offerings load, so a teacher would see no courses at all because of a
  /// missing header label. A null term just hides the label.
  /// Both callers already treat null as "no term to show", so the empty map
  /// cachedMapFetch needs for its non-nullable contract is folded back to null
  /// here rather than leaking a `{}` they would have to special-case.
  Future<Map<String, dynamic>?> fetchActiveTerm() async {
    final term = await cachedMapFetch(
      cacheKey: 'active_term',
      liveFetch: () async =>
          await _client.from('semesters')
              .select('id, name, code, start_date, end_date')
              .eq('is_active', true).limit(1).maybeSingle() ??
          const <String, dynamic>{},
    );
    return (term == null || term.isEmpty) ? null : term;
  }

  // -------------------------------------------------------------- offerings

  /// Creates a pending offering.
  ///
  /// Teachers no longer declare meeting times: the class itself is the
  /// meeting, so there is nothing separate to schedule and no
  /// `course_offering_meetings` rows are written. The table and its RPCs are
  /// left in place for the existing rows rather than dropped.
  ///
  /// Does NOT notify the reviewing admins from here, deliberately: the
  /// `trg_notify_offering_submitted` trigger does it in the same transaction
  /// as the insert. A client-side call would be a second, independent request
  /// that is silently lost if the app is backgrounded or the network drops
  /// between the two — which is how an offering once sat ~6h with no admin
  /// aware of it. Do not add one back.
  Future<String> createOffering({
    required String courseId,
    required String section,
    required String department,
    required String batch,
    required int semester,
    String outlineText = '',
    int? maxStudents,
  }) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) throw StateError('Not signed in');

    final offering = await _client.from('course_offerings').insert({
      'teacher_id': uid, 'course_id': courseId, 'section': section.trim(),
      'department': department.trim(), 'batch': batch.trim(), 'semester': semester,
      'status': 'pending',
      if (outlineText.trim().isNotEmpty) 'outline_text': outlineText.trim(),
      if (maxStudents != null) 'max_students': maxStudents,
    }).select('id').single();

    final offeringId = offering['id'] as String;

    // trg_notify_offering_submitted writes the admins' in-app rows; this adds
    // the banner it cannot send. Without it an offering could sit in the review
    // queue with nothing on any reviewer's phone — which is how one previously
    // sat ~6h unnoticed.
    await _pushReviewers(
      offeringId: offeringId,
      includeExamController: false,
      title: 'Course offering awaiting review',
      message: 'A teacher submitted a course for Section '
          '${section.trim()}, Batch ${batch.trim()}.',
      deepLink: '/admin/course-offerings',
      category: 'course_offering',
    );
    return offeringId;
  }

  Future<List<Map<String, dynamic>>> fetchMyOfferings() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return [];
    return cachedListFetch(
      cacheKey: 'my_offerings_$uid',
      liveFetch: () async {
        final res = await _client.from('course_offerings').select(_offeringSelect)
            .eq('teacher_id', uid).eq('is_archived', false)
            .order('created_at', ascending: false) as List;
        return res.cast<Map<String, dynamic>>();
      },
    );
  }

  /// Brings an ended offering back into every list that filters
  /// `is_archived = false` — which is nearly all of them.
  ///
  /// Archiving used to be one-way: no restore existed anywhere, so a single tap
  /// on "End course" removed a course from the teacher's Results, Attendance
  /// and Assignments lists, from student browsing and from the dashboard, with
  /// no trace and no undo.
  Future<void> restoreOffering(String offeringId) =>
      _client.rpc('restore_course_offering', params: {'p_offering_id': offeringId});

  Future<List<Map<String, dynamic>>> fetchMyArchivedOfferings() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return [];
    final res = await _client.from('course_offerings').select(_offeringSelect)
        .eq('teacher_id', uid).eq('is_archived', true)
        .order('archived_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Only succeeds while still pending (RLS-enforced) -- once an admin has
  /// reviewed it, withdrawing would orphan the schedule_slots rows the
  /// approval generated. Use [archiveOffering] for an approved course.
  Future<void> withdrawOffering(String offeringId) async {
    await _client.from('course_offerings').delete().eq('id', offeringId);
  }

  Future<List<Map<String, dynamic>>> fetchPendingOfferings() => cachedListFetch(
        cacheKey: 'pending_offerings',
        liveFetch: () async {
          final res = await _client.from('course_offerings')
              .select('$_offeringSelect, profiles!teacher_id(full_name, avatar_url, teacher_initial)')
              .eq('status', 'pending').eq('is_archived', false)
              .order('created_at', ascending: true) as List;
          return res.cast<Map<String, dynamic>>();
        },
      );

  /// Offerings that have already been decided, newest decision first — the
  /// "who did what" record behind the admin screen's Reviewed tab.
  ///
  /// Approving used to just drop the card out of the pending queue behind a
  /// snackbar, so an admin had no way to see what they or anyone else had
  /// decided, or to catch a mistaken approval. `reviewed_by`/`reviewed_at`
  /// were already being written; nothing ever read them back.
  ///
  /// The teacher embed stays unaliased because OfferingCard reads
  /// `offering['profiles']`; only the reviewer is aliased. Both resolve
  /// through `course_offerings_teacher_id_profiles_fkey` and
  /// `course_offerings_reviewed_by_fkey` respectively.
  Future<List<Map<String, dynamic>>> fetchReviewedOfferings({int limit = 50}) async {
    final res = await _client.from('course_offerings')
        .select('$_offeringSelect, '
            'profiles!teacher_id(full_name, avatar_url, teacher_initial), '
            'reviewer:profiles!reviewed_by(full_name, avatar_url)')
        .inFilter('status', ['approved', 'rejected'])
        .order('reviewed_at', ascending: false)
        .limit(limit) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Approves via RPC so the status flip and every generated schedule_slots
  /// row land together, then notifies the teacher and the batch+section the
  /// course is actually for.
  Future<int> approveOffering(Map<String, dynamic> offering) async {
    final offeringId = offering['id'] as String;
    final teacherId = offering['teacher_id'] as String?;
    final course = offering['courses'] as Map<String, dynamic>?;
    final label = '${course?['code'] ?? 'Your course'} (Section ${offering['section']})';

    final created = await _client.rpc('approve_course_offering',
        params: {'p_offering_id': offeringId}) as int? ?? 0;

    if (teacherId != null) {
      await NotificationService.sendToUsers(
        userIds: [teacherId],
        title: 'Course offering approved',
        message: '$label is now live on the schedule',
        deepLink: '/schedule/my-offerings',
        category: 'course_offering',
      );
    }
    // The class's in-app row is written by trg_notify_offering_approved, in the
    // same transaction as the status flip, so it cannot be lost. What that
    // trigger CANNOT do is send the OneSignal banner -- pg_net is not installed
    // and the OneSignal key lives in the edge function's environment, not in
    // the database. So the banner is sent from here, push-only.
    //
    // Do not switch this to sendToUsers: that would insert a second in-app row
    // and show every student the same notification twice. Do not drop it
    // either -- without it students get a silent list entry and no banner,
    // which reads as "no notification at all".
    await _pushOfferingAudience(
      offeringId: offeringId,
      title: 'New course available',
      message: '$label is open to join for Batch ${offering['batch']}.',
      deepLink: '/schedule/browse-courses',
    );
    return created;
  }

  /// Sends the push banner to the offering's batch+section.
  ///
  /// Best-effort: the approval and its in-app notifications have already
  /// committed, so a failed banner must never surface as a failed approval.
  Future<void> _pushOfferingAudience({
    required String offeringId,
    required String title,
    required String message,
    String? deepLink,
  }) async {
    try {
      final rows = await _client.rpc('list_offering_audience',
          params: {'p_offering_id': offeringId}) as List;
      final ids = rows
          .map((r) => (r as Map<String, dynamic>)['profile_id'] as String?)
          .whereType<String>()
          .toList();
      await NotificationService.pushToUsers(
        userIds: ids,
        title: title, message: message,
        deepLink: deepLink, category: 'course_offering',
      );
    } catch (_) {
      // Intentionally swallowed -- see doc comment.
    }
  }

  Future<void> rejectOffering({
    required String offeringId,
    required String teacherId,
    required String courseLabel,
    String reason = '',
  }) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    await _client.from('course_offerings').update({
      'status': 'rejected', 'reviewed_by': uid,
      'reviewed_at': DateTime.now().toIso8601String(), 'rejection_reason': reason,
    }).eq('id', offeringId);
    await NotificationService.sendToUsers(
      userIds: [teacherId],
      title: 'Course offering declined',
      message: reason.isNotEmpty ? '$courseLabel was declined: $reason' : '$courseLabel was declined',
      deepLink: '/schedule/my-offerings',
      category: 'course_offering',
    );
  }

  /// Semester rollover: drops the generated routine rows (cascading every
  /// enrolled student's pins) while keeping the offering and its enrollments
  /// as the record of who took the course.
  Future<void> archiveOffering(String offeringId) =>
      _client.rpc('archive_course_offering', params: {'p_offering_id': offeringId});

  /// Un-approves an offering an admin should not have approved.
  ///
  /// Approving is loud — it publishes schedule_slots and notifies a whole
  /// batch+section — and until now it was also final: the Reviewed tab was
  /// read-only, so a wrong call could only be undone by asking the teacher to
  /// archive their own course, which is a different thing and reads to them as
  /// their fault. The RPC drops the generated routine rows, returns the
  /// offering to `rejected` with a reason, and tells both the teacher and
  /// everyone already enrolled. Returns how many routine rows it removed.
  Future<int> revokeOffering({required String offeringId, String reason = ''}) async =>
      await _client.rpc('revoke_course_offering',
          params: {'p_offering_id': offeringId, 'p_reason': reason}) as int? ?? 0;

  /// Puts a declined offering back in the review queue.
  ///
  /// A plain UPDATE rather than an RPC because there is nothing to keep
  /// consistent: a rejected offering never generated any schedule_slots, so
  /// returning it to `pending` touches one row. It has to go through `pending`
  /// at all because `approve_course_offering` refuses anything else — which is
  /// correct, since approving is what generates the routine and it must run
  /// exactly once. RLS (`admin_manage_offerings`) is what restricts this to
  /// admins; there is no client-side check standing in for that.
  ///
  /// The previous decision is cleared, not kept: leaving `rejection_reason` on
  /// a row that is once again awaiting review would show the next reviewer a
  /// verdict that no longer applies.
  Future<void> reopenOffering(String offeringId) =>
      _client.from('course_offerings').update({
        'status': 'pending',
        'rejection_reason': null,
        'reviewed_by': null,
        'reviewed_at': null,
      }).eq('id', offeringId);

  // ------------------------------------------------------- student-facing

  /// Courses for THIS student: active term, approved, and matching their own
  /// department + batch + section.
  ///
  /// Previously filtered on department alone, which showed a first-year CSE
  /// student every CSE course in the university. Set [allDepartmentCourses]
  /// to widen back to the whole department -- that is the path a retake or
  /// irregular student uses to find another section.
  Future<List<Map<String, dynamic>>> fetchJoinableOfferings({
    required String department,
    String? batch,
    String? section,
    bool allDepartmentCourses = false,
  }) async {
    final scoped = !allDepartmentCourses && batch != null && section != null
        && batch.isNotEmpty && section.isNotEmpty;
    return cachedListFetch(
      cacheKey: 'joinable_${department}_${scoped ? '${batch}_$section' : 'all'}',
      liveFetch: () async {
        var q = _client.from('course_offerings')
            .select('$_offeringSelect, profiles!teacher_id(full_name, avatar_url, teacher_initial)')
            .eq('status', 'approved').eq('is_archived', false).eq('department', department);
        if (scoped) q = q.eq('batch', batch).eq('section', section);
        final res = await q.order('created_at', ascending: false) as List;
        return res.cast<Map<String, dynamic>>();
      },
    );
  }

  Future<List<Map<String, dynamic>>> fetchMyEnrollments() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return [];
    final res = await _client.from('enrollments')
        .select('*, course_offerings(*, courses(code, title), course_offering_meetings(*))')
        .eq('student_id', uid).order('created_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// The offering's teacher is notified by `trg_notify_enrollment_requested`,
  /// not from here — see [createOffering] for why this is a trigger. Before
  /// that trigger existed nothing told the teacher a request had arrived, so
  /// requests sat at REQUEST PENDING forever and the student never reached
  /// the course group. The group's RLS was never the problem.
  Future<void> requestJoin(String offeringId) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    await _client.from('enrollments').insert({
      'student_id': uid, 'offering_id': offeringId, 'status': 'pending',
    });

    // The trigger writes the teacher's in-app row; it cannot reach OneSignal.
    // Without this the teacher gets NO banner when someone applies, so the
    // request only surfaces if they happen to open the screen — which is
    // exactly how requests end up sitting undecided.
    try {
      final off = await _client
          .from('course_offerings')
          .select('teacher_id, courses(code)')
          .eq('id', offeringId)
          .maybeSingle();
      final teacherId = off?['teacher_id'] as String?;
      if (teacherId == null) return;
      await NotificationService.pushToUsers(
        userIds: [teacherId],
        title: 'New join request',
        message: '${(off?['courses'] as Map?)?['code'] ?? 'A course'} — '
            'a student is waiting for your decision.',
        deepLink: '/schedule/join-requests',
        category: 'course_offering',
      );
    } catch (_) {
      // Best-effort: the request itself is committed and the in-app row exists.
    }
  }

  /// Push-only banner to the people who review a queue.
  ///
  /// Resolves recipients through offering_reviewer_audience() — the SAME
  /// function the trigger uses to write the in-app rows — so the two channels
  /// cannot describe different audiences. They already had: this previously
  /// called list_role_holders() and pushed to every dept_admin in the
  /// university, while the trigger scoped them to the offering's own
  /// department. Nothing surfaced it because the project has no dept_admin
  /// yet, so a recipient count matched while the rule did not.
  ///
  /// Never sendToUsers: the in-app rows are already written by the trigger.
  Future<void> _pushReviewers({
    required String offeringId,
    required bool includeExamController,
    required String title,
    required String message,
    required String deepLink,
    required String category,
  }) async {
    try {
      final rows = await _client.rpc('offering_reviewer_audience', params: {
        'p_offering_id': offeringId,
        'p_include_exam_controller': includeExamController,
      }) as List;
      await NotificationService.pushToUsers(
        userIds: rows
            .map((r) => (r as Map<String, dynamic>)['profile_id'] as String?)
            .whereType<String>()
            .toList(),
        title: title, message: message, deepLink: deepLink, category: category,
      );
    } catch (_) {}
  }

  // ------------------------------------------------------- teacher-facing

  /// Every join request across every offering this teacher owns -- RLS
  /// (teacher_read_offering_enrollments) already scopes this to their own
  /// offerings, so no explicit teacher_id filter is needed client-side.
  Future<List<Map<String, dynamic>>> fetchOfferingJoinRequests() async {
    final res = await _client.from('enrollments')
        // university_id / is_verified / role / department are here so the
        // teacher can actually identify who is asking to join — a name and a
        // batch string alone were not enough to tell whether the requester
        // really belongs to that batch.
        // `is_archived` is here because approving a request that points at an
        // ended course is refused by trg_no_approval_into_archived, and a
        // request CAN outlive the archiving of its course. Without this column
        // the teacher taps Accept on a normal-looking card and gets a raw
        // database error; with it the card can say so up front.
        .select('*, profiles!student_id(id, full_name, avatar_url, batch, section, '
            'semester, university_id, email, department, role, is_verified), '
            'course_offerings!inner(id, section, department, batch, is_archived, '
            'courses(code, title))')
        .order('created_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Takes an already-admitted student back out of the course.
  ///
  /// Goes through the RPC because approving PINNED every one of the offering's
  /// schedule_slots into that student's routine, and deleting the enrolment row
  /// alone would leave those pins behind for the rest of the term. There was no
  /// path for this at all before: `enrollments` carries a DELETE policy for the
  /// student withdrawing a pending request and one for admins, and none for the
  /// teacher who owns the course — so admitting the wrong person was permanent.
  Future<void> removeEnrollment(String enrollmentId, {String reason = ''}) =>
      _client.rpc('remove_course_enrollment',
          params: {'p_enrollment_id': enrollmentId, 'p_reason': reason});

  /// Puts a declined request back in the queue.
  ///
  /// Deliberately returns it to `pending` rather than approving it outright:
  /// `approve_course_join` only accepts a pending row, and reversing a decline
  /// is a decision to look again, not a decision to admit. The student is told
  /// by `trg_notify_enrollment_reviewed` on the transition, same as any other.
  Future<void> reopenJoinRequest(String enrollmentId) =>
      _client.from('enrollments').update({'status': 'pending'}).eq('id', enrollmentId);

  /// Both outcomes notify the student via `trg_notify_enrollment_reviewed`,
  /// which fires on the status transition itself — so it covers this RPC and
  /// the plain UPDATE below identically, and cannot be bypassed by an admin
  /// acting through some other path.
  /// Takes back a join request the student sent but the teacher has not yet
  /// decided on.
  ///
  /// Deletes rather than marking withdrawn: a request nobody ruled on is not a
  /// decision worth keeping, and a new status would have to be filtered out of
  /// every teacher-facing query afterwards.
  ///
  /// The `status = 'pending'` filter mirrors the RLS policy exactly, so this
  /// never silently no-ops against a row the database would refuse anyway — an
  /// approved enrolment is a drop, not a cancel, and stays with the teacher.
  Future<void> withdrawJoinRequest(String enrollmentId) =>
      _client.from('enrollments')
          .delete()
          .eq('id', enrollmentId)
          .eq('student_id', SupabaseConfig.uid ?? '')
          .eq('status', 'pending');

  /// [studentId] is optional and only used for the push banner. The trigger
  /// writes the in-app row transactionally; a trigger cannot reach OneSignal,
  /// so without this the student is admitted with nothing on their phone —
  /// the same gap that made offering approvals look silent.
  Future<void> approveJoin(String enrollmentId, {String? studentId, String? courseCode}) async {
    await _client.rpc('approve_course_join', params: {'p_enrollment_id': enrollmentId});
    if (studentId == null) return;
    try {
      await NotificationService.pushToUsers(
        userIds: [studentId],
        title: 'Course join approved',
        message: '${courseCode ?? 'Your course'} — you are enrolled.',
        deepLink: '/schedule/my-courses',
        category: 'course_offering',
      );
    } catch (_) {}
  }

  Future<void> rejectJoin(String enrollmentId, {String? studentId, String? courseCode}) async {
    await _client.from('enrollments').update({'status': 'rejected'}).eq('id', enrollmentId);
    if (studentId == null) return;
    try {
      await NotificationService.pushToUsers(
        userIds: [studentId],
        title: 'Course join declined',
        message: '${courseCode ?? 'Your course'} — your request was not accepted.',
        deepLink: '/schedule/browse-courses',
        category: 'course_offering',
      );
    } catch (_) {}
  }

  /// The section CR for an offering, so a teacher can reach them directly.
  /// Reuses the existing find_section_cr RPC rather than adding a lookup.
  Future<Map<String, dynamic>?> findOfferingCr(Map<String, dynamic> offering) async {
    try {
      final res = await _client.rpc('find_section_cr', params: {
        'p_department_code': offering['department'],
        'p_batch': offering['batch'],
        'p_section': offering['section'],
      }) as List;
      return res.firstOrNull as Map<String, dynamic>?;
    } catch (_) {
      return null;
    }
  }

  // --------------------------------------------------------- course groups

  /// Offerings whose group chat the current user can open: their own
  /// offerings if a teacher, or ones they're approved into if a student.
  /// Mirrors the `can_access_course_group` predicate the RLS policies use.
  Future<List<Map<String, dynamic>>> fetchMyCourseGroups() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return [];
    final mine = await _client.from('course_offerings')
        .select('id, section, batch, department, is_archived, courses(code, title)')
        .eq('teacher_id', uid).eq('is_archived', false) as List;
    final joined = await _client.from('enrollments')
        .select('course_offerings!inner(id, section, batch, department, is_archived, courses(code, title))')
        .eq('student_id', uid).eq('status', 'approved') as List;

    final out = <String, Map<String, dynamic>>{};
    for (final o in mine.cast<Map<String, dynamic>>()) {
      out[o['id'] as String] = o;
    }
    for (final e in joined.cast<Map<String, dynamic>>()) {
      final o = e['course_offerings'] as Map<String, dynamic>?;
      if (o != null && o['is_archived'] != true) out[o['id'] as String] = o;
    }
    return out.values.toList();
  }

  /// Most recent first from the server, then reversed for display -- the same
  /// shape dept/club chat use, so the 60-row window is the newest 60.
  Future<List<Map<String, dynamic>>> fetchCourseMessages(String offeringId) async {
    final res = await _client.from('course_messages')
        .select('*, profiles!sender_id(full_name, avatar_url, role)')
        .eq('offering_id', offeringId)
        .order('created_at', ascending: false).limit(60) as List;
    return res.cast<Map<String, dynamic>>().reversed.toList();
  }

  Future<void> sendCourseMessage(String offeringId, String content) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    await _client.from('course_messages').insert({
      'offering_id': offeringId, 'sender_id': uid, 'content': content.trim(),
    });
  }

  Future<void> deleteCourseMessage(String messageId) =>
      _client.from('course_messages').delete().eq('id', messageId);
}
