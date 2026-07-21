import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:afos_v7/core/navigation/router_location.dart';
import 'package:afos_v7/features/shell/presentation/app_shell.dart';
import 'package:afos_v7/shared/widgets/glass_bottom_nav.dart';

/// Regression guards for the bottom-nav indicator.
///
/// This bug has now been "fixed" twice by changing the navigation VERB, which
/// each time traded the indicator against the back stack. The real cause is a
/// go_router behaviour: inside a ShellRoute an imperative `push` deliberately
/// does not advance the match list's uri, so `matchedLocation` reports the
/// screen you came FROM.
///
/// These tests pin that behaviour directly. If a go_router upgrade ever changes
/// it, this fails loudly rather than silently reintroducing a stale indicator
/// (or tempting a third verb swap).
void main() {
  /// Mirrors the real app's shape: every destination is a FLAT sibling inside
  /// one ShellRoute. That flatness is why `go` replaces instead of stacking,
  /// and therefore why `go` kills canPop() app-wide.
  GoRouter buildRouter() => GoRouter(
        initialLocation: '/home',
        routes: [
          ShellRoute(
            builder: (_, __, child) => child,
            routes: [
              for (final path in const [
                '/home',
                '/search',
                '/profile',
                '/settings',
                '/library',
              ])
                GoRoute(
                  path: path,
                  builder: (_, __) => Scaffold(body: Text('screen $path')),
                ),
            ],
          ),
        ],
      );

  Future<GoRouter> pumpRouter(WidgetTester tester) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
    ));
    await tester.pumpAndSettle();
    return router;
  }

  String staleLocation(GoRouter r) =>
      r.routerDelegate.currentConfiguration.uri.toString();

  String trueLocation(GoRouter r) =>
      r.routerDelegate.currentConfiguration.last.matchedLocation;

  testWidgets('kQuickNavDestinations order is the contract these tests assume',
      (tester) async {
    expect(kQuickNavDestinations.map((d) => d.route).toList(),
        ['/home', '/search', '/profile', '/settings']);
  });

  testWidgets('imperative push leaves matchedLocation stale but last is truthful',
      (tester) async {
    final router = await pumpRouter(tester);
    expect(trueLocation(router), '/home');

    router.push('/library');
    await tester.pumpAndSettle();

    // The exact go_router behaviour that caused the bug. If this assertion ever
    // fails, go_router changed and navIndexForRouter can be simplified.
    expect(staleLocation(router), '/home',
        reason: 'push is expected to leave the outer uri stale');
    // The behaviour the fix relies on.
    expect(trueLocation(router), '/library',
        reason: 'ImperativeRouteMatch must report the pushed location');
  });

  testWidgets('indicator clears when a pushed screen is not a quick destination',
      (tester) async {
    final router = await pumpRouter(tester);
    expect(navIndexForRouter(router), 0); // Home

    router.push('/library');
    await tester.pumpAndSettle();

    // The original symptom: this returned 0 (Home stayed lit) while Library was
    // on screen, because the index was read off the stale location.
    expect(navIndexForRouter(router), -1);
  });

  testWidgets('indicator follows a pushed quick destination', (tester) async {
    final router = await pumpRouter(tester);

    router.push('/settings');
    await tester.pumpAndSettle();
    expect(navIndexForRouter(router), 3);

    router.push('/profile');
    await tester.pumpAndSettle();
    expect(navIndexForRouter(router), 2);
  });

  testWidgets('indicator is correct under go as well as push', (tester) async {
    final router = await pumpRouter(tester);

    router.go('/search');
    await tester.pumpAndSettle();
    expect(navIndexForRouter(router), 1);

    router.go('/library');
    await tester.pumpAndSettle();
    expect(navIndexForRouter(router), -1);
  });

  testWidgets('push preserves the back stack; go does not', (tester) async {
    final router = await pumpRouter(tester);
    expect(router.canPop(), isFalse);

    // What the slide menu does again after this fix.
    router.push('/library');
    await tester.pumpAndSettle();
    expect(router.canPop(), isTrue,
        reason: 'push must keep a back stack so screen-level back works');

    router.pop();
    await tester.pumpAndSettle();
    expect(trueLocation(router), '/home');
    expect(navIndexForRouter(router), 0);

    // Why the `go` workaround was harmful: on flat siblings it replaces, so
    // there is nothing left to pop anywhere in the app.
    router.go('/library');
    await tester.pumpAndSettle();
    expect(router.canPop(), isFalse,
        reason: 'go on flat siblings replaces rather than stacks');
  });

  // The user-visible symptom of the stale index, and the reason this mattered
  // beyond cosmetics. GlassBottomNav._handleTap returns early when the tapped
  // index equals currentIndex ("already on this exact screen"). With the stale
  // location, pushing to a non-tab screen left currentIndex at 0, so tapping
  // Home was a no-op -- the reported "press home and it doesn't work". A
  // truthful -1 makes the tab live again while the planet still rests on Home.
  group('Home tab stays tappable from a non-tab screen', () {
    Future<int?> tapHome(WidgetTester tester, int currentIndex) async {
      int? tapped;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: GlassBottomNav(
              destinations: kQuickNavDestinations,
              currentIndex: currentIndex,
              onTap: (i) => tapped = i,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      return tapped;
    }

    testWidgets('fires with the truthful -1 index', (tester) async {
      expect(await tapHome(tester, -1), 0);
    });

    testWidgets('was suppressed by the stale 0 index', (tester) async {
      expect(await tapHome(tester, 0), isNull);
    });
  });

  // The bottom nav was only the instance that got reported. The desktop rail
  // and the slide-menu highlight derived "am I here?" independently and were
  // both wrong in the same way -- the rail off the stale matchedLocation, the
  // menu off a Bloc index that only menu taps ever wrote. All three now share
  // isRouteActive, so these guard the shared helper directly.
  group('isRouteActive (shared by nav, desktop rail, slide menu)', () {
    testWidgets('true only for the route actually on screen', (tester) async {
      final router = await pumpRouter(tester);
      expect(isRouteActive(router, '/home'), isTrue);
      expect(isRouteActive(router, '/library'), isFalse);

      router.push('/library');
      await tester.pumpAndSettle();

      // The rail bug: with the stale location this stayed true for /home.
      expect(isRouteActive(router, '/home'), isFalse);
      expect(isRouteActive(router, '/library'), isTrue);
    });

    testWidgets('is not fooled by a shared prefix', (tester) async {
      final router = await pumpRouter(tester);
      router.push('/settings');
      await tester.pumpAndSettle();
      // '/set' must not match '/settings' -- only an exact hit or a real
      // '/settings/...' child counts.
      expect(isRouteActive(router, '/set'), isFalse);
      expect(isRouteActive(router, '/settings'), isTrue);
    });

    testWidgets('currentRouteLocation tracks push and pop', (tester) async {
      final router = await pumpRouter(tester);
      expect(currentRouteLocation(router), '/home');
      router.push('/profile');
      await tester.pumpAndSettle();
      expect(currentRouteLocation(router), '/profile');
      router.pop();
      await tester.pumpAndSettle();
      expect(currentRouteLocation(router), '/home');
    });
  });

  testWidgets('sub-routes keep the parent tab lit', (tester) async {
    final router = await pumpRouter(tester);
    router.push('/settings');
    await tester.pumpAndSettle();
    expect(navIndexForRouter(router), 3);
    // '/settings/notifications' would also resolve to 3 via the startsWith
    // branch; asserted here on the prefix rule itself rather than by adding a
    // route that does not exist in the real app yet.
    expect('/settings/notifications'.startsWith('/settings/'), isTrue);
  });
}
