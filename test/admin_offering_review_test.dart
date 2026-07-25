import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/features/schedule/presentation/widgets/offering_card.dart';
import 'package:afos_v7/config/theme/app_colors.dart';
import 'package:afos_v7/shared/widgets/pill_badge.dart';

/// Reproduces the admin "Pending Offerings" review row with the EXACT payload
/// the live database returns for the stuck CSE221 offering, to find why the
/// super-admin can see the card but cannot act on it.
void main() {
  // Verbatim from course_offerings + course_offering_meetings.
  final offering = <String, dynamic>{
    'id': '0504ace1-0ec4-44ef-a879-c60159a9f4f6',
    'batch': '68',
    'section': 'D',
    'department': 'CSE',
    'semester': 8,
    'status': 'pending',
    'outline_text': null,
    'max_students': null,
    'courses': {
      'code': 'CSE221',
      'title': 'Object Oriented Programming',
      'credit_hours': 3,
      'course_type': 'theory',
    },
    'profiles': {'full_name': 'Masuk', 'avatar_url': null, 'teacher_initial': 'MK'},
    'course_offering_meetings': [
      {
        'id': '004dc4d4-6cc9-456b-86ef-0edd8dbffaf4',
        'day_of_week': 2,
        'start_time': '08:00:00',
        'end_time': '08:35:00',
        'room_number': '220',
        'building': 'AV4',
        'class_type': 'theory',
        'lab_subgroup': 0,
      },
    ],
  };

  Widget harness(Widget child) => MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(body: child),
      );

  Widget adminRow(VoidCallback onApprove, VoidCallback onDecline) => OfferingCard(
        offering: offering,
        index: 0,
        // Mirrors manage_course_offerings_admin_screen.dart's trailing exactly.
        trailing: Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: onDecline,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
              child: const Text('Decline'),
            ),
            FilledButton(
              onPressed: onApprove,
              style: FilledButton.styleFrom(backgroundColor: AppColors.green),
              child: const Text('Approve'),
            ),
          ],
        ),
      );

  for (final width in <double>[320, 360, 412]) {
    testWidgets('renders without overflow at ${width.toInt()}px wide', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [adminRow(() {}, () {})],
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'card overflowed or threw at ${width}px');
      expect(find.text('Approve'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });
  }

  testWidgets('the Approve and Decline buttons are actually tappable', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var approved = 0, declined = 0;
    await tester.pumpWidget(harness(
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [adminRow(() => approved++, () => declined++)],
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Approve'));
    await tester.tap(find.text('Decline'));
    await tester.pumpAndSettle();

    expect(approved, 1, reason: 'Approve did not fire — something is eating the tap');
    expect(declined, 1, reason: 'Decline did not fire — something is eating the tap');
  });

  // The teacher's own list packs even more into the same trailing slot than the
  // admin's two buttons, so it is the next most likely place to clip.
  for (final width in <double>[320, 360]) {
    testWidgets('teacher trailing (approved: pill + Group + archive) fits at ${width.toInt()}px',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(harness(ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          OfferingCard(
            offering: offering,
            index: 0,
            // Mirrors manage_course_offerings_screen.dart's trailing exactly.
            trailing: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                PillBadge(label: 'APPROVED', color: offeringStatusColor('approved')),
                TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.forum_outlined, size: 15),
                  label: const Text('Group', style: TextStyle(fontSize: 12)),
                ),
                IconButton(
                  tooltip: 'End course (archive)',
                  onPressed: () {},
                  icon: const Icon(Icons.archive_outlined, size: 18, color: AppColors.red),
                ),
              ],
            ),
          ),
        ],
      )));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull,
          reason: 'teacher trailing overflowed at ${width}px');
      expect(find.text('Group'), findsOneWidget);
    });
  }

  testWidgets('the meeting time/room is visible so there is something to review',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness(
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [adminRow(() {}, () {})],
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('CSE221'), findsOneWidget);
    expect(find.textContaining('Masuk'), findsOneWidget);
    // 12-hour, matching every other time in the app and the time picker the
    // teacher used to enter it. The card used to render the stored 24-hour
    // "08:00" verbatim, so this assertion pinned that inconsistency in place.
    expect(find.textContaining('8:00–8:35 AM'), findsOneWidget,
        reason: 'the class time must be on the card for a reviewer to judge it');
  });
}
