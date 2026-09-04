import '../../../../config/supabase_config.dart';
import '../models/teacher_link.dart';

/// Advising and FYDP supervision, both sides of it.
///
/// Every rule lives on the server. This class calls four RPCs and reads two
/// tables; it decides nothing. In particular it does NOT decide how much of a
/// student a teacher may see — `student_profile_for_link` already returned a
/// row with the restricted columns null, so there is no client-side filtering
/// here that a future edit could quietly loosen.
class AdvisingRepository {
  final _client = SupabaseConfig.client;

  /// The teacher behind an initial, or null when nothing matches.
  ///
  /// Resolves against teacher PROFILES. It deliberately cannot see
  /// `schedule_slots`, which carries 221 free-text initials scraped from the
  /// routine PDF that belong to no account — matching those is what once
  /// listed another teacher's classes as your own.
  Future<TeacherCard?> resolveInitial(String initial) async {
    final trimmed = initial.trim();
    if (trimmed.isEmpty) return null;
    final rows = await _client
        .rpc('resolve_teacher_initial', params: {'p_initial': trimmed}) as List;
    if (rows.isEmpty) return null;
    return TeacherCard.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Ask a teacher to take you on. Returns the new link's id.
  ///
  /// Throws with a sentence meant to be shown as-is: the server raises
  /// "No teacher is registered under the initial …", "You already have an
  /// advisor request open …" and the semester rule for FYDP.
  Future<String> request(String initial, LinkKind kind) async {
    final id = await _client.rpc('request_teacher_link', params: {
      'p_initial': initial.trim(),
      'p_kind': kind.wire,
    });
    return id as String;
  }

  /// The signed-in student's own links, newest first.
  Future<List<TeacherLink>> myLinks() async {
    final rows = await _client
        .from('teacher_links')
        .select('id, kind, status, teacher_id, student_id, decline_reason, requested_at')
        .order('requested_at', ascending: false) as List;
    return rows
        .map((r) => TeacherLink.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// The live link of one kind, or null. Row-level security already limits
  /// this to the caller's own rows, so no student filter is needed here.
  Future<TeacherLink?> myLink(LinkKind kind) async {
    final all = await myLinks();
    for (final l in all) {
      if (l.kind == kind && l.status.isLive) return l;
    }
    return null;
  }

  /// Withdraw a request that has not been answered, or release an active one.
  Future<void> end(String linkId) async {
    await _client.from('teacher_links').update({'status': 'ended'}).eq('id', linkId);
  }

  // ---------------------------------------------------------------- teacher

  /// Everything waiting on, or belonging to, the signed-in teacher.
  ///
  /// Returns the raw rows joined to the student's NAME AND ID ONLY. That is
  /// all a teacher may see before accepting — the full profile comes from
  /// [studentFor], which refuses while the link is pending.
  Future<List<Map<String, dynamic>>> myStudents({LinkStatus? status}) async {
    var q = _client
        .from('teacher_links')
        .select('id, kind, status, student_id, requested_at, '
            'profiles!teacher_links_student_id_fkey(full_name, university_id, avatar_url)');
    if (status != null) q = q.eq('status', status.name);
    final rows = await q.order('requested_at', ascending: false) as List;
    return rows.cast<Map<String, dynamic>>();
  }

  /// The student behind a link, scoped by the server to this link's kind.
  ///
  /// Throws while the link is pending — which is the point, and is asserted
  /// in the migration's own verification.
  Future<LinkedStudent?> studentFor(String linkId) async {
    final rows = await _client
        .rpc('student_profile_for_link', params: {'p_link_id': linkId}) as List;
    if (rows.isEmpty) return null;
    return LinkedStudent.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Accept or decline a pending request.
  Future<void> decide(String linkId, {required bool accept, String? reason}) =>
      _client.rpc('decide_teacher_link', params: {
        'p_link_id': linkId,
        'p_accept': accept,
        'p_reason': reason,
      });

  // ----------------------------------------------------------------- thread

  Future<List<Map<String, dynamic>>> messages(String linkId) async {
    final rows = await _client
        .from('teacher_link_messages')
        .select('id, sender_id, body, created_at')
        .eq('link_id', linkId)
        .order('created_at') as List;
    return rows.cast<Map<String, dynamic>>();
  }

  Future<void> send(String linkId, String senderId, String body) =>
      _client.from('teacher_link_messages').insert({
        'link_id': linkId,
        'sender_id': senderId,
        'body': body.trim(),
      });

  // ----------------------------------------------------------- availability

  /// A teacher's weekly office hours, ordered as a week reads.
  Future<List<Map<String, dynamic>>> officeHours(String teacherId) async {
    final rows = await _client
        .from('teacher_office_hours')
        .select('day_of_week, start_time, end_time, note')
        .eq('teacher_id', teacherId)
        .order('day_of_week')
        .order('start_time') as List;
    return rows.cast<Map<String, dynamic>>();
  }

  /// Leave that has not finished yet. Past leave is not news.
  Future<List<Map<String, dynamic>>> upcomingLeave(String teacherId) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final rows = await _client
        .from('teacher_leave')
        .select('starts_on, ends_on, reason')
        .eq('teacher_id', teacherId)
        .gte('ends_on', today)
        .order('starts_on') as List;
    return rows.cast<Map<String, dynamic>>();
  }
}
