import '../../../../config/supabase_config.dart';
import '../models/class_slot.dart';

class ScheduleRepository {
  final _client = SupabaseConfig.client;

  /// Stream schedule slots, filter by dept+semester+day client-side.
  /// Supabase stream builder supports only one .eq() — we filter the rest locally.
  Stream<List<ClassSlot>> watchSchedule(String dept, int semester, int day) {
    return _client
        .from('schedule_slots')
        .stream(primaryKey: ['id'])
        .eq('department', dept)
        .order('start_time')
        .map((list) => list
            .where((s) =>
                s['semester'] == semester &&
                s['day_of_week'] == day)
            .map((s) => ClassSlot.fromJson(s))
            .toList());
  }

  /// Stream only the classes belonging to this student's own batch+section
  /// (from PDF-imported class routine data), so they don't see every other
  /// section's classes in the department.
  Stream<List<ClassSlot>> watchMyClassesAsStudent(String dept, String batch, String section, int day) {
    return _client
        .from('schedule_slots')
        .stream(primaryKey: ['id'])
        .eq('department', dept)
        .order('start_time')
        .map((list) => list
            .where((s) =>
                s['day_of_week'] == day &&
                (s['batch'] as String?)?.toLowerCase() == batch.toLowerCase() &&
                (s['section'] as String?)?.toLowerCase() == section.toLowerCase())
            .map((s) => ClassSlot.fromJson(s))
            .toList());
  }

  /// Stream only the classes taught by this teacher (matched by the
  /// initials they set in Settings, as printed in the class routine PDF).
  Stream<List<ClassSlot>> watchMyClassesAsTeacher(String teacherInitial, int day) {
    return _client
        .from('schedule_slots')
        .stream(primaryKey: ['id'])
        .eq('teacher_initial', teacherInitial)
        .order('start_time')
        .map((list) => list
            .where((s) => s['day_of_week'] == day)
            .map((s) => ClassSlot.fromJson(s))
            .toList());
  }

  Future<List<Map<String,dynamic>>> getExams(String dept, int semester) async {
    final res = await _client
        .from('exams')
        .select()
        .eq('department', dept)
        .eq('semester', semester)
        .order('exam_date') as List;
    return res.cast<Map<String,dynamic>>();
  }

  /// Exams filtered to this student's own batch, or this teacher's own
  /// initials aren't tracked on exams — teachers see the full department
  /// exam routine since they may invigilate/teach across batches.
  Future<List<Map<String,dynamic>>> getMyExams({required String dept, String? batch}) async {
    var q = _client.from('exams').select().eq('department', dept);
    if (batch != null && batch.isNotEmpty) q = q.eq('batch', batch);
    final res = await q.order('exam_date') as List;
    return res.cast<Map<String,dynamic>>();
  }

  /// Maps a teacher's routine-sheet initials (e.g. "FNN") to their real
  /// name and profile photo, so a class card can show who's actually
  /// teaching it instead of just the bare initials the PDF prints.
  Future<Map<String, ({String fullName, String? avatarUrl})>> getTeacherDirectory() async {
    final res = await _client.from('profiles')
        .select('full_name, avatar_url, teacher_initial')
        .not('teacher_initial', 'is', null) as List;
    final map = <String, ({String fullName, String? avatarUrl})>{};
    for (final row in res) {
      final initial = (row['teacher_initial'] as String?)?.trim();
      if (initial == null || initial.isEmpty) continue;
      map[initial.toLowerCase()] = (
        fullName: row['full_name'] as String? ?? initial,
        avatarUrl: row['avatar_url'] as String?,
      );
    }
    return map;
  }

  /// Resolves the Class Representative for a specific department+batch+
  /// section — lets a teacher message the CR directly from a class card
  /// ("if course match teacher can directly communicate ... by CR of that
  /// section and batch"), without needing the still-empty courses/
  /// course_offerings tables (schedule_slots already has real batch/
  /// section/department data, which is what this reuses).
  Future<Map<String, dynamic>?> findSectionCr(String departmentCode, String batch, String section) async {
    final res = await _client.rpc('find_section_cr', params: {
      'p_department_code': departmentCode, 'p_batch': batch, 'p_section': section,
    }) as List;
    return res.isNotEmpty ? res.first as Map<String, dynamic> : null;
  }
}
