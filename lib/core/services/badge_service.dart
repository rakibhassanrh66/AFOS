import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';

/// Keeps the home-screen launcher icon badge in sync with the unread
/// `user_notifications` count — separate from the in-app bell badge
/// (`top_app_bar.dart`'s `_NotificationBell`), which only updates while
/// that widget is actually mounted/visible. This runs for the whole app
/// session regardless of which screen is showing, and is a no-op on
/// launchers that don't support badges (the plugin handles that itself).
class BadgeService {
  BadgeService._();
  static RealtimeChannel? _sub;
  static int _refreshGen = 0;

  static Future<void> start() async {
    await _refresh();
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    await _sub?.unsubscribe();
    _sub = SupabaseConfig.client.channel('badge_service_$uid')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
            table: 'user_notifications', callback: (_) => _refresh())
        .subscribe();
  }

  static Future<void> stop() async {
    await _sub?.unsubscribe();
    _sub = null;
    try { await AppBadgePlus.updateBadge(0); } catch (_) {}
  }

  static Future<void> _refresh() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    // Same out-of-order-response race as _NotificationBellState._load():
    // marking several notifications read in quick succession queues up
    // overlapping _refresh() calls whose network responses can resolve
    // out of order, letting a stale higher count overwrite a fresher
    // lower one. Only apply the result of the most recently issued query.
    final gen = ++_refreshGen;
    try {
      // HEAD count rather than fetching every unread id to call .length on:
      // this is the app-icon badge, so it re-runs on every notification
      // change, and the payload used to grow with the size of the backlog it
      // was reporting. See the same fix in top_app_bar.dart's bell.
      final unread = await SupabaseConfig.client.from('user_notifications')
          .count().eq('user_id', uid).eq('is_read', false);
      if (gen == _refreshGen) await AppBadgePlus.updateBadge(unread);
    } catch (_) {}
  }
}
