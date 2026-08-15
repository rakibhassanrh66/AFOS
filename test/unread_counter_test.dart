import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/core/services/unread_counter.dart';

/// The badge that used to wait for the network.
///
/// The bell kept its own `_unread` and changed it in exactly one place — a
/// `.count()` query — so tapping a notification left the number sitting there
/// for a full round trip while the list beside it had already updated. These
/// pin the arithmetic that replaced it.
void main() {
  setUp(UnreadCounter.clear);

  test('an optimistic decrement lands immediately', () {
    UnreadCounter.set(3);
    UnreadCounter.decrement();
    expect(UnreadCounter.value.value, 2);
  });

  test('it never goes below zero', () {
    // The real sequence this protects against: "mark all read" clears the
    // count, then a per-row decrement from a tap that was already in flight
    // arrives. Going negative would hide a genuinely unread item later.
    UnreadCounter.set(1);
    UnreadCounter.clear();
    UnreadCounter.decrement();
    UnreadCounter.decrement();
    expect(UnreadCounter.value.value, 0);
  });

  test('an authoritative count overrides an optimistic guess', () {
    UnreadCounter.set(5);
    UnreadCounter.decrement();
    expect(UnreadCounter.value.value, 4);
    // The real query comes back — another device marked two more read.
    UnreadCounter.set(2);
    expect(UnreadCounter.value.value, 2);
  });

  test('a negative count from the server is clamped, not trusted', () {
    UnreadCounter.set(-7);
    expect(UnreadCounter.value.value, 0);
  });

  test('listeners are notified, because the badge rebuilds from this', () {
    var fired = 0;
    void listener() => fired++;
    UnreadCounter.value.addListener(listener);
    addTearDown(() => UnreadCounter.value.removeListener(listener));

    UnreadCounter.set(4);
    UnreadCounter.decrement();
    UnreadCounter.clear();
    expect(fired, 3);
  });

  test('clearing when already zero does not churn listeners', () {
    UnreadCounter.set(0);
    var fired = 0;
    void listener() => fired++;
    UnreadCounter.value.addListener(listener);
    addTearDown(() => UnreadCounter.value.removeListener(listener));

    UnreadCounter.clear();
    // ValueNotifier suppresses a notification when the value is unchanged, so
    // the app bar does not rebuild on every realtime event that changes
    // nothing — worth pinning, since the bell sits on essentially every screen.
    expect(fired, 0);
  });
}
