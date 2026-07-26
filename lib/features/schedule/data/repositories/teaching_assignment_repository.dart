import '../../../../config/supabase_config.dart';
import '../../../notifications/data/repositories/notification_service.dart';

/// Module leaders and the teaching loads they allocate.
///
/// The allocation is what authorises a teacher to open a course offering for a
/// given course/batch/section. Before this existed a teacher typed all three
/// from memory, so two teachers could each believe they owned the same class
/// and a typo produced a section nobody belonged to.
class TeachingAssignmentRepository {
  final _client = SupabaseConfig.client;

  // -------------------------------------------------------- module leaders

  /// Departments the signed-in user is a module leader for. Empty for almost
  /// everyone — the whole module-leader UI keys off this being non-empty.
  Future<List<String>> fetchMyLedDepartments() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return [];
    final res = await _client
        .from('module_leaders')
        .select('department')
        .eq('teacher_id', uid) as List;
    return [for (final r in res) r['department'] as String];
  }

  /// The signed-in user's own department. Read from `profiles` rather than
  /// RoleSession, which caches the role and verification flags but not this.
  Future<String?> fetchMyDepartment() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return null;
    final row = await _client
        .from('profiles')
        .select('department')
        .eq('id', uid)
        .maybeSingle();
    return row?['department'] as String?;
  }

  /// Every appointment, for the admin screen that grants them.
  Future<List<Map<String, dynamic>>> fetchAllLeaders() async {
    final res = await _client
        .from('module_leaders')
        .select('id, department, appointed_at, profiles!teacher_id(id, full_name, teacher_initial, email)')
        .order('department') as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<void> appointLeader({
    required String department,
    required String teacherId,
  }) =>
      _client.from('module_leaders').insert({
        'department': department,
        'teacher_id': teacherId,
        'appointed_by': SupabaseConfig.uid,
      });

  Future<void> revokeLeader(String id) =>
      _client.from('module_leaders').delete().eq('id', id);

  /// Teachers in a department, to allocate to. Uses `profiles` directly rather
  /// than a roster RPC because the module leader needs colleagues, not students.
  Future<List<Map<String, dynamic>>> fetchDepartmentTeachers(String department) async {
    final res = await _client
        .from('profiles')
        .select('id, full_name, teacher_initial, email')
        .eq('role', 'teacher')
        .eq('department', department)
        .order('full_name') as List;
    return res.cast<Map<String, dynamic>>();
  }

  // ---------------------------------------------------- teaching assignments

  /// Everything allocated in a department, newest first. RLS restricts this to
  /// module leaders of that department and to admins.
  Future<List<Map<String, dynamic>>> fetchDepartmentAssignments(String department) async {
    final res = await _client
        .from('teaching_assignment_overview')
        .select()
        .eq('department', department)
        .order('assigned_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// What the signed-in teacher has been allocated.
  ///
  /// [unclaimedOnly] filters to rows not yet turned into an offering — that is
  /// the teacher's actual to-do list, and what the New Course Offering form
  /// starts from.
  Future<List<Map<String, dynamic>>> fetchMyAssignments({bool unclaimedOnly = false}) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return [];
    var q = _client
        .from('teaching_assignments')
        .select()
        .eq('teacher_id', uid);
    if (unclaimedOnly) q = q.isFilter('offering_id', null);
    final res = await q.order('assigned_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<void> assign({
    required String department,
    required String teacherId,
    required String courseCode,
    required String courseTitle,
    required String courseType,
    required String batch,
    required String section,
    required int semester,
    String note = '',
  }) async {
    // The teacher's in-app row is written by trg_notify_teaching_assigned, in
    // the same transaction as the insert, so it cannot be lost.
    await _client.from('teaching_assignments').insert({
      'department': department,
      'teacher_id': teacherId,
      'course_code': courseCode.trim().toUpperCase(),
      'course_title': courseTitle.trim(),
      'course_type': courseType,
      'batch': batch.trim(),
      'section': section.trim().toUpperCase(),
      'semester': semester,
      'note': note.trim(),
      'assigned_by': SupabaseConfig.uid,
    });

    // ...but a trigger cannot reach OneSignal, so the banner is sent from here,
    // push-only. Without it the teacher gets a silent list entry and nothing on
    // their phone. Best-effort: the allocation has already committed.
    try {
      await NotificationService.pushToUsers(
        userIds: [teacherId],
        title: 'New teaching assignment',
        message: '${courseCode.trim().toUpperCase()} — Batch ${batch.trim()}, '
            'Section ${section.trim().toUpperCase()}. Review it in Teaching Load.',
        deepLink: '/schedule/teaching-load',
        category: 'course_offering',
      );
    } catch (_) {}
  }

  Future<void> unassign(String id) =>
      _client.from('teaching_assignments').delete().eq('id', id);

  /// Links an allocation to the offering the teacher created from it, so the
  /// module leader can see what has actually been acted on.
  ///
  /// Best-effort by design: the offering already exists and is the thing that
  /// matters, so a failure to stamp the allocation must not surface as a
  /// failed submission.
  Future<void> markClaimed({required String assignmentId, required String offeringId}) async {
    try {
      await _client
          .from('teaching_assignments')
          .update({'offering_id': offeringId}).eq('id', assignmentId);
    } catch (_) {}
  }
}
