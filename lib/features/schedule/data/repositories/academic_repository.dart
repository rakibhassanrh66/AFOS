import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/course.dart';

class AcademicRepository {
  final _client = Supabase.instance.client;

  Future<List<Course>> getCourses() async {
    final data = await _client.from('courses').select('*');
    return (data as List).map((j) => Course.fromJson(j)).toList();
  }

  Future<void> enroll(String studentId, String offeringId) async {
    await _client.from('enrollments').insert({
      'student_id': studentId,
      'offering_id': offeringId,
    });
  }
}
