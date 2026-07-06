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
  static bool? _isVerified;

  static String? get role => _role;
  static bool? get profileCompleted => _profileCompleted;
  static bool? get isVerified => _isVerified;

  static void set(String? role, {bool? profileCompleted, bool? isVerified}) {
    _role = role;
    if (profileCompleted != null) _profileCompleted = profileCompleted;
    if (isVerified != null) _isVerified = isVerified;
  }

  static void markProfileCompleted() => _profileCompleted = true;
  static void markVerified() => _isVerified = true;

  static void clear() {
    _role = null;
    _profileCompleted = null;
    _isVerified = null;
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

  // New signups start unverified (is_verified defaults false) and need
  // super_admin approval before they can use the app; every account that
  // existed before that gate was introduced was grandfathered to true.
  static Future<bool> ensureVerifiedLoaded() async {
    if (_isVerified != null) return _isVerified!;
    await _fetch();
    return _isVerified ?? true;
  }

  static Future<void> _fetch() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('role, profile_completed, is_verified')
          .eq('id', uid)
          .maybeSingle();
      _role = row?['role'] as String?;
      _profileCompleted = row?['profile_completed'] as bool? ?? true;
      _isVerified = row?['is_verified'] as bool? ?? true;
    } catch (_) {
      _role = null;
    }
  }
}
