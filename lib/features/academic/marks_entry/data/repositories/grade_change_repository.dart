import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/grade_change_request.dart';

class GradeChangeRepository {
  final _client = Supabase.instance.client;

  Future<void> submitRequest(GradeChangeRequest request) async {
    await _client.from('grade_change_requests').insert({
      'marks_id': request.marksId,
      'requested_by': request.requestedBy,
      'reason': request.reason,
      'old_values': request.oldValues,
      'new_values': request.newValues,
    });
  }

  Future<void> approveRequest(String requestId) async {
    await _client.rpc('approve_grade_change', params: {'request_id': requestId});
  }
}
