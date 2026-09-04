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
  static DateTime? _graceUntil;

  static String? get role => _role;
  static bool? get profileCompleted => _profileCompleted;
  static bool? get isVerified => _isVerified;

  /// When an incomplete profile stops being allowed to skip. Null once the
  /// profile is complete, and null for a row that could not be read.
  static DateTime? get graceUntil => _graceUntil;

  /// True while an incomplete profile may still use the app.
  ///
  /// Fails CLOSED, like [_profileCompleted]: no deadline means no grace. The
  /// database sets one the first time a row reads incomplete, so the only way
  /// to arrive here with null is a row that could not be read — and that must
  /// not become an open door.
  static bool get insideGrace {
    final until = _graceUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  static void set(String? role, {bool? profileCompleted, bool? isVerified}) {
    _role = role;
    if (profileCompleted != null) _profileCompleted = profileCompleted;
    if (isVerified != null) _isVerified = isVerified;
  }

  static void markProfileCompleted() {
    _profileCompleted = true;
    _graceUntil = null;
  }
  static void markVerified() => _isVerified = true;

  static void clear() {
    _role = null;
    _profileCompleted = null;
    _isVerified = null;
    _graceUntil = null;
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
          .select('role, profile_completed, is_verified, profile_grace_until')
          .eq('id', uid)
          .maybeSingle();
      _role = row?['role'] as String?;
      // Fails CLOSED. This was `?? true`, which was defensible while the flag
      // was cosmetic -- but it is now the enforcement point for mandatory
      // profile details, and an unreadable or missing row must not walk past
      // the gate. Worst case is one extra trip through a form they can fill.
      // `_isVerified` below deliberately keeps `?? true`: that one grandfathers
      // accounts which predate the approval gate.
      _profileCompleted = row?['profile_completed'] as bool? ?? false;
      _isVerified = row?['is_verified'] as bool? ?? true;
      _graceUntil = DateTime.tryParse('${row?['profile_grace_until'] ?? ''}');
    } catch (_) {
      _role = null;
    }
  }
}
