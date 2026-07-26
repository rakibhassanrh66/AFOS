import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

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
    double maxMarks = 10,
  }) async {
    await _client.from('assignments').insert({
      'teacher_id': SupabaseConfig.uid,
      'department_id': departmentId,
      'batch': batch, 'section': section, 'semester': semester,
      'course_code': courseCode, 'course_title': courseTitle,
      'title': title, 'description': description,
      'deadline': deadline.toIso8601String(),
      'max_marks': maxMarks,
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
        .select('*, profiles!student_id(full_name, university_id, avatar_url)')
        .eq('assignment_id', assignmentId).order('submitted_at') as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// Marks and feedback for one submission.
  ///
  /// `graded_by` / `graded_at` are stamped by a DB trigger rather than sent
  /// from here, so who marked a piece of work can't be spoofed by the client,
  /// and the ceiling is checked against the assignment's own `max_marks`
  /// (cross-table, so it can't be a CHECK) -- an over-max value throws.
  Future<void> gradeSubmission({
    required String submissionId,
    required double marks,
    String? feedback,
  }) =>
      _client.from('assignment_submissions').update({
        'marks': marks,
        if (feedback != null) 'feedback': feedback.trim(),
      }).eq('id', submissionId);

  /// Signed URL for a submitted file. The bucket is private -- coursework is
  /// the student's own work and must not be readable by anyone who guesses the
  /// URL -- so a short-lived signed link is the only way in.
  Future<String?> signedAttachmentUrl(String attachmentPath) async {
    try {
      return await _client.storage
          .from('assignment-submissions')
          .createSignedUrl(attachmentPath, 300);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getMyClassAssignments() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return [];
    // RLS (student_read_own_section_assignments) already scopes this to only
    // the caller's own department/batch/section — narrowing the column list
    // (not adding a redundant filter) is the real saving here, since the row
    // set returned is identical either way.
    final assignments = await _client.from('assignments')
        .select('id, title, course_code, course_title, description, deadline, max_marks')
        .order('deadline') as List;
    // Marks/feedback come back too, so a student sees what they scored rather
    // than only that they handed something in.
    final mySubmissions = await _client.from('assignment_submissions')
        .select('id, assignment_id, content, marks, feedback, attachment_url')
        .eq('student_id', uid) as List;
    final mine = {
      for (final s in mySubmissions.cast<Map<String, dynamic>>())
        s['assignment_id'] as String: s,
    };
    return assignments.cast<Map<String, dynamic>>().map((a) => {
      ...a,
      'has_submitted': mine.containsKey(a['id']),
      'my_submission': mine[a['id']],
    }).toList();
  }

  /// Upserts rather than inserts: a student may revise their answer until the
  /// deadline (RLS enforces the cutoff, and refuses an edit once a mark has
  /// been entered). The table is unique per (assignment, student), so a second
  /// hand-in replaces the first instead of failing on the constraint.
  Future<void> submitAssignment(
    String assignmentId,
    String content, {
    String? attachmentPath,
  }) async {
    await _client.from('assignment_submissions').upsert({
      'assignment_id': assignmentId,
      'student_id': SupabaseConfig.uid,
      'content': content,
      if (attachmentPath != null) 'attachment_url': attachmentPath,
      'submitted_at': DateTime.now().toIso8601String(),
    }, onConflict: 'assignment_id,student_id');
  }

  /// Uploads coursework to the private bucket under `{uid}/…`, the path
  /// convention every other bucket and StorageUploadService already use, and
  /// which the storage policies key ownership off. Returns the storage path
  /// (not a URL) — the bucket is private, so the path is what gets stored and
  /// signed on demand.
  Future<String> uploadSubmissionFile({
    required String assignmentId,
    required String filename,
    required Uint8List bytes,
  }) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) throw StateError('Not signed in');
    final ext = filename.contains('.') ? filename.split('.').last : 'bin';
    final path = '$uid/${assignmentId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from('assignment-submissions').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }
}
