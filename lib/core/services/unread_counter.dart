import 'package:flutter/foundation.dart';

/// The unread-notification count, shared by everything that displays it.
///
/// THE PROBLEM. The bell in the app bar kept its own `_unread`, and changed it
/// in exactly one place: a `.count()` query. So tapping a notification marked
/// it read on the server, and the number sat there until a realtime event
/// arrived and a fresh count came back — a full round trip on campus wifi,
/// during which the app looked like it had ignored the tap. The popover
/// *already* updated its own list instantly; the bell six pixels away did not,
/// which is what made it feel slow rather than merely late.
///
/// So the count lives in one place and every surface reads it. Whoever learns
/// something first publishes it: the popover knows a notification was read the
/// moment it is tapped, long before any query could confirm it.
///
/// OPTIMISTIC, NOT SPECULATIVE. [decrement] is applied because the write that
/// follows it is one the server has no reason to refuse — marking your own
/// notification read. If it does fail, the next [set] from a real count
/// corrects it. The alternative, waiting to be sure, is the thing that felt
/// broken.
class UnreadCounter {
  UnreadCounter._();

  /// Never negative: a stale decrement arriving after a `mark all read` must
  /// not push the badge below zero and hide a genuinely unread item later.
  static final ValueNotifier<int> value = ValueNotifier<int>(0);

  /// Authoritative — from a real query. Always wins over an optimistic guess.
  static void set(int count) => value.value = count < 0 ? 0 : count;

  /// One notification was just read. Applied immediately, reconciled later.
  static void decrement([int by = 1]) {
    final next = value.value - by;
    value.value = next < 0 ? 0 : next;
  }

  /// Everything was marked read.
  static void clear() => value.value = 0;
}
