import 'dart:io';
import '../../config/supabase_config.dart';
import '../../features/notifications/data/repositories/notification_service.dart';
import 'outbox_service.dart';

/// Registers every outbox action handler once at app start (called from
/// bootstrap.dart) rather than lazily inside each screen -- a queued action
/// must flush even if the user never revisits the screen that created it
/// this session. Each handler also fires the post-submit notification that
/// used to live in the screen itself, so it fires exactly once whether the
/// submit went through immediately or was queued and flushed later.
void registerOutboxHandlers() {
  OutboxService.instance.registerHandler('hall_application_submit', (p) async {
    await SupabaseConfig.client.from('hall_applications').insert({
      'student_id': p['student_id'],
      'preferred_hall': p['preferred_hall'],
      'preference': p['preference'],
      'reason': p['reason'],
      'status': 'pending',
    });
    NotificationService.notifyRoles(
      roles: const ['admin', 'staff', 'super_admin'],
      title: 'New hall application',
      message: 'A student applied for ${p['preferred_hall']}.',
      category: 'hall', deepLink: '/admin/hall',
    );
  });

  OutboxService.instance.registerHandler('hall_complaint_submit', (p) async {
    await SupabaseConfig.client.from('hall_complaints').insert({
      'student_id': p['student_id'],
      'category': p['category'],
      'description': p['description'],
      'status': 'open',
    });
    NotificationService.notifyRoles(
      roles: const ['admin', 'staff', 'super_admin'],
      title: 'New hall complaint',
      message: 'A student filed a ${p['category']} complaint.',
      category: 'hall', deepLink: '/admin/hall',
    );
  });

  OutboxService.instance.registerHandler('feedback_submit', (p) async {
    var payload = Map<String, dynamic>.from(p);
    final localPath = payload.remove('local_file_path') as String?;
    if (localPath != null) {
      try {
        final path = '${payload['user_id']}/${DateTime.now().millisecondsSinceEpoch}_${payload['file_name']}';
        await SupabaseConfig.client.storage.from('feedback-attachments')
            .uploadBinary(path, await File(localPath).readAsBytes());
        payload['file_url'] = path;
      } catch (_) {
        // The picked file may no longer be on disk by the time connectivity
        // returns (e.g. OS cache reclaim) -- still send the text feedback
        // rather than losing the whole submission over a missing attachment.
        payload['file_url'] = null;
        payload['file_name'] = null;
      }
    }
    await SupabaseConfig.client.from('feedback').insert(payload);
    NotificationService.notifyRoles(
      roles: const ['super_admin'],
      title: 'New feedback submitted',
      message: (payload['title'] as String?)?.isNotEmpty == true
          ? payload['title'] as String : payload['message'] as String? ?? '',
      deepLink: '/admin/feedback', category: 'feedback',
    );
  });

  OutboxService.instance.registerHandler('mentorship_booking_request', (p) async {
    await SupabaseConfig.client.from('mentorship_bookings').insert({
      'student_id': p['student_id'],
      'mentor_id': p['mentor_id'],
      'topic': p['topic'],
      'status': 'pending',
    });
    NotificationService.sendToUsers(
      userIds: [p['mentor_id'] as String],
      title: 'New mentorship request',
      message: '${p['student_name'] ?? 'A student'} — new request awaiting your response',
      deepLink: '/mentorship', category: 'mentorship',
    );
  });

  OutboxService.instance.registerHandler('club_join_request', (p) async {
    await SupabaseConfig.client.from('club_membership_requests')
        .insert({'club_id': p['club_id'], 'student_id': p['student_id']});
    final presidentId = p['president_id'] as String?;
    if (presidentId != null) {
      NotificationService.sendToUsers(
        userIds: [presidentId],
        title: 'New membership request',
        message: 'A student wants to join ${p['club_name'] ?? 'your club'}.',
        category: 'club', deepLink: '/clubs',
      );
    }
  });

  OutboxService.instance.registerHandler('cr_request', (p) async {
    await SupabaseConfig.client.from('cr_requests').insert({
      'student_id': p['student_id'],
      'department_id': p['department_id'],
      'batch_label': p['batch_label'],
      'section': p['section'],
    });
    NotificationService.notifyRoles(
      roles: const ['super_admin'],
      title: 'New CR request',
      message: 'A student requested to become Class Representative.',
      category: 'general', deepLink: '/admin/users',
    );
  });
}
