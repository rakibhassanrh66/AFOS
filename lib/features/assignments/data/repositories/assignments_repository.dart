import '../../../../config/supabase_config.dart';
import '../../../notifications/data/repositories/notification_service.dart';

class AssignmentsRepository {
  final _client = SupabaseConfig.client;

  Future<void> createAssignment({
    required String departmentId,
    required String departmentCode,
    required String batch,
    required String section,
    required int semester,
    required String courseCode,
    required String courseTitle,
    required String title,
    required String description,
    required DateTime deadline,
  }) async {
    await _client.from('assignments').insert({
      'teacher_id': SupabaseConfig.uid,
      'department_id': departmentId,
      'batch': batch, 'section': section, 'semester': semester,
      'course_code': courseCode, 'course_title': courseTitle,
      'title': title, 'description': description,
      'deadline': deadline.toIso8601String(),
    });

    // Notify the whole section immediately — reuses the same narrow
    // section-roster RPC teachers already have access to for grading.
    try {
      final students = await _client.rpc('list_section_students', params: {
        'p_department_code': departmentCode, 'p_batch': batch, 'p_section': section,
      }) as List;
      final ids = students.map((s) => s['id'] as String).toList();
      for (var i = 0; i < ids.length; i += 20) {
        await NotificationService.sendToUsers(
          userIds: ids.sublist(i, i + 20 > ids.length ? ids.length : i + 20),
          title: 'New assignment: $title',
          message: '$courseCode — due ${deadline.day}/${deadline.month}/${deadline.year}',
          deepLink: '/assignments', category: 'assignment',
        );
      }
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getMyAssignments() async {
    final res = await _client.from('assignments')
        .select('*, assignment_submissions(count)')
        .eq('teacher_id', SupabaseConfig.uid ?? '')
        .order('deadline', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<void> deleteAssignment(String id) async {
    await _client.from('assignments').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> getSubmissions(String assignmentId) async {
    final res = await _client.from('assignment_submissions')
        .select('*, profiles!student_id(full_name, university_id)')
        .eq('assignment_id', assignmentId).order('submitted_at') as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getMyClassAssignments() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return [];
    final assignments = await _client.from('assignments').select().order('deadline') as List;
    final mySubmissions = await _client.from('assignment_submissions')
        .select('assignment_id').eq('student_id', uid) as List;
    final submittedIds = mySubmissions.map((s) => s['assignment_id'] as String).toSet();
    return assignments.cast<Map<String, dynamic>>().map((a) => {
      ...a, 'has_submitted': submittedIds.contains(a['id']),
    }).toList();
  }

  Future<void> submitAssignment(String assignmentId, String content) async {
    await _client.from('assignment_submissions').insert({
      'assignment_id': assignmentId, 'student_id': SupabaseConfig.uid, 'content': content,
    });
  }
}
