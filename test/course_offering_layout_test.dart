import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/config/theme/app_colors.dart';
import 'package:afos_v7/features/schedule/presentation/manage_course_offerings_screen.dart';
import 'package:afos_v7/features/schedule/presentation/module_leader_screen.dart';
import 'package:afos_v7/features/schedule/presentation/widgets/offering_card.dart';
import 'package:afos_v7/shared/widgets/pill_badge.dart';

/// Layout guard for the course-offering cards.
///
/// WHAT THIS CATCHES, and why it is not covered by layout_overflow_test.
///
/// A `Row` lays its NON-FLEX children out first, with unbounded width, and
/// gives an `Expanded` sibling only what is left. A [PillBadge] carrying a long
/// label therefore takes the whole row and leaves the `Expanded(Text)` beside
/// it with **0.0px**. An uncapped `Text` answers a 0px box by wrapping one
/// glyph per line — a 500px-tall column of single letters where a course title
/// should be. That is not a RenderFlex overflow, so an overflow-only harness
/// reports success while the screen is unreadable. It shipped: the Teaching
/// Load cards carried 'ACCEPTED — CREATE OFFERING' and 'DECLINED — REASSIGN',
/// and My Course Offerings had an uncapped ended-course line.
///
/// So this asserts BOTH conditions, and it drives the REAL widgets rather than
/// re-declaring them. A copy in a test is worthless here: the first version of
/// this harness used simplified copies, "reproduced" a bug in two cards that
/// were actually fine, and missed nothing only by luck.
void main() {
  // Real devices, smallest first, and up to a 2.0x accessibility text scale —
  // the vertical-text failure starts at 1.0x on a 320dp phone and reaches a
  // 412dp phone by 1.3x, so a default-scale-only sweep would miss it.
  const sizes = <String, Size>{
    '320x568 (small Android)': Size(320, 568),
    '360x780 (common Android)': Size(360, 780),
    '412x915 (large Android)': Size(412, 915),
  };
  const scales = <double>[1.0, 1.3, 1.6, 2.0];

  Future<List<String>> faultsFor(
      WidgetTester tester, Widget child, Size size, double scale) async {
    final faults = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed')) faults.add('OVERFLOW: ${text.split('\n').first}');
    };

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          // Scrollable on purpose: every one of these cards lives in a
          // ListView in the app, so "taller than the phone" is normal and a
          // bottom overflow here would be an artifact of the harness rather
          // than a fault in the widget. Width is what is genuinely constrained,
          // and that is where all of these bugs live.
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: child,
            ),
          ),
        ),
      ),
    ));
    // Not pumpAndSettle: OfferingCard runs an entrance animation.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    FlutterError.onError = previous;

    for (final element in find.byType(Text).evaluate()) {
      final box = element.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final w = box.size.width, h = box.size.height;
      final data = (element.widget as Text).data ?? '';
      // Tall and pencil-thin == one glyph per line.
      if (data.trim().length > 4 && w < 34 && h > w * 2.2) {
        faults.add('VERTICAL TEXT "${data.substring(0, data.length.clamp(0, 40))}" '
            'w=${w.toStringAsFixed(1)} h=${h.toStringAsFixed(1)}');
      }
    }
    return faults;
  }

  Map<String, dynamic> offeringRow({bool archived = false}) => {
        'id': 'off-1',
        'batch': '68',
        'section': 'D',
        'status': 'approved',
        'is_archived': archived,
        'archived_at': '2026-07-26T16:43:12.206972Z',
        'courses': {
          'code': 'CSE321',
          'title': 'Computer Architecture and Organisation',
          'credit_hours': 3,
          'course_type': 'theory',
        },
        'profiles': {'full_name': 'Md. Masukur Rahman Chowdhury'},
        'course_offering_meetings': const [],
      };

  Map<String, dynamic> allocationRow(String status, {bool claimed = false}) => {
        'id': 'alloc-1',
        'course_code': 'CSE321',
        'course_title': 'Computer Architecture',
        'course_type': 'theory',
        'batch': '68',
        'section': 'D',
        'semester': 8,
        'note': 'Please coordinate the lab schedule with the module leader before week 3.',
        'status': status,
        'decline_reason': status == 'declined'
            ? 'Already teaching four sections this term and it clashes with CSE221.'
            : null,
        'offering_id': claimed ? 'off-1' : null,
        'offering_status': claimed ? 'approved' : null,
        'teacher_name': 'Md. Masukur Rahman Chowdhury',
      };

  final cases = <String, Widget Function()>{
    // --- My Course Offerings: the ended section, where this was reported.
    'EndedHeader': () => const EndedHeader(count: 1),
    'EndedOfferingRow': () => EndedOfferingRow(
        offering: offeringRow(archived: true), busy: false, onRestore: () {}),
    'EndedOfferingRow (busy)': () => EndedOfferingRow(
        offering: offeringRow(archived: true), busy: true, onRestore: () {}),

    // --- Teaching Load: both sides of the allocation, every state.
    for (final s in ['pending', 'accepted', 'declined'])
      'TeachingAssignmentCard ($s)': () => TeachingAssignmentCard(
          row: allocationRow(s), busy: false, onAccept: () {}, onDecline: () {}),
    'TeachingAssignmentCard (accepted, claimed)': () => TeachingAssignmentCard(
        row: allocationRow('accepted', claimed: true),
        busy: false, onAccept: () {}, onDecline: () {}),
    // The historical anomaly: a running offering on an allocation nobody ever
    // answered. Its card shows a longer explanation and only one button.
    'TeachingAssignmentCard (pending, claimed)': () => TeachingAssignmentCard(
        row: allocationRow('pending', claimed: true),
        busy: false, onAccept: () {}, onDecline: () {}),
    'AllocationCard (pending, claimed)': () => AllocationCard(
        row: allocationRow('pending', claimed: true), onRemove: () {}),
    for (final s in ['pending', 'accepted', 'declined'])
      'AllocationCard ($s)': () =>
          AllocationCard(row: allocationRow(s), onRemove: () {}, onReassign: () {}),
    'AllocationCard (live)': () => AllocationCard(
        row: allocationRow('accepted', claimed: true), onRemove: () {}),

    // --- OfferingCard with each screen's real trailing.
    'OfferingCard (teacher approved)': () => OfferingCard(
          offering: offeringRow(),
          trailing: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8, runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const PillBadge(label: 'APPROVED', color: AppColors.green),
              TextButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.forum_outlined, size: 15),
                  label: const Text('Group', style: TextStyle(fontSize: 12))),
              IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.archive_outlined, size: 18, color: AppColors.red)),
            ],
          ),
        ),
    'OfferingCard (admin reviewed, withdraw)': () => OfferingCard(
          offering: offeringRow(),
          trailing: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8, runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const PillBadge(label: 'APPROVED', color: AppColors.green),
              OutlinedButton(onPressed: () {}, child: const Text('Withdraw', maxLines: 1)),
            ],
          ),
          footer: const Text('Approved by Rakib Hassan · 27 Jul 2026, 4:56 AM'),
        ),

    // --- The structural guard itself. If someone puts a sentence in a badge
    // again, the badge must ellipsize rather than starve the title to 0px.
    'PillBadge with an over-long label beside a title': () => Row(children: [
          const Expanded(
              child: Text('CSE321 · Computer Architecture',
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          PillBadge(
              label: 'ACCEPTED — CREATE OFFERING NOW'.toUpperCase(),
              color: AppColors.blue),
        ]),
  };

  for (final entry in cases.entries) {
    testWidgets('layout: ${entry.key}', (tester) async {
      final failures = <String>[];
      for (final size in sizes.entries) {
        for (final scale in scales) {
          for (final fault in await faultsFor(tester, entry.value(), size.value, scale)) {
            failures.add('${size.key} @ ${scale}x -> $fault');
          }
        }
      }
      expect(failures, isEmpty,
          reason: '${entry.key} laid out wrong:\n${failures.join('\n')}');
    });
  }
}
