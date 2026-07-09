import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns a caught error into a message a non-technical user can act on,
/// instead of the raw exception dump (e.g. `PostgrestException(message:
/// duplicate key value violates unique constraint "clubs_name_key", code:
/// 23505, ...)`) that every screen used to shove straight into a SnackBar.
String friendlyError(Object err) {
  if (err is AuthException) return err.message;

  if (err is PostgrestException) {
    switch (err.code) {
      case '23505': return 'That already exists — try a different value.';
      case '23503': return 'This can\'t be completed because something it depends on is missing.';
      case '42501': return 'You don\'t have permission to do that.';
      case 'PGRST301': return 'Your session expired — please log in again.';
    }
    if (err.message.toLowerCase().contains('permission') ||
        err.message.toLowerCase().contains('policy')) {
      return 'You don\'t have permission to do that.';
    }
    return err.message;
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
