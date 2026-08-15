import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:afos_v7/core/navigation/nav_destinations.dart';
import 'package:afos_v7/features/shell/presentation/command_palette.dart';

/// Phase 6, the keyboard half — driven rather than described.
///
/// The palette is web-only, and there is no browser on this machine to press
/// Ctrl+K in. That is not a reason to ship it unverified: a widget test that
/// actually sends the key events is stronger evidence than one person clicking
/// once, because it runs again on every change.
void main() {
  const destinations = [
    NavDestination('Dashboard', Icons.home, '/home', Colors.blue),
    NavDestination('Class Schedule', Icons.schedule, '/schedule', Colors.blue),
    NavDestination('Transport', Icons.directions_bus, '/transport', Colors.teal),
    NavDestination('Manage Users', Icons.people, '/admin/users', Colors.purple),
  ];

  /// Where the router ended up, so navigation can be asserted rather than
  /// assumed.
  late String location;

  Widget harness() {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        for (final path in ['/home', '/schedule', '/transport', '/admin/users', '/search'])
          GoRoute(
            path: path,
            builder: (_, __) {
              location = path;
              return Scaffold(body: Text('at $path'));
            },
          ),
      ],
    );
    return MaterialApp.router(routerConfig: router);
  }

  setUp(() {
    location = '/home';
    navDestinations.value = destinations;
  });

  tearDown(() => navDestinations.value = const []);

  Future<void> openPalette(WidgetTester tester) async {
    final ctx = tester.element(find.text('at /home'));
    CommandPalette.show(ctx);
    await tester.pumpAndSettle();
  }

  testWidgets('opens showing every destination the user can reach',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await openPalette(tester);

    for (final d in destinations) {
      expect(find.text(d.label), findsOneWidget);
    }
    expect(find.text('4 destinations'), findsOneWidget);
  });

  testWidgets('typing filters, and the count follows', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await openPalette(tester);

    await tester.enterText(find.byType(TextField), 'trans');
    await tester.pumpAndSettle();

    expect(find.text('Transport'), findsOneWidget);
    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('1 destination'), findsOneWidget,
        reason: 'the count must be singular for one result — the kind of '
            'detail that makes a tool feel finished');
  });

  testWidgets('Enter opens the highlighted destination', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await openPalette(tester);

    await tester.enterText(find.byType(TextField), 'transport');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(location, '/transport');
    expect(find.byType(CommandPalette), findsNothing,
        reason: 'the palette must close itself on navigating');
  });

  testWidgets('arrow keys move the selection, and Enter takes that one',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await openPalette(tester);

    // Down twice from the first row = the third destination.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(location, '/transport', reason: 'third in the unfiltered list');
  });

  testWidgets('the selection wraps at the end of the list', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await openPalette(tester);

    // Up from the first row should land on the LAST, not sit still. A dead
    // end at the top of a list is immediately noticeable to a keyboard user.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(location, '/admin/users', reason: 'last destination');
  });

  testWidgets('Escape closes without navigating', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await openPalette(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(CommandPalette), findsNothing);
    expect(location, '/home', reason: 'Escape must not move the user');
  });

  testWidgets('no match hands the query to /search rather than dead-ending',
      (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await openPalette(tester);

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No destination matches'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(location, '/search',
        reason: 'a palette that can only say "nothing found" wastes what the '
            'user already typed');
  });

  testWidgets('with permissions unresolved it offers nothing at all',
      (tester) async {
    // Fails CLOSED. The list is derived from the role matrix, so the wrong
    // direction to fail is "show everything" — that would advertise admin
    // destinations to a student for the moment before their role loads.
    navDestinations.value = const [];
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    await openPalette(tester);

    expect(find.textContaining('No destination matches'), findsOneWidget);
    expect(find.text('Manage Users'), findsNothing);
  });
}
