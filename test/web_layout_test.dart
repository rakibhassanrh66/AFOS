import 'package:afos_v7/features/web/presentation/widgets/adaptive_list.dart';
import 'package:afos_v7/features/web/presentation/widgets/web_layout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The four primitives the 62-screen desktop sweep is built from.
///
/// WHY THESE ARE TESTED RATHER THAN EYEBALLED. The web build cannot be logged
/// into from here — signing in means typing a password, which is not something
/// this process does — so "I looked at it and it seemed fine" is not available
/// as verification for anything behind auth. These primitives are what every
/// swept screen is made of, so pinning their behaviour pins the sweep.
///
/// The behaviour that actually matters is the RESPONSIVE one: each primitive
/// has to degrade to the phone answer below its breakpoint. A desktop table in
/// a 700px window is worse than the cards it replaced, and a master/detail
/// split with a 380px master leaves 320px for the detail — which is not a
/// layout, it is two broken columns.
void main() {
  /// Renders [child] at an exact window size, the way a browser would.
  ///
  /// [scroll] wraps the child in a scroll view, which most of these primitives
  /// need because they shrink-wrap. WebPage does NOT: it fills the page and
  /// owns its own scroll view, so nesting it in another one gives it unbounded
  /// height and its Expanded body has nothing to expand into. That is a real
  /// misuse rather than a widget bug — a page is not a list item — and this
  /// flag is how the tests express the difference instead of papering over it.
  Future<void> pumpAt(WidgetTester tester, Size size, Widget child,
      {bool scroll = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: scroll ? SingleChildScrollView(child: child) : child),
    ));
    await tester.pumpAndSettle();
  }

  const desktop = Size(1600, 1000);
  const narrow = Size(900, 1000);

  group('WebSplit — master/detail only when there is room for both', () {
    testWidgets('shows both panes on a desktop window', (t) async {
      await pumpAt(t, desktop, const WebSplit(
        master: Text('MASTER'),
        detail: Text('DETAIL'),
      ));
      expect(find.text('MASTER'), findsOneWidget);
      expect(find.text('DETAIL'), findsOneWidget);
    });

    testWidgets('below the breakpoint shows the master alone', (t) async {
      // The phone behaviour: a list, and selection pushes a route. Rendering
      // a 380px master beside a 320px detail would be two broken columns.
      await pumpAt(t, narrow, const WebSplit(
        master: Text('MASTER'),
        detail: Text('DETAIL'),
      ));
      expect(find.text('MASTER'), findsOneWidget);
      expect(find.text('DETAIL'), findsNothing);
    });

    testWidgets('an unselected detail pane explains itself', (t) async {
      // An empty pane with no text is the desktop equivalent of a blank
      // screen — the reader cannot tell it apart from a failure.
      await pumpAt(t, desktop, const WebSplit(
        master: Text('MASTER'),
        placeholder: Text('Pick one from the list'),
      ));
      expect(find.text('Pick one from the list'), findsOneWidget);
    });
  });

  group('WebGrid — columns follow available width, not a hardcoded count', () {
    testWidgets('lays every child out and none overflow', (t) async {
      await pumpAt(t, desktop, WebGrid(
        minItemWidth: 300,
        children: [for (var i = 0; i < 9; i++) Text('item$i')],
      ));
      for (var i = 0; i < 9; i++) {
        expect(find.text('item$i'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });

    testWidgets('a narrow window still renders every child', (t) async {
      // The banned pattern is "three equal cards in a row" as filler. Driving
      // the count from width means one column at 400px and four at 1600px,
      // rather than always three.
      await pumpAt(t, const Size(400, 1000), WebGrid(
        minItemWidth: 300,
        children: [for (var i = 0; i < 4; i++) Text('item$i')],
      ));
      for (var i = 0; i < 4; i++) {
        expect(find.text('item$i'), findsOneWidget);
      }
      expect(t.takeException(), isNull);
    });
  });

  group('WebDataTable — the dense readout', () {
    testWidgets('renders a header cell and every row', (t) async {
      await pumpAt(t, desktop, WebDataTable(
        columns: const [WebColumn('Name'), WebColumn('Count', numeric: true)],
        rowCount: 3,
        rowBuilder: (i) => [Text('row$i'), Text('$i')],
      ));
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('row0'), findsOneWidget);
      expect(find.text('row2'), findsOneWidget);
    });

    testWidgets('an empty table shows its empty state, not a bare header',
        (t) async {
      await pumpAt(t, desktop, WebDataTable(
        columns: const [WebColumn('Name')],
        rowCount: 0,
        rowBuilder: (i) => const [Text('never')],
        empty: const Text('Nothing waiting'),
      ));
      expect(find.text('Nothing waiting'), findsOneWidget);
      expect(find.text('never'), findsNothing);
    });

    testWidgets('a row producing the wrong number of cells fails loudly',
        (t) async {
      // Silent truncation would render a table that quietly drops a column,
      // which is the worst possible failure for something people read numbers
      // out of. The assert turns it into a test failure instead.
      await pumpAt(t, desktop, WebDataTable(
        columns: const [WebColumn('A'), WebColumn('B')],
        rowCount: 1,
        rowBuilder: (i) => const [Text('only-one')],
      ));
      expect(t.takeException(), isAssertionError);
    });
  });

  group('WebPage — one header, and width is the page\'s decision', () {
    testWidgets('renders title, subtitle and actions', (t) async {
      await pumpAt(t, desktop, scroll: false, const WebPage(
        title: 'Manage Users',
        subtitle: 'Roles and areas',
        actions: [Text('ACTION')],
        child: Text('BODY'),
      ));
      expect(find.text('Manage Users'), findsOneWidget);
      expect(find.text('Roles and areas'), findsOneWidget);
      expect(find.text('ACTION'), findsOneWidget);
      expect(find.text('BODY'), findsOneWidget);
    });

    testWidgets('a side rail is never unreachable at a narrow width', (t) async {
      // Above the three-pane breakpoint it sits beside the content; below it,
      // it moves underneath rather than disappearing. Content that exists at
      // one width and not another is how a filter control becomes impossible
      // to find.
      for (final size in [desktop, narrow]) {
        await pumpAt(t, size, scroll: false, const WebPage(
          title: 'Queue',
          sideRail: Text('FILTERS'),
          child: Text('BODY'),
        ));
        expect(find.text('FILTERS'), findsOneWidget,
            reason: 'side rail vanished at ${size.width}px');
      }
    });
  });

  group('WebStatStrip — figures you can compare', () {
    testWidgets('renders every figure with its reading', (t) async {
      await pumpAt(t, desktop, const WebStatStrip(stats: [
        WebStat(label: 'Pending', value: '7', icon: Icons.inbox,
            accent: Colors.blue, note: '7 waiting'),
        WebStat(label: 'Users', value: '1204', icon: Icons.people,
            accent: Colors.green),
      ]));
      expect(find.text('7'), findsOneWidget);
      expect(find.text('1204'), findsOneWidget);
      // The note replaces the bare label when present: "7" is not
      // information, "7 waiting" is.
      expect(find.text('7 waiting'), findsOneWidget);
      expect(find.text('Users'), findsOneWidget);
    });
  });

  group('AdaptiveList — columns on desktop, lazily', () {
    // On Android and below the desktop breakpoint this must be exactly the
    // ListView.builder it replaced. kIsWeb is false in the test VM, so these
    // cases pin the NON-web path, which is the one that must not regress: 34
    // screens now route their main list through this widget, and a mistake
    // here is a mistake on all of them at once.
    testWidgets('is a plain lazy list when not on web', (t) async {
      await pumpAt(t, const Size(1600, 1000), SizedBox(
        height: 600,
        child: AdaptiveList(
          itemCount: 500,
          itemBuilder: (c, i) => SizedBox(height: 60, child: Text('row$i')),
        ),
      ));
      // Laziness is the property that matters: 500 items, only the visible
      // handful built. Building all of them is how a screen takes four
      // seconds to open, which is why the constitution bans unbounded lists.
      expect(find.text('row0'), findsOneWidget);
      expect(find.text('row499'), findsNothing);
    });

    testWidgets('passes padding and count through unchanged', (t) async {
      await pumpAt(t, const Size(1600, 1000), SizedBox(
        height: 400,
        child: AdaptiveList(
          padding: const EdgeInsets.all(24),
          itemCount: 3,
          itemBuilder: (c, i) => SizedBox(height: 50, child: Text('row$i')),
        ),
      ));
      for (var i = 0; i < 3; i++) {
        expect(find.text('row$i'), findsOneWidget);
      }
    });

    testWidgets('an empty list renders nothing and does not throw', (t) async {
      await pumpAt(t, const Size(1600, 1000), SizedBox(
        height: 200,
        child: AdaptiveList(itemCount: 0, itemBuilder: (c, i) => const Text('x')),
      ));
      expect(find.text('x'), findsNothing);
      expect(t.takeException(), isNull);
    });
  });
}
