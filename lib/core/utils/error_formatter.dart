import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Matches a Postgres/PostgREST message that names schema internals.
///
/// These arrive verbatim from the database and routinely contain table,
/// column and constraint names — e.g. `null value in column "department_id"
/// of relation "profiles" violates not-null constraint`. Showing that to a
/// user is both useless and a free map of the schema, so anything matching
/// this is replaced with a generic message (the real text still goes to the
/// debug log for developers).
final _schemaLeakPattern = RegExp(
  r'\b(relation|column|constraint|table|schema|function|operator|type)\b\s*"',
  caseSensitive: false,
);

/// Maps this project's own named constraints to text that tells the user what
/// to actually type.
///
/// Consulted before both the generic code branches and the [_schemaLeakPattern]
/// suppression below, which would otherwise collapse a fixable typo ("section
/// must be 1-4 characters") into "Something went wrong". Only the constraint
/// *name* is matched — the database's own message is never shown, so this adds
/// no disclosure surface. Mirrors the CHECK constraints in
/// sec_input_validation_and_normalisation and the client-side rules in
/// AppValidators.
const _constraintHelp = <String, String>{
  'profiles_teacher_initial_unique':
      'That initial is already taken by another teacher — try a longer one (e.g. "MR" → "MAR").',
  'profiles_teacher_initial_format':
      'Teacher initials must be 2-6 letters with no digits or spaces (e.g. AS, FNN).',
  'students_section_format': 'Section must be 1-4 letters or digits (e.g. A, B2).',
  'course_offerings_section_format': 'Section must be 1-4 letters or digits (e.g. A, B2).',
  'students_batch_label_format': 'Batch must be 1-10 letters, digits or "-" (e.g. 66).',
  'course_offerings_batch_format': 'Batch must be 1-10 letters, digits or "-" (e.g. 66).',
  'courses_code_format':
      'Course code must be 2-20 letters, digits, spaces or "-" (e.g. CSE 412).',
  // Hit by "Reconsider" on a declined join request. The index is partial on
  // `status <> 'rejected'`, so a student whose request was declined is free to
  // apply again — and once they have, putting the OLD row back to pending
  // collides with the new one. The generic 23505 text ("That already exists")
  // is useless here; what the teacher needs to know is that there is already a
  // live request from this student that they can simply accept.
  'enrollments_active_request_uniq':
      'This student has already sent a fresh request for that course — accept that one instead, it is in the Waiting tab.',
};

String? _constraintMessage(String message) {
  for (final e in _constraintHelp.entries) {
    if (message.contains(e.key)) return e.value;
  }
  return null;
}

/// Turns a caught error into a message a non-technical user can act on,
/// instead of the raw exception dump (e.g. `PostgrestException(message:
/// duplicate key value violates unique constraint "clubs_name_key", code:
/// 23505, ...)`) that every screen used to shove straight into a SnackBar.
String friendlyError(Object err) {
  if (err is AuthException) return err.message;

  if (err is PostgrestException) {
    // Named-constraint help first: these are this project's own constraints,
    // and both the generic branches below and the schema-leak suppression
    // would otherwise turn an actionable formatting mistake into a dead end.
    final help = _constraintMessage(err.message);
    if (help != null) return help;

    switch (err.code) {
      case '23505': return 'That already exists — try a different value.';
      case '23503': return 'This can\'t be completed because something it depends on is missing.';
      case '23514': return 'Some of that information isn\'t in a valid format — please check it and try again.';
      case '42501': return 'You don\'t have permission to do that.';
      case 'PGRST301': return 'Your session expired — please log in again.';
    }
    if (err.message.toLowerCase().contains('permission') ||
        err.message.toLowerCase().contains('policy')) {
      return 'You don\'t have permission to do that.';
    }
    // Unmapped PostgrestExceptions used to be returned verbatim, which made
    // this default branch — not the handful of screens that print `$e` — the
    // app's main schema-disclosure surface.
    //
    // Not everything here is unsafe though: this project's SECURITY DEFINER
    // RPCs deliberately RAISE human-written messages ("Only the offering's
    // teacher or an admin can approve this request"), and plpgsql reports
    // those as P0001. Those are worth showing; Postgres's own integrity and
    // access errors are not.
    if (_schemaLeakPattern.hasMatch(err.message)) {
      debugPrint('[friendlyError] suppressed schema detail: ${err.message}');
      return 'Something went wrong — please try again.';
    }
    if (err.code == 'P0001') return err.message;
    debugPrint('[friendlyError] unmapped Postgrest ${err.code}: ${err.message}');
    return 'Something went wrong — please try again.';
  }

  if (err is StorageException) return err.message;

  if (err is FunctionException) {
    final details = err.details;
    if (details is Map && details['error'] is String) return details['error'] as String;
    if (err.status == 401 || err.status == 403) return 'You don\'t have permission to do that.';
    return 'Something went wrong on the server — please try again.';
  }

  final msg = err.toString();
  if (msg.contains('SocketException') || msg.contains('Failed host lookup') ||
      msg.contains('TimeoutException') || msg.contains('ClientException') ||
      msg.contains('Connection closed') || msg.contains('Network is unreachable')) {
    return 'Couldn\'t connect — check your internet connection and try again.';
  }

  final cleaned = msg.replaceAll('Exception: ', '');
  // A raw class-dump like "SomeException(field: value, ...)" isn't useful to
  // a non-technical user even after stripping "Exception: " — fall back to
  // a generic message rather than showing that shape verbatim.
  if (RegExp(r'^[A-Za-z_]+\(.*\)$').hasMatch(cleaned)) {
    return 'Something went wrong — please try again.';
  }
  return cleaned;
}

/// Distinguishes "the network dropped" from a genuine app-level error
/// (validation, RLS, a real constraint violation) -- used by OutboxService
/// to decide whether a failed submit should be queued for retry (connectivity)
/// or surfaced to the user immediately (it would fail identically on retry).
bool isConnectivityError(Object err) {
  if (err is PostgrestException) return false;
  if (err is AuthException) return false;
  final msg = err.toString();
  return msg.contains('SocketException') || msg.contains('Failed host lookup') ||
      msg.contains('TimeoutException') || msg.contains('ClientException') ||
      msg.contains('Connection closed') || msg.contains('Network is unreachable');
}
