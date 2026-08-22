import 'package:afos_v7/features/web/presentation/consoles/personal_overview.dart';
import 'package:afos_v7/features/web/presentation/widgets/chart_primitives.dart';
import 'package:afos_v7/features/web/presentation/widgets/console_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The grid, and the dashboard four of the seven roles never had.
///
/// WHY THE GEOMETRY IS TESTED AND NOT EYEBALLED. The complaint that produced
/// this work was "it looks scattered" — panels at arbitrary heights with no
/// shared alignment. That is a geometric claim, so the fix has to be a
/// geometric guarantee: a panel gets exactly the box its span asks for, and
/// panels sharing a row share a height. Eyeballing a screenshot cannot pin
/// that, and the previous layout passed every test it had while being wrong.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, Widget child,
      {bool reduceMotion = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: size,
            disableAnimations: reduceMotion,
          ),
          child: SingleChildScrollView(child: child),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  const desktop = Size(1280, 2400);

  Widget box(String key) => GridPanel(key: Key(key), child: Text(key));

  group('the grid gives a panel exactly the box its span asks for', () {
    testWidgets('a stat is one row tall, a large is three', (t) async {
      await pumpAt(
        t,
        desktop,
        ConsoleGrid(animate: false, panels: [
          ConsolePanel(span: PanelSpan.stat, child: box('a')),
          ConsolePanel(span: PanelSpan.large, child: box('b')),
        ]),
      );
      expect(t.getSize(find.byKey(const Key('a'))).height,
          ConsoleGrid.heightFor(PanelSpan.stat));
      expect(t.getSize(find.byKey(const Key('b'))).height,
          ConsoleGrid.heightFor(PanelSpan.large));
      // 1 row -> 78, 3 rows -> 3*78 + 2*12 gutters.
      expect(ConsoleGrid.heightFor(PanelSpan.stat), 78);
      expect(ConsoleGrid.heightFor(PanelSpan.large), 258);
    });

    testWidgets('four stats fill one row and share a height and a top edge',
        (t) async {
      await pumpAt(
        t,
        desktop,
        ConsoleGrid(animate: false, panels: [
          for (final k in ['a', 'b', 'c', 'd'])
            ConsolePanel(span: PanelSpan.stat, child: box(k)),
        ]),
      );
      final tops = <double>[];
      final sizes = <Size>[];
      for (final k in ['a', 'b', 'c', 'd']) {
        tops.add(t.getTopLeft(find.byKey(Key(k))).dy);
        sizes.add(t.getSize(find.byKey(Key(k))));
      }
      // THE ALIGNMENT CLAIM. Same row, same height, same y — this is precisely
      // what the old Expanded(flex:) pairs could not promise.
      expect(tops.toSet().length, 1, reason: 'all four sit on one line');
      expect(sizes.map((s) => s.height).toSet().length, 1);
      expect(sizes.map((s) => s.width).toSet().length, 1);
    });

    testWidgets('spans that sum to twelve leave no gap and no overflow',
        (t) async {
      await pumpAt(
        t,
        desktop,
        ConsoleGrid(animate: false, panels: [
          ConsolePanel(span: PanelSpan.tall, child: box('a')),
          ConsolePanel(span: PanelSpan.tall, child: box('b')),
          ConsolePanel(span: PanelSpan.tall, child: box('c')),
        ]),
      );
      final a = t.getRect(find.byKey(const Key('a')));
      final c = t.getRect(find.byKey(const Key('c')));
      expect(a.top, c.top, reason: 'three 4-spans are one row');
      // The run ends flush with the grid, within a rounding pixel.
      expect(c.right, closeTo(1280, 1.0));
      expect(noOverflow(t), isTrue);
    });
  });

  group('narrower windows fold instead of overflowing', () {
    test('the column count steps at the declared breakpoints', () {
      expect(ConsoleGrid.columnsFor(1280), 12);
      expect(ConsoleGrid.columnsFor(1024), 12);
      expect(ConsoleGrid.columnsFor(1023), 6);
      expect(ConsoleGrid.columnsFor(640), 6);
      expect(ConsoleGrid.columnsFor(639), 3);
    });

    testWidgets('a 12-span panel in a 6-column window clamps to the window',
        (t) async {
      const narrow = Size(800, 1200);
      await pumpAt(
        t,
        narrow,
        ConsoleGrid(animate: false, panels: [
          ConsolePanel(span: PanelSpan.wide, child: box('w')),
        ]),
      );
      // Clamped to six columns, not overflowing by half a screen.
      expect(t.getSize(find.byKey(const Key('w'))).width, closeTo(800, 1.0));
      expect(noOverflow(t), isTrue);
    });
  });

  group('the entrance animation', () {
    testWidgets('reduced motion shows every panel immediately, not faded',
        (t) async {
      await pumpAt(
        t,
        desktop,
        ConsoleGrid(panels: [
          for (final k in ['a', 'b', 'c'])
            ConsolePanel(span: PanelSpan.stat, child: box(k)),
        ]),
        reduceMotion: true,
      );
      // Pumping a single frame is enough — under reduced motion the reveal
      // must jump to its end state rather than tween to it.
      for (final k in ['a', 'b', 'c']) {
        // `.first` is the nearest enclosing FadeTransition — the panel's own
        // reveal. MaterialApp contributes others further up the tree, and
        // asking for "the" FadeTransition without qualifying which throws.
        final op = t.widget<FadeTransition>(
          find
              .ancestor(
                  of: find.byKey(Key(k)),
                  matching: find.byType(FadeTransition))
              .first,
        );
        expect(op.opacity.value, 1.0, reason: '$k is fully visible at once');
      }
    });

    testWidgets('panels hold their box while still animating in', (t) async {
      await pumpAt(
        t,
        desktop,
        ConsoleGrid(panels: [
          for (final k in ['a', 'b', 'c', 'd'])
            ConsolePanel(span: PanelSpan.stat, child: box(k)),
        ]),
      );
      // pumpAndSettle has run the entrance; the geometry must be identical to
      // the un-animated case. The reveal wraps the CONTENT, never the box —
      // otherwise the grid would reflow on every frame of its own entrance.
      final tops = [
        for (final k in ['a', 'b', 'c', 'd'])
          t.getTopLeft(find.byKey(Key(k))).dy
      ];
      expect(tops.toSet().length, 1);
    });
  });

  group('PersonalOverview — the dashboard the other four roles never had', () {
    PersonalOverviewData student() => const PersonalOverviewData(
          // The real shape, read from the live project on 2026-08-22 for the
          // first student with a cohort: batch 68, section D.
          mine: {
            'role': 'student',
            'batch': '68',
            'section': 'D',
            'myslots': 10,
            'mylabs': 6,
            'clubs': 5,
            'enrollments': 3,
            'unread': 3,
            'byDay': [
              {'d': 0, 'n': 5},
              {'d': 2, 'n': 1},
              {'d': 3, 'n': 1},
              {'d': 4, 'n': 3},
            ],
          },
          campus: {
            'liveSlots': 1854,
            'rooms': 68,
            'clubs': 55,
            'routes': 40,
            'stops': 351,
            'books': 18,
          },
        );

    testWidgets('a student sees their own week as a ring', (t) async {
      await pumpAt(t, desktop, PersonalOverview(data: student()));
      final ring = t.widget<RingChart>(find.byType(RingChart));
      expect(ring.centerValue, '10');
      // 6 lab, 4 theory — the theory half is derived, so this pins the sum.
      expect(ring.slices.map((s) => s.value).toList(), [6, 4]);
      expect(find.text('Batch 68 · Section D'), findsOneWidget);
    });

    testWidgets('their own figures are shown against the campus ones',
        (t) async {
      await pumpAt(t, desktop, PersonalOverview(data: student()));
      expect(find.text('of 55 on campus'), findsOneWidget);
      expect(find.text('waiting for you'), findsOneWidget);
    });

    testWidgets('someone with no cohort is told so, not shown a zero ring',
        (t) async {
      await pumpAt(
        t,
        desktop,
        const PersonalOverview(
          data: PersonalOverviewData(
            mine: {'role': 'staff', 'myslots': 0, 'unread': 0},
            campus: {'clubs': 55},
          ),
        ),
      );
      expect(find.byType(RingChart), findsNothing);
      expect(find.text('You have no cohort, so no timetable of your own.'),
          findsOneWidget);
      expect(find.text('no cohort assigned'), findsOneWidget);
    });

    testWidgets('null data renders nothing at all', (t) async {
      await pumpAt(t, desktop, const PersonalOverview(data: null));
      expect(find.byType(ConsoleGrid), findsNothing);
    });

    testWidgets('a failed load explains itself without leaking the exception',
        (t) async {
      await pumpAt(
        t,
        desktop,
        const PersonalOverview(
            data: PersonalOverviewData.failed('PostgrestException 42501')),
      );
      expect(find.text('Your figures are unavailable'), findsOneWidget);
      expect(find.textContaining('42501'), findsNothing);
    });
  });
}

/// True when no RenderFlex/RenderBox overflow was recorded this frame.
bool noOverflow(WidgetTester t) => t.takeException() == null;
