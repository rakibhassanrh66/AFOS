import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory cache of the signed-in user's DELEGATED permission grants — the
/// client-side counterpart to the database's `caller_can(resource, action)`
/// (already used by several RLS policies: transport_routes, schedule_slots,
/// exam_room_allocations, notices, and now also halls, hall_applications,
/// sos_alerts, books, borrowed_books, conference_room_requests).
///
/// This exists so a super_admin can delegate ONE specific area of admin work
/// to a non-admin-role user (e.g. "transport:upload" without making them a
/// full `admin`) via Manage Users, and have it actually work end to end.
/// Granting the permission alone only unlocks the underlying DATA (RLS) —
/// without this session cache feeding `app_router.dart`'s redirect guard,
/// the router would still bounce that user away from the matching `/admin/*`
/// screen before they ever got a chance to use the access RLS already grants
/// them. Mirrors [RoleSession]'s own cache-until-cleared pattern.
class PermissionSession {
  PermissionSession._();
  static Set<String>? _grants; // "resource:action" strings

  static void clear() => _grants = null;

  static bool has(String resource, String action) =>
      _grants?.contains('$resource:$action') ?? false;

  /// Loads the grant set on first use (or after [clear]), then checks —
  /// the router calls this directly since it can't assume the cache is
  /// already warm the way an already-rendered screen can.
  static Future<bool> ensureHas(String resource, String action) async {
    if (_grants == null) await _fetch();
    return has(resource, action);
  }

  static Future<void> _fetch() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) { _grants = {}; return; }
    try {
      final rows = await Supabase.instance.client.rpc('list_my_permissions') as List;
      _grants = rows
          .map((r) => '${(r as Map)['resource']}:${r['action']}')
          .toSet();
    } catch (_) {
      // Best-effort: a failed load must never grant access by accident —
      // an empty set means every ensureHas() call fails closed, same as
      // "not delegated this permission", not "let them through".
      _grants = {};
    }
  }
}
