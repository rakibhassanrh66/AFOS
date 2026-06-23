import 'dart:convert';

class GradeChangeRequest {
  final String id, marksId, requestedBy, reason;
  final Map<String, dynamic> oldValues, newValues;
  final String status;

  const GradeChangeRequest({
    required this.id, required this.marksId, required this.requestedBy,
    required this.reason, required this.oldValues, required this.newValues,
    required this.status,
  });

  factory GradeChangeRequest.fromJson(Map<String, dynamic> j) => GradeChangeRequest(
    id: j['id'],
    marksId: j['marks_id'],
    requestedBy: j['requested_by'],
    reason: j['reason'],
    oldValues: j['old_values'],
    newValues: j['new_values'],
    status: j['status'],
  );
}
