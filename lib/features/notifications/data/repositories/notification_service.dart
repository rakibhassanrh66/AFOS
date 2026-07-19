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
  /// Returns the edge function's result (`{inAppInserted, insertError,
  /// pushTargeted, pushError}`) or null if the call itself failed, so callers
  /// can confirm delivery and show the admin a real outcome instead of assuming
  /// success. Still best-effort — it never throws.
  static Future<Map<String, dynamic>?> broadcast({
    String? roleFilter,
    String? departmentFilter,
    required String title,
    required String message,
    String? deepLink,
    String? category,
  }) async {
    return _invoke({
      if (roleFilter != null) 'roleFilter': roleFilter,
      if (departmentFilter != null) 'departmentFilter': departmentFilter,
      if (roleFilter == null && departmentFilter == null) 'broadcastAll': true,
      'title': title,
      'message': message,
      if (deepLink != null) 'deepLink': deepLink,
      if (category != null) 'category': category,
    });
  }

  /// Notifies every user holding any of the given roles — for a student/
  /// teacher submission (hall application, complaint, CR request,
  /// conference room request) that needs an admin-tier role's attention.
  /// Those callers can't use [broadcast] (its roleFilter path is
  /// restricted server-side to admin/super_admin/dept_admin/teacher
  /// callers), so this resolves recipients via the list_role_holders RPC
  /// and sends direct notifications instead, chunked under the 20-per-call
  /// cap. Best-effort: a resolution or send failure never throws, since a
  /// failed notification shouldn't undo the submission that triggered it.
  static Future<void> notifyRoles({
    required List<String> roles,
    required String title,
    required String message,
    String? deepLink,
    String? category,
  }) async {
    try {
      final res = await SupabaseConfig.client
          .rpc('list_role_holders', params: {'p_roles': roles}) as List;
      final ids = res.map((r) => (r as Map)['profile_id'] as String).toList();
      for (var i = 0; i < ids.length; i += 20) {
        await sendToUsers(
          userIds: ids.sublist(i, i + 20 > ids.length ? ids.length : i + 20),
          title: title, message: message, deepLink: deepLink, category: category,
        );
      }
    } catch (e) {
      debugPrint('[NotificationService] notifyRoles failed: $e');
    }
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
