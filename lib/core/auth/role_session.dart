import 'package:supabase_flutter/supabase_flutter.dart';

/// In-memory cache of the signed-in user's profile role + completion
/// status, so the router's redirect callback can gate admin-only routes
/// and the force-complete-profile flow without firing a network request on
/// every navigation. Populated on login/session-check, cleared on logout.
/// RLS remains the authoritative access control for data — this only
/// controls what the UI navigates to.
class RoleSession {
  RoleSession._();
  static String? _role;
  static bool? _profileCompleted;

  static String? get role => _role;
  static bool? get profileCompleted => _profileCompleted;

  static void set(String? role, {bool? profileCompleted}) {
    _role = role;
    if (profileCompleted != null) _profileCompleted = profileCompleted;
  }

  static void markProfileCompleted() => _profileCompleted = true;

  static void clear() {
    _role = null;
    _profileCompleted = null;
  }

  static Future<String?> ensureLoaded() async {
    if (_role != null) return _role;
    await _fetch();
    return _role;
  }

  static Future<bool> ensureProfileCompletedLoaded() async {
    if (_profileCompleted != null) return _profileCompleted!;
    await _fetch();
    return _profileCompleted ?? true;
  }

  static Future<void> _fetch() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('role, profile_completed')
          .eq('id', uid)
          .maybeSingle();
      _role = row?['role'] as String?;
      _profileCompleted = row?['profile_completed'] as bool? ?? true;
    } catch (_) {
      _role = null;
    }
  }
}
