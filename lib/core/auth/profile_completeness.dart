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

/// The last 10 digits, so "+880 1712-345678" and "01712345678" compare equal
/// — a leading 0 is the local-dialling equivalent of the +880 country code,
/// and both share the same 10-digit subscriber number. Mirrors the
/// `right(regexp_replace(..., '\D', '', 'g'), 10)` comparison in
/// `profile_is_complete()`.
String _digits(Object? v) {
  final d = v.toString().replaceAll(RegExp(r'\D'), '');
  return d.length <= 10 ? d : d.substring(d.length - 10);
}

/// Whether [p] — a `profiles` row as PostgREST returns it — carries every
/// detail its role is required to provide.
///
/// [now] is injectable only for the photo-deadline clause below; every real
/// call site omits it and gets the actual clock.
bool isProfileComplete(Map<String, dynamic> p, {DateTime? now}) {
  final role = (p['role'] ?? '').toString().trim();
  final at = now ?? DateTime.now();

  // Everyone, whatever they are, owes a way to be reached and an address.
  final everyone = _has(p['full_name']) &&
      _has(p['phone']) &&
      _has(p['gender']) &&
      _has(p['emergency_contact']) &&
      _has(p['permanent_division']) &&
      _has(p['permanent_district']) &&
      _has(p['permanent_upazila']);
  if (!everyone) return false;

  // An emergency contact identical to the user's own number is not a second
  // point of contact — compared on digits only so formatting cannot dodge it.
  if (_digits(p['emergency_contact']) == _digits(p['phone'])) return false;

  // A real, admin-checked photo is required within 48h of verification.
  // Compliant while: not yet verified (is_verified already blocks the account
  // from doing anything, so the photo clock has not started); still inside
  // the grace window; or already engaged (pending review or approved). Only
  // "never uploaded" or "uploaded and rejected, never resubmitted" blocks
  // once the deadline passes.
  final verifiedAt = DateTime.tryParse('${p['verified_at'] ?? ''}');
  final avatarStatus = (p['avatar_review_status'] ?? 'none').toString();
  final photoOk = verifiedAt == null ||
      at.difference(verifiedAt) < const Duration(hours: 48) ||
      avatarStatus == 'pending' ||
      avatarStatus == 'approved';
  if (!photoOk) return false;

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

/// Which of [isProfileComplete]'s checks [p] is actually failing, in the same
/// order that function tests them — for the admin Inspection screen, which
/// needs to SHOW a reason, not just a pass/fail. Never used to gate anything;
/// [isProfileComplete] (and the database behind it) remains the one verdict
/// that matters.
List<String> incompleteReasons(Map<String, dynamic> p, {DateTime? now}) {
  final role = (p['role'] ?? '').toString().trim();
  final at = now ?? DateTime.now();
  final reasons = <String>[];

  void need(bool ok, String label) { if (!ok) reasons.add(label); }

  need(_has(p['full_name']), 'Full name');
  need(_has(p['phone']), 'Phone number');
  need(_has(p['gender']), 'Gender');
  need(_has(p['emergency_contact']), 'Emergency contact');
  need(_has(p['permanent_division']), 'Permanent division');
  need(_has(p['permanent_district']), 'Permanent district');
  need(_has(p['permanent_upazila']), 'Permanent upazila');

  if (_has(p['emergency_contact']) && _has(p['phone']) &&
      _digits(p['emergency_contact']) == _digits(p['phone'])) {
    reasons.add('Emergency contact is the same as their own number');
  }

  final verifiedAt = DateTime.tryParse('${p['verified_at'] ?? ''}');
  final avatarStatus = (p['avatar_review_status'] ?? 'none').toString();
  final photoOk = verifiedAt == null ||
      at.difference(verifiedAt) < const Duration(hours: 48) ||
      avatarStatus == 'pending' ||
      avatarStatus == 'approved';
  if (!photoOk) {
    reasons.add(avatarStatus == 'rejected'
        ? 'Photo was rejected and never resubmitted'
        : 'No photo uploaded past the 48h deadline');
  }

  switch (role) {
    case 'student':
      need(_has(p['department_id']), 'Department');
      need(_has(p['batch']), 'Batch');
      need(_has(p['section']), 'Section');
      need(_has(p['semester']), 'Semester');
      need(_has(p['admission_season']), 'Admission season');
      need(_has(p['admission_year']), 'Admission year');
      need(_has(p['joined_on']), 'Join date');
      break;
    case 'teacher':
      need(_has(p['department_id']), 'Department');
      need(_has(p['designation']), 'Designation');
      need(_has(p['joined_on']), 'Join date');
      break;
    case 'staff':
      need(_has(p['designation']), 'Designation');
      need(_has(p['joined_on']), 'Join date');
      break;
    default:
      need(_has(p['role']), 'Role');
  }

  return reasons;
}

/// (fields still missing, fields required in total) for [p] — the same
/// checks [incompleteReasons] runs, counted rather than named. Exists to draw
/// a completion ring; what to actually SAY about a gap still comes from
/// [incompleteReasons], and whether the account may proceed at all is still
/// [isProfileComplete]'s call alone.
(int missing, int total) profileCompletionCounts(Map<String, dynamic> p, {DateTime? now}) {
  final role = (p['role'] ?? '').toString().trim();
  // The 7 everyone-fields, the emergency-contact-distinct check, the photo
  // check — every "everyone" clause incompleteReasons can raise.
  const everyoneChecks = 9;
  final roleChecks = switch (role) {
    'student' => 7,
    'teacher' => 3,
    'staff' => 2,
    _ => 1,
  };
  return (incompleteReasons(p, now: now).length, everyoneChecks + roleChecks);
}
