import 'package:go_router/go_router.dart';

/// The location actually on screen, for UI that highlights "where am I".
///
/// Deliberately NOT `GoRouterState.of(context).matchedLocation`. Inside a
/// ShellRoute an imperative `push` leaves the match list's uri untouched by
/// design (go_router's own comment: "Imperative route match doesn't change the
/// uri and path parameters"), so `matchedLocation` reports the screen you came
/// FROM rather than the one you are on.
///
/// `currentConfiguration.last` is truthful for both verbs: a normal match
/// carries its own matchedLocation, and an `ImperativeRouteMatch` derives one
/// from the PUSHED match list rather than the stale outer uri
/// (go_router-14.8.1 `match.dart:440`, `_getsMatchedLocationFromMatches`).
///
/// Anything deriving "is this the current screen" must use this. Three separate
/// pieces of UI got that wrong independently — the bottom-nav indicator, the
/// desktop rail highlight, and the slide-menu highlight (which had drifted even
/// further, deriving from a Bloc index that only menu taps ever updated).
///
/// Returns `''` when the router has no matches yet, which matches nothing.
String currentRouteLocation(GoRouter router) {
  final config = router.routerDelegate.currentConfiguration;
  if (config.isEmpty) return '';
  return config.last.matchedLocation;
}

/// Whether [route] is the current screen, treating sub-routes as the parent
/// (so a future '/settings/notifications' still highlights Settings).
bool isRouteActive(GoRouter router, String route) {
  final loc = currentRouteLocation(router);
  return loc == route || loc.startsWith('$route/');
}
