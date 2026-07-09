import 'package:flutter/widgets.dart';

/// Tracks consecutive back-button presses within the authenticated shell so
/// AppShell can cap "back" at 3 real pops before snapping to Dashboard,
/// rather than letting the single shared shell Navigator's stack (which
/// grows unbounded since every in-app navigation action `push`es) be walked
/// back through indefinitely. Any genuine forward push (opening a new
/// screen) resets the count -- the cap is meant for "wandered too deep by
/// back-pressing," not a running lifetime total across the whole session.
class BackPressTracker extends NavigatorObserver {
  BackPressTracker._();
  static final instance = BackPressTracker._();

  int consecutiveBackPresses = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    consecutiveBackPresses = 0;
  }
}
