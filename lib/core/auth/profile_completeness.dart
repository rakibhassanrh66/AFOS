/// Mirrors `profile_is_complete()` in Postgres.
///
/// The DATABASE is the authority: a `BEFORE INSERT OR UPDATE` trigger on
/// `profiles` overwrites `profile_completed` with its own verdict on every
/// write, so a client cannot claim to be complete. This file exists so the
/// form can grey out Save without a round trip, and so the required-field
/// matrix is pinned by a test that needs no connection.
///
/// If the two ever disagree, the SQL wins and this file is the bug.
library;

/// A blank string is not a filled field.
///
/// `department = ''` already defeated `?? 'default'` in this project once and
/// rendered an empty chip, so emptiness is tested after trimming rather than
/// by a null check alone.
bool _has(Object? v) => v != null && v.toString().trim().isNotEmpty;

/// Whether [p] — a `profiles` row as PostgREST returns it — carries every
/// detail its role is required to provide.
bool isProfileComplete(Map<String, dynamic> p) {
  final role = (p['role'] ?? '').toString().trim();

  // Everyone, whatever they are, owes a way to be reached and an address.
  final everyone = _has(p['full_name']) &&
      _has(p['phone']) &&
      _has(p['gender']) &&
      _has(p['emergency_contact']) &&
      _has(p['permanent_division']) &&
      _has(p['permanent_district']) &&
      _has(p['permanent_upazila']);
  if (!everyone) return false;

  // permanent_thana is deliberately NOT required: it only applies to
  // city-corporation addresses (3 of 14 people have one), and requiring it
  // would wedge every rural address permanently.
  switch (role) {
    case 'student':
      return _has(p['department_id']) &&
          _has(p['batch']) &&
          _has(p['section']) &&
          _has(p['semester']) &&
          _has(p['admission_season']) &&
          _has(p['admission_year']) &&
          _has(p['joined_on']);
    case 'teacher':
      return _has(p['department_id']) &&
          _has(p['designation']) &&
          _has(p['joined_on']);
    case 'staff':
      return _has(p['designation']) && _has(p['joined_on']);
    default:
      // admin / super_admin carry no academic identity. An ABSENT role is a
      // different thing entirely — an unreadable or missing row — and must
      // never be treated as a complete one, because this value gates the
      // whole app.
      return _has(p['role']);
  }
}
