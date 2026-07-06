import '../../../../config/supabase_config.dart';
import '../../../notifications/data/repositories/notification_service.dart';

class GradesRepository {
  final _client = SupabaseConfig.client;

  /// Distinct subject/batch/section combos this teacher actually teaches,
  /// derived from schedule_slots (real, populated data) rather than the
  /// still-empty courses/course_offerings tables.
  Future<List<Map<String, String>>> getMyTaughtSections(String teacherInitial) async {
    final res = await _client.from('schedule_slots')
        .select('subject_code, subject, batch, section, department, semester')
        .eq('teacher_initial', teacherInitial) as List;
    final seen = <String>{};
    final out = <Map<String, String>>[];
    for (final row in res) {
      final code = row['subject_code'] as String?;
      final batch = row['batch'] as String?;
      final section = row['section'] as String?;
      final dept = row['department'] as String?;
      if (code == null || batch == null || section == null || dept == null) continue;
      final key = '$code|$batch|$section';
      if (seen.add(key)) {
        out.add({
          'subjectCode': code, 'subject': row['subject'] as String? ?? code,
          'batch': batch, 'section': section, 'department': dept,
          'semester': (row['semester'] as int? ?? 1).toString(),
        });
      }
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> listSectionStudents(String departmentCode, String batch, String section) async {
    final res = await _client.rpc('list_section_students', params: {
      'p_department_code': departmentCode, 'p_batch': batch, 'p_section': section,
    }) as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<void> upsertGrade({
    required String studentId,
    required String courseCode,
    required String courseTitle,
    required int semester,
    required String batch,
    required String section,
    required String gradeLetter,
    double? marks,
  }) async {
    await _client.from('grades').upsert({
      'student_id': studentId,
      'teacher_id': SupabaseConfig.uid,
      'course_code': courseCode,
      'course_title': courseTitle,
      'semester': semester,
      'batch': batch,
      'section': section,
      'grade_letter': gradeLetter,
      'marks': marks,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'student_id,course_code,semester');
  }

  Future<List<Map<String, dynamic>>> getMyUploads() async {
    final res = await _client.from('grades')
        .select('*, profiles!student_id(full_name, university_id)')
        .eq('teacher_id', SupabaseConfig.uid ?? '')
        .order('created_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> getPendingPublish() async {
    final res = await _client.from('grades')
        .select('*, profiles!student_id(full_name, university_id), teacher:profiles!teacher_id(full_name)')
        .eq('is_published', false)
        .order('created_at', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }

  Future<void> publishGrades(List<String> ids) async {
    final rows = await _client.from('grades').select('id, student_id, course_code, course_title, semester')
        .inFilter('id', ids) as List;
    await _client.from('grades').update({
      'is_published': true,
      'published_by': SupabaseConfig.uid,
      'published_at': DateTime.now().toIso8601String(),
    }).inFilter('id', ids);
    for (final row in rows) {
      final studentId = row['student_id'] as String?;
      if (studentId == null) continue;
      await NotificationService.sendToUsers(
        userIds: [studentId],
        title: 'Result published',
        message: '${row['course_title'] ?? row['course_code']} (Semester ${row['semester']}) result is now available.',
        deepLink: '/grades', category: 'grades',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getMyResults() async {
    final res = await _client.from('grades')
        .select().eq('student_id', SupabaseConfig.uid ?? '').eq('is_published', true)
        .order('semester', ascending: false) as List;
    return res.cast<Map<String, dynamic>>();
  }
}
