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

  /// The whole grant set, loading it first if needed.
  ///
  /// The router asks one question at a time ("may this user open /admin/hall?"),
  /// but the slide menu has to decide about a dozen entries in a single
  /// synchronous `build`. Awaiting [ensureHas] per item there would mean a
  /// dozen awaits inside a getter — so the menu loads once through this and
  /// then reads the set with [has].
  ///
  /// Returns an UNMODIFIABLE view: a caller that mutated this would be editing
  /// the cache the router trusts for access decisions.
  static Future<Set<String>> ensureLoaded() async {
    if (_grants == null) await _fetch();
    return Set.unmodifiable(_grants ?? const <String>{});
  }

  /// Discards the cache and loads it again.
  ///
  /// [clear] alone previously only ran at LOGOUT, which meant a permission a
  /// super_admin granted did not reach the person it was granted to until they
  /// signed out and back in — they would even get the "Your permissions were
  /// updated" notification and then find the menu unchanged. The slide menu
  /// calls this each time it opens, so a delegation takes effect the next time
  /// the user looks at their own menu.
  static Future<Set<String>> reload() async {
    clear();
    return ensureLoaded();
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
