import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;

/// Builds a realtime channel topic that is unique per widget INSTANCE.
///
/// supabase-dart dedupes channels by topic name. Inside this app's ShellRoute,
/// go_router keeps pushed-under screens' State alive rather than disposing it,
/// so the same screen is routinely mounted more than once (open Manage Users,
/// navigate away via the menu, open it again). With a fixed topic like
/// `'manage_users'`, both instances resolve to the SAME channel — and then the
/// first one to `dispose()` calls `unsubscribe()` and tears that channel down
/// out from under the instance still on screen.
///
/// The surviving screen then silently stops receiving postgres_changes. Nothing
/// errors; the list just quietly stops updating, so an approve/reject looks like
/// it "didn't take" until you leave the screen and come back (which remounts and
/// re-runs the initial load). That is the reported
/// "approval not reflected in time / takes ages to refresh".
///
/// `top_app_bar.dart` already worked around this locally with
/// `identityHashCode(this)`; this hoists that fix so every screen gets it.
///
/// Pass `this` from the State. Do NOT use this for genuinely app-wide singleton
/// subscriptions (AppConfigService, BadgeService) — those intentionally want one
/// shared channel for the whole app.
String screenChannel(String base, Object instance) =>
    '${base}_${identityHashCode(instance)}';

/// Coalesces a burst of realtime events into a single refetch.
///
/// The admin screens subscribe with `PostgresChangeEvent.all` and answer every
/// event by reloading the WHOLE table. `profiles` in particular changes on every
/// login and every profile edit anywhere in the app, so one admin sitting on
/// Manage Users re-downloads all profiles (15 columns) for each of those events.
/// Anything that touches several rows — approving a handful of signups, a bulk
/// migration — multiplies that: N row changes became N full-table fetches, each
/// one a round trip on a phone connection.
///
/// A short debounce collapses each burst into one fetch. It deliberately fires
/// on the TRAILING edge: the last event in a burst is the one whose state we
/// want, and waiting ~300ms costs nothing perceptible against a network fetch
/// that already takes longer than that.
///
/// Not a substitute for the immediate local update an action does on its own
/// screen (see `manage_users_screen._approve`) — that is what makes your own
/// action feel instant; this only governs reacting to *other people's* changes.
class RealtimeRefresh {
  final Duration delay;
  Timer? _timer;

  RealtimeRefresh({this.delay = const Duration(milliseconds: 300)});

  /// Schedule [action], cancelling any refetch still pending from this burst.
  void schedule(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  /// Must be called from the State's dispose, or a queued refetch can fire
  /// against an unmounted widget.
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
