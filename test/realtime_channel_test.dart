import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/core/services/realtime_channel.dart';

/// supabase-dart dedupes realtime channels by topic name, and this app's
/// ShellRoute keeps pushed-under screens alive, so the same admin screen can be
/// mounted twice. With a fixed topic both instances share one channel and the
/// first dispose() unsubscribes it out from under the other -- the surviving
/// screen then silently stops refreshing.
void main() {
  test('distinct instances get distinct topics', () {
    final a = Object();
    final b = Object();
    expect(screenChannel('manage_users', a),
        isNot(equals(screenChannel('manage_users', b))));
  });

  test('same instance is stable across calls', () {
    final a = Object();
    expect(screenChannel('manage_users', a), screenChannel('manage_users', a));
  });

  test('different bases on one instance stay distinct', () {
    // manage_users_screen subscribes to two tables from a single State.
    final state = Object();
    expect(screenChannel('manage_users', state),
        isNot(equals(screenChannel('manage_cr_requests', state))));
  });

  test('topic keeps its base as a readable prefix', () {
    expect(screenChannel('manage_hall_applications', Object()),
        startsWith('manage_hall_applications_'));
  });
}
