import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/mark.dart';

class MarksRepository {
  final _client = Supabase.instance.client;

  Future<void> updateMarks(Mark mark) async {
    await _client.from('marks').update({
      'attendance_marks': mark.attendance,
      'quiz_marks': mark.quiz,
      'assignment_marks': mark.assignment,
      'midterm_marks': mark.midterm,
      'final_marks': mark.finalMarks,
    }).eq('id', mark.id);
  }
}
