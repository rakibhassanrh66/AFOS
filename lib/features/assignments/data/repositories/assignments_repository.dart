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
    /// Storage PATH of the teacher's brief, from [uploadBriefFile]. Optional
    /// and defaulted, so every existing caller compiles unchanged — the
    /// constitution forbids changing a repository signature, and this was
    /// added only after the owner asked for the attach control explicitly.
    /// Omitted entirely from the insert when null, so a plain assignment
    /// writes exactly the columns it always did.
    String? attachmentPath,
  }) async {
    await _client.from('assignments').insert({
      'teacher_id': SupabaseConfig.uid,
      'department_id': departmentId,
      'batch': batch, 'section': section, 'semester': semester,
      'course_code': courseCode, 'course_title': courseTitle,
      'title': title, 'description': description,
      'deadline': deadline.toIso8601String(),
      'max_marks': maxMarks,
      if (attachmentPath != null) 'attachment_url': attachmentPath,
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

  /// Deletes the assignment and the brief attached to it.
  ///
  /// The file goes FIRST and its failure is swallowed: `attachment_url` is
  /// what `assignment_brief_read` keys on, so once the row is gone nobody can
  /// read the object anyway — a stranded file is a storage leak, not an
  /// exposure. Letting a storage hiccup abort the delete would instead leave
  /// the teacher unable to remove an assignment at all, which is worse.
  Future<void> deleteAssignment(String id) async {
    try {
      final row = await _client.from('assignments')
          .select('attachment_url').eq('id', id).maybeSingle();
      final path = row?['attachment_url'] as String?;
      if (path != null && path.isNotEmpty) {
        await _client.storage.from('assignment-submissions').remove([path]);
      }
    } catch (_) {}
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
    // `attachment_url` added when teachers gained the attach control — without
    // it the brief is written but never fetched, so the student card could
    // never offer it. Additive: the return type and every existing key are
    // unchanged, so no caller has to adapt.
    final assignments = await _client.from('assignments')
        .select('id, title, course_code, course_title, description, deadline, max_marks, attachment_url')
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
  }) =>
      _put('${assignmentId}_${DateTime.now().millisecondsSinceEpoch}', filename, bytes);

  /// Uploads a TEACHER's brief — the question paper or handout that goes out
  /// with an assignment — and returns its storage path.
  ///
  /// Same private bucket and same `{uid}/…` convention as a submission, which
  /// is what the bucket's INSERT policy keys on, so a teacher can write it
  /// without a new policy. Reading it needed one: a brief sits under the
  /// TEACHER's folder, and the two SELECT policies covered only your own
  /// folder and a teacher reading submissions to their own assignment — a
  /// student matched neither. `assignment_brief_read` (20260901120000) closes
  /// that by allowing a read when some assignment row THE CALLER CAN SEE
  /// points at the object, which inherits the assignments table's own scoping
  /// instead of restating it.
  ///
  /// Uploaded BEFORE the row exists, so the name is keyed by time rather than
  /// by assignment id — there is no id yet to key it by.
  Future<String> uploadBriefFile({
    required String filename,
    required Uint8List bytes,
  }) =>
      _put('brief_${DateTime.now().millisecondsSinceEpoch}', filename, bytes);

  Future<String> _put(String stem, String filename, Uint8List bytes) async {
    final uid = SupabaseConfig.uid;
    if (uid == null) throw StateError('Not signed in');
    final ext = filename.contains('.') ? filename.split('.').last : 'bin';
    final path = '$uid/$stem.$ext';
    await _client.storage.from('assignment-submissions').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return path;
  }
}
