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

    return offering['id'] as String;
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
        .select('*, profiles!student_id(id, full_name, avatar_url, batch, section, '
            'university_id, email, department, role, is_verified), '
            'course_offerings!inner(id, section, department, batch, courses(code, title))')
        .order('created_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Both outcomes notify the student via `trg_notify_enrollment_reviewed`,
  /// which fires on the status transition itself — so it covers this RPC and
  /// the plain UPDATE below identically, and cannot be bypassed by an admin
  /// acting through some other path.
  Future<void> approveJoin(String enrollmentId) =>
      _client.rpc('approve_course_join', params: {'p_enrollment_id': enrollmentId});

  Future<void> rejectJoin(String enrollmentId) =>
      _client.from('enrollments').update({'status': 'rejected'}).eq('id', enrollmentId);

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
