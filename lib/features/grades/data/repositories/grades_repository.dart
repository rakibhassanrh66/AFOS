import '../../../../config/supabase_config.dart';

/// What remains of the legacy single-letter grade flow.
///
/// The old `grades` table (one hand-picked letter per student, no numbers) is
/// superseded by the component model in [MarksRepository]: marks are entered
/// against the DIU distribution and the letter is derived from
/// `grading_scale` in the database. Its upload/publish/read methods are gone
/// rather than left lying around, because a dead parallel implementation of
/// the grading rules is exactly how `marks` came to be silently unused for
/// months.
///
/// Only the section lookup survives, because Assignments still needs it.
class GradesRepository {
  final _client = SupabaseConfig.client;

  /// Distinct course/batch/section combos this teacher actually teaches.
  ///
  /// Sourced from `course_offerings.teacher_id` — a real FK to profiles, and
  /// the same table the whole approve/enrol flow already runs on.
  ///
  /// This used to read `schedule_slots.eq('teacher_initial', …)`, which was
  /// wrong in a way that showed up as "random classes I don't teach appear in
  /// Results". `teacher_initial` is free text scraped out of the routine PDF
  /// by parse-routine; it is not an identity, it is not unique across
  /// departments, and a teacher types their own into Settings. Live, initials
  /// "MSK" matched five combos belonging to a different faculty member who
  /// happens to share them, while the one offering that teacher genuinely owns
  /// was just one of the five. The query also spanned every semester ever
  /// uploaded and surfaced the `batch = 'RE'` retake pseudo-rows, which always
  /// resolve to an empty roster.
  ///
  /// Assignments uses this same method to populate its class picker, so the
  /// fix also stops a teacher posting an assignment to someone else's section.
  Future<List<Map<String, String>>> getMyTaughtSections() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return [];
    final res = await _client.from('course_offerings')
        .select('section, department, batch, semester, courses(code, title)')
        .eq('teacher_id', uid)
        .eq('status', 'approved')
        .eq('is_archived', false) as List;
    final seen = <String>{};
    final out = <Map<String, String>>[];
    for (final row in res) {
      final course = row['courses'] as Map<String, dynamic>? ?? const {};
      final code = course['code'] as String?;
      final batch = row['batch'] as String?;
      final section = row['section'] as String?;
      final dept = row['department'] as String?;
      if (code == null || batch == null || section == null || dept == null) continue;
      final key = '$code|$batch|$section';
      if (seen.add(key)) {
        out.add({
          'subjectCode': code, 'subject': course['title'] as String? ?? code,
          'batch': batch, 'section': section, 'department': dept,
          'semester': (row['semester'] as int? ?? 1).toString(),
        });
      }
    }
    return out;
  }
}
