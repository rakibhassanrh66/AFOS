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

  Future<List<Map<String,dynamic>>> getExams(String dept, int semester) async {
    final res = await _client
        .from('exams')
        .select()
        .eq('department', dept)
        .eq('semester', semester)
        .order('exam_date') as List;
    return res.cast<Map<String,dynamic>>();
  }
}
