import 'package:flutter/foundation.dart';
import '../../../../config/supabase_config.dart';

/// Sends a targeted push + in-app notification via the send-notification
/// edge function. Direct (userIds) calls are for 1:1 notifications tied to
/// an action the caller just performed (mentorship reply, lost&found claim
/// accepted); broadcast (roleFilter/departmentFilter) calls are restricted
/// server-side to admin/teacher/dept_admin/super_admin.
class NotificationService {
  NotificationService._();

  static Future<void> sendToUsers({
    required List<String> userIds,
    required String title,
    required String message,
    String? deepLink,
    String? category,
  }) async {
    if (userIds.isEmpty) return;
    await _invoke({
      'userIds': userIds,
      'title': title,
      'message': message,
      if (deepLink != null) 'deepLink': deepLink,
      if (category != null) 'category': category,
    });
  }

  /// Pass neither roleFilter nor departmentFilter to notify every user
  /// (e.g. a university-wide notice/rule) — the edge function requires
  /// broadcastAll explicitly in that case so an empty target can never be
  /// mistaken for "no filter given, do nothing".
  static Future<void> broadcast({
    String? roleFilter,
    String? departmentFilter,
    required String title,
    required String message,
    String? deepLink,
    String? category,
  }) async {
    await _invoke({
      if (roleFilter != null) 'roleFilter': roleFilter,
      if (departmentFilter != null) 'departmentFilter': departmentFilter,
      if (roleFilter == null && departmentFilter == null) 'broadcastAll': true,
      'title': title,
      'message': message,
      if (deepLink != null) 'deepLink': deepLink,
      if (category != null) 'category': category,
    });
  }

  /// A club president notifying only their own club's members — verified
  /// server-side against clubs.president_id, not just trusted from the client.
  /// Returns how many members were actually reached (the edge function
  /// resolves club_members server-side and excludes the caller) so the
  /// caller can tell a real send apart from "the club has no other members".
  static Future<int> notifyClub({
    required String clubId,
    required String title,
    required String message,
    String? deepLink,
  }) async {
    final result = await _invoke({
      'clubId': clubId,
      'title': title,
      'message': message,
      if (deepLink != null) 'deepLink': deepLink,
      'category': 'club',
    });
    return (result?['inAppInserted'] as num?)?.toInt() ?? 0;
  }

  static Future<Map<String, dynamic>?> _invoke(Map<String, dynamic> payload) async {
    try {
      final res = await SupabaseConfig.client.functions.invoke('send-notification', body: payload);
      // The edge function returns 200 even when the OneSignal call itself
      // failed (bad REST key, wrong app id, no matching external_id) —
      // it reports that via pushError/insertError in the body, which was
      // previously never read, so a "successful" call could still silently
      // never deliver a push. Surface it so failures are visible.
      final data = res.data;
      if (data is Map) {
        if (data['insertError'] != null) {
          debugPrint('[NotificationService] in-app insert failed: ${data['insertError']}');
        }
        if (data['pushError'] != null) {
          debugPrint('[NotificationService] OneSignal push failed: ${data['pushError']}');
        }
        return data.cast<String, dynamic>();
      }
    } catch (e) {
      debugPrint('[NotificationService] invoke failed: $e');
      // Still best-effort: a failed push/in-app notification should never
      // block the action that triggered it (booking, claim acceptance,
      // etc) — but it's no longer silent, so failures show up in logs.
    }
    return null;
  }
}
