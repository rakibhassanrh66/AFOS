import 'package:afos_v7/features/web/presentation/consoles/admin_overview.dart';
import 'package:afos_v7/features/web/presentation/widgets/chart_primitives.dart';
import 'package:afos_v7/features/web/presentation/widgets/console_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The desktop console's data half, which shipped with no tests at all.
///
/// WHY THESE AND NOT A SCREENSHOT. The console sits behind an admin login, and
/// signing in means typing a password, which this process does not do. So the
/// panels are pinned the same way the 62-screen sweep was: by rendering the
/// real widget at a real desktop size with the shapes the live database
/// actually returns, and asserting on what a reader would see.
///
/// The figures below are the REAL ones, read from the project on 2026-08-22:
/// 14 profiles across 4 role buckets, 38 exams, 5 active halls totalling 2800
/// beds, 3 approved hall applications, 0 pending, 0 stuck. Using the live
/// shape matters — a hall system that is 0.1% full is exactly the case where a
/// ring chart is easiest to get wrong.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));
    await tester.pumpAndSettle();
  }

  const desktop = Size(1600, 1000);

  AdminOverviewData data({
    Map<String, dynamic>? facets,
    List<Map<String, dynamic>> recent = const [],
    int stuck = 0,
    List<Map<String, dynamic>> exams = const [],
    int beds = 2800,
    int occupied = 3,
  }) =>
      AdminOverviewData(
        facets: facets ??
            const {
              'total': 14,
              'pending': 0,
              'roles': [
                {'value': 'student', 'count': 9},
                {'value': 'teacher', 'count': 3},
                {'value': 'staff', 'count': 1},
                {'value': 'super_admin', 'count': 1},
              ],
            },
        recent: recent,
        stuck: stuck,
        exams: exams,
        beds: beds,
        occupied: occupied,
      );

  Finder ring() => find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is RingPainter);

  group('who gets an overview at all', () {
    testWidgets('null data renders nothing — not an empty panel', (t) async {
      await pumpAt(t, desktop, const AdminOverview(data: null));
      expect(find.byType(WidgetsApp), findsOneWidget); // sanity: it did pump
      expect(find.textContaining('People in AFOS'), findsNothing);
      expect(ring(), findsNothing);
    });

    testWidgets('a failed fetch explains itself and shows no figures',
        (t) async {
      await pumpAt(
          t, desktop, const AdminOverview(data: AdminOverviewData.failed('boom')));
      expect(find.text('Overview unavailable'), findsOneWidget);
      // The raw exception must not reach the reader.
      expect(find.textContaining('boom'), findsNothing);
      expect(find.text('People in AFOS'), findsNothing);
      expect(ring(), findsNothing);
    });
  });

  group('the figures across the top', () {
    testWidgets('carry the count and a reading of it', (t) async {
      await pumpAt(t, desktop, AdminOverview(data: data()));
      expect(find.text('14'), findsOneWidget);
      // Zero pending is stated, not left as a bare 0 for the reader to judge.
      expect(find.text('nothing waiting'), findsOneWidget);
      expect(find.text('none stuck'), findsOneWidget);
    });

    testWidgets('a non-zero queue changes the words, not just the colour',
        (t) async {
      await pumpAt(t, desktop, AdminOverview(data: data(stuck: 2)));
      expect(find.text('verification did not settle'), findsOneWidget);
      expect(find.text('none stuck'), findsNothing);
    });
  });

  group('who is in AFOS — bars, deliberately not a donut', () {
    testWidgets('every bar states its share for a screen reader', (t) async {
      await pumpAt(t, desktop, AdminOverview(data: data()));
      // 9 of 14 is 64.28…%, which must round rather than truncate.
      expect(
        find.byWidgetPredicate((w) =>
            w is Semantics &&
            w.properties.label == 'Student: 9 of 14, 64 percent'),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) =>
            w is Semantics &&
            w.properties.label == 'Staff/Officer: 1 of 14, 7 percent'),
        findsOneWidget,
      );
    });

    testWidgets('bars are ordered biggest first, whatever order they arrive in',
        (t) async {
      await pumpAt(
        t,
        desktop,
        AdminOverview(
          data: data(facets: const {
            'total': 14,
            'pending': 0,
            'roles': [
              {'value': 'staff', 'count': 1},
              {'value': 'student', 'count': 9},
              {'value': 'teacher', 'count': 3},
            ],
          }),
        ),
      );
      final bars = t
          .widgetList<Semantics>(find.byWidgetPredicate((w) =>
              w is Semantics && (w.properties.label ?? '').contains(' of 14, ')))
          .map((w) => w.properties.label!)
          .toList();
      expect(bars.first, startsWith('Student:'));
      expect(bars.last, startsWith('Staff/Officer:'));
    });

    testWidgets('no accounts is a sentence, not an empty box', (t) async {
      await pumpAt(
        t,
        desktop,
        AdminOverview(
            data: data(facets: const {'total': 0, 'pending': 0, 'roles': []})),
      );
      expect(find.text('No accounts yet.'), findsOneWidget);
    });
  });

  group('hall occupancy — the ring', () {
    testWidgets('puts the total in the middle and the numbers in the legend',
        (t) async {
      await pumpAt(t, desktop, AdminOverview(data: data()));
      expect(ring(), findsOneWidget);
      // Grouped, or the eye has to count digits.
      expect(find.text('2,800'), findsOneWidget);
      expect(find.text('total beds'), findsOneWidget);
      // The legend carries the values because at 3/2800 the slice is invisible.
      // Scoped to the hall panel: a bare find.text('3') also matches the
      // teacher bar's count, which is a different 3 entirely.
      final hallPanel =
          find.ancestor(of: ring(), matching: find.byType(GridPanel)).first;
      expect(find.descendant(of: hallPanel, matching: find.text('Occupied ')),
          findsOneWidget);
      expect(
          find.descendant(of: hallPanel, matching: find.text('3')), findsOneWidget);
      expect(find.descendant(of: hallPanel, matching: find.text('2,797')),
          findsOneWidget);
    });

    testWidgets('the arc matches the occupancy it claims', (t) async {
      await pumpAt(t, desktop, AdminOverview(data: data()));
      final chart = t
          .widgetList<RingChart>(find.byType(RingChart))
          .firstWhere((c) => c.centerLabel == 'total beds');
      expect(chart.slices.map((s) => s.value).toList(), [3, 2797]);
    });

    testWidgets('no halls configured draws no ring at all', (t) async {
      await pumpAt(t, desktop, AdminOverview(data: data(beds: 0, occupied: 0)));
      expect(find.text('No halls are configured.'), findsOneWidget);
      expect(ring(), findsNothing);
      // A ring over zero beds would be a divide by zero or a drawn lie.
    });

    testWidgets('occupancy cannot report more available than exist', (t) async {
      // Defensive: approved applications outnumbering beds is a data error,
      // and must not render as a negative bed count.
      await pumpAt(t, desktop, AdminOverview(data: data(beds: 10, occupied: 25)));
      expect(find.text('0'), findsWidgets);
      expect(find.textContaining('-'), findsNothing);
    });
  });

  group('RingPainter repaint', () {
    RingPainter painter({
      double occupied = 3,
      Color track = const Color(0xFF111111),
      Color gap = const Color(0xFF000000),
    }) =>
        RingPainter(
          slices: [
            RingSlice(label: 'Occupied', value: occupied, color: const Color(0xFF1B78C2)),
            RingSlice(label: 'Available', value: 2797, color: const Color(0xFF10855A)),
          ],
          total: occupied + 2797,
          stroke: 16,
          track: track,
          gap: gap,
        );

    test('repaints when only the theme-dependent track colour changed', () {
      // THE REGRESSION. track is the one colour here that follows the theme,
      // and the first version of shouldRepaint compared everything EXCEPT it,
      // so a light/dark switch left the ring wearing the previous theme.
      expect(
        painter(track: const Color(0xFFEEEEEE)).shouldRepaint(painter()),
        isTrue,
      );
    });

    test('repaints when the surface behind the slice gaps changed', () {
      // Same class of bug: the 2px separators are painted in the SURFACE
      // colour, so they go stale across a theme switch too.
      expect(
        painter(gap: const Color(0xFFFFFFFF)).shouldRepaint(painter()),
        isTrue,
      );
    });

    test('repaints when the occupancy changed', () {
      expect(painter(occupied: 900).shouldRepaint(painter()), isTrue);
    });

    test('does not repaint when nothing changed', () {
      final p = painter();
      expect(p.shouldRepaint(painter()), isFalse);
    });
  });

  group('exam schedule', () {
    Map<String, dynamic> exam({
      String subject = 'Algorithms',
      String? date,
      bool retake = false,
      String batch = '63',
      String section = 'A',
      String room = '502',
    }) =>
        {
          'subject': subject,
          'exam_date': date,
          'is_retake': retake,
          'batch': batch,
          'section': section,
          'room': room,
        };

    testWidgets('a retake outranks the date', (t) async {
      // The distinction that once made batch 'RE' rows invisible to every
      // student: a retake sitting is a different population, so the pill says
      // so even when the date alone would have said "Scheduled".
      final future = DateTime.now().add(const Duration(days: 30));
      await pumpAt(
        t,
        desktop,
        AdminOverview(
          data: data(exams: [
            exam(date: future.toIso8601String(), retake: true),
          ]),
        ),
      );
      expect(find.text('Retake'), findsOneWidget);
      expect(find.text('Scheduled'), findsNothing);
    });

    testWidgets('past and future sittings are told apart', (t) async {
      final past = DateTime.now().subtract(const Duration(days: 30));
      final future = DateTime.now().add(const Duration(days: 30));
      await pumpAt(
        t,
        desktop,
        AdminOverview(
          data: data(exams: [
            exam(subject: 'Compilers', date: past.toIso8601String()),
            exam(subject: 'Networks', date: future.toIso8601String()),
          ]),
        ),
      );
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Scheduled'), findsOneWidget);
    });

    testWidgets('a missing date says so instead of rendering an epoch',
        (t) async {
      await pumpAt(t, desktop, AdminOverview(data: data(exams: [exam()])));
      expect(find.text('Undated'), findsOneWidget);
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('the class line survives missing parts', (t) async {
      await pumpAt(
        t,
        desktop,
        AdminOverview(data: data(exams: [exam(section: '', room: '')])),
      );
      expect(find.text('Batch 63'), findsOneWidget);
      // No stray separators for the fields that were not there.
      expect(find.textContaining('· ·'), findsNothing);
    });

    testWidgets('an empty schedule is a sentence', (t) async {
      await pumpAt(t, desktop, AdminOverview(data: data()));
      expect(find.text('No exams have been scheduled yet.'), findsOneWidget);
    });
  });

  group('recently joined — how each person proved who they are', () {
    Map<String, dynamic> joiner({
      String name = 'Rakib Hassan',
      bool verified = true,
      String source = 'diu_email',
    }) =>
        {
          'full_name': name,
          'is_verified': verified,
          'identity_source': source,
          'role': 'student',
          'university_id': '221-15-1234',
          'created_at': DateTime.now().toIso8601String(),
        };

    testWidgets('each state reads as words, not only as a colour', (t) async {
      await pumpAt(
        t,
        desktop,
        AdminOverview(
          data: data(recent: [
            joiner(name: 'A', verified: false),
            joiner(name: 'B', source: 'diu_email'),
            joiner(name: 'C', source: 'admin_override'),
            joiner(name: 'D', source: 'self'),
          ]),
        ),
      );
      expect(find.text('Awaiting approval'), findsOneWidget);
      expect(find.text('Email proven'), findsOneWidget);
      expect(find.text('Approved by admin'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('an unnamed row does not render null', (t) async {
      await pumpAt(
        t,
        desktop,
        AdminOverview(
            data: data(recent: [
          {'is_verified': true, 'identity_source': 'self', 'role': 'student'},
        ])),
      );
      expect(find.text('Unnamed'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
    });
  });

  group('AdminOverviewData reads the facets it is given', () {
    test('missing keys fall back rather than throwing', () {
      const d = AdminOverviewData(
        facets: {},
        recent: [],
        stuck: 0,
        exams: [],
        beds: 0,
        occupied: 0,
      );
      expect(d.total, 0);
      expect(d.pending, 0);
      expect(d.roles, isEmpty);
      expect(d.error, isNull);
    });

    test('a failed load carries the reason and no data', () {
      const d = AdminOverviewData.failed('PostgrestException');
      expect(d.error, 'PostgrestException');
      expect(d.total, 0);
      expect(d.exams, isEmpty);
      expect(d.beds, 0);
    });
  });
}
