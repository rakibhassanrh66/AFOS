import '../../../../config/supabase_config.dart';
import '../../../notifications/data/repositories/notification_service.dart';

/// Teacher self-service course offerings (admin-approved) + student join
/// requests (teacher-approved). An approved offering is mirrored into
/// `schedule_slots` -- the table every existing schedule screen already
/// reads from -- via [approveOffering], and an approved join is mirrored
/// into `user_pinned_slots` -- the table the existing "pin a retake"
/// feature already reads from -- via the `approve_course_join` RPC (a
/// SECURITY DEFINER function, since a teacher approving on a student's
/// behalf has no RLS path to write a row owned by that student).
class CourseOfferingRepository {
  final _client = SupabaseConfig.client;

  Future<List<Map<String, dynamic>>> searchCourses(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final res = await _client.from('courses').select()
        .or('code.ilike.%$q%,title.ilike.%$q%').order('code').limit(8) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Looks up a course by its unique code, creating it on the fly if this
  /// is the first offering ever declared for it -- there's no pre-seeded
  /// course catalog to pick from (the `courses` table starts empty), so it
  /// builds up organically the same way `schedule_slots.subject_code` has
  /// always been freely typed by whoever uploads the routine.
  Future<String> resolveOrCreateCourse({
    required String code, required String title, required int creditHours, required String courseType,
  }) async {
    final existing = await _client.from('courses').select('id').eq('code', code).maybeSingle();
    if (existing != null) return existing['id'] as String;
    final inserted = await _client.from('courses').insert({
      'code': code, 'title': title, 'credit_hours': creditHours, 'course_type': courseType,
    }).select('id').single();
    return inserted['id'] as String;
  }

  Future<void> createOffering({
    required String courseId, required String section, required String department, required String batch,
    required int semester, required int dayOfWeek, required String startTime, required String endTime,
    required String roomNumber, required String building,
  }) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    await _client.from('course_offerings').insert({
      'teacher_id': uid, 'course_id': courseId, 'section': section, 'department': department,
      'batch': batch, 'semester': semester, 'day_of_week': dayOfWeek, 'start_time': startTime,
      'end_time': endTime, 'room_number': roomNumber, 'building': building, 'status': 'pending',
    });
  }

  Future<List<Map<String, dynamic>>> fetchMyOfferings() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return [];
    final res = await _client.from('course_offerings')
        .select('*, courses(code, title, credit_hours)')
        .eq('teacher_id', uid).order('created_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Only succeeds while still pending (RLS-enforced) -- once admin has
  /// reviewed it, withdrawing would silently orphan the schedule_slots row
  /// an approval may already have generated.
  Future<void> withdrawOffering(String offeringId) async {
    await _client.from('course_offerings').delete().eq('id', offeringId);
  }

  Future<List<Map<String, dynamic>>> fetchPendingOfferings() async {
    final res = await _client.from('course_offerings')
        .select('*, courses(code, title, credit_hours), profiles!teacher_id(full_name, avatar_url, teacher_initial)')
        .eq('status', 'pending').order('created_at', ascending: true) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Approves a pending offering AND generates the matching schedule_slots
  /// row -- both plain client writes, since admin-tier already has direct
  /// RLS write access to course_offerings (admin_manage_offerings) and to
  /// schedule_slots (its own pre-existing admin_write_schedule policy) --
  /// no RPC needed here, unlike the student-join-approval flow below.
  Future<void> approveOffering(Map<String, dynamic> offering) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    final offeringId = offering['id'] as String;
    final teacherId = offering['teacher_id'] as String;
    final course = offering['courses'] as Map<String, dynamic>?;
    final teacherProfile = await _client.from('profiles')
        .select('full_name, avatar_url, teacher_initial').eq('id', teacherId).maybeSingle();

    await _client.from('course_offerings').update({
      'status': 'approved', 'reviewed_by': uid, 'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', offeringId);

    await _client.from('schedule_slots').insert({
      'subject': course?['title'] ?? 'Untitled Course',
      'subject_code': course?['code'],
      'credit_hours': course?['credit_hours'] ?? 3,
      'teacher_name': teacherProfile?['full_name'],
      'teacher_avatar': teacherProfile?['avatar_url'],
      'teacher_initial': teacherProfile?['teacher_initial'],
      'room_number': offering['room_number'],
      'building': offering['building'],
      'start_time': offering['start_time'],
      'end_time': offering['end_time'],
      'day_of_week': offering['day_of_week'],
      'department': offering['department'],
      'semester': offering['semester'],
      'batch': offering['batch'],
      'section': offering['section'],
      'course_offering_id': offeringId,
    });

    NotificationService.sendToUsers(
      userIds: [teacherId],
      title: 'Course offering approved',
      message: "${course?['code'] ?? 'Your course'} (Section ${offering['section']}) is now live on the schedule",
      deepLink: '/schedule/my-offerings',
      category: 'course_offering',
    );
  }

  Future<void> rejectOffering({
    required String offeringId, required String teacherId, required String courseLabel, String reason = '',
  }) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    await _client.from('course_offerings').update({
      'status': 'rejected', 'reviewed_by': uid, 'reviewed_at': DateTime.now().toIso8601String(),
      'rejection_reason': reason,
    }).eq('id', offeringId);
    NotificationService.sendToUsers(
      userIds: [teacherId],
      title: 'Course offering declined',
      message: reason.isNotEmpty ? '$courseLabel was declined: $reason' : '$courseLabel was declined',
      deepLink: '/schedule/my-offerings',
      category: 'course_offering',
    );
  }

  Future<List<Map<String, dynamic>>> fetchJoinableOfferings(String department) async {
    final res = await _client.from('course_offerings')
        .select('*, courses(code, title, credit_hours), profiles!teacher_id(full_name, avatar_url)')
        .eq('status', 'approved').eq('department', department)
        .order('created_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> fetchMyEnrollments() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return [];
    final res = await _client.from('enrollments')
        .select('*, course_offerings(*, courses(code, title))')
        .eq('student_id', uid).order('created_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<void> requestJoin(String offeringId) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    await _client.from('enrollments').insert({
      'student_id': uid, 'offering_id': offeringId, 'status': 'pending',
    });
  }

  /// Every join request across every offering this teacher owns -- RLS
  /// (teacher_read_offering_enrollments) already scopes this to their own
  /// offerings, so no explicit teacher_id filter is needed client-side.
  Future<List<Map<String, dynamic>>> fetchOfferingJoinRequests() async {
    final res = await _client.from('enrollments')
        .select('*, profiles!student_id(full_name, avatar_url, batch, section), '
            'course_offerings!inner(section, department, batch, courses(code, title))')
        .order('created_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<void> approveJoin(String enrollmentId) =>
      _client.rpc('approve_course_join', params: {'p_enrollment_id': enrollmentId});

  Future<void> rejectJoin(String enrollmentId) =>
      _client.from('enrollments').update({'status': 'rejected'}).eq('id', enrollmentId);
}
