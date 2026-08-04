import 'package:flutter/material.dart';

import 'package:afos_v7/config/theme/app_colors.dart';
import 'package:afos_v7/features/schedule/presentation/browse_courses_screen.dart';
import 'package:afos_v7/features/schedule/presentation/manage_course_offerings_screen.dart';
import 'package:afos_v7/features/schedule/presentation/module_leader_screen.dart';
import 'package:afos_v7/features/schedule/presentation/widgets/offering_card.dart';
import 'package:afos_v7/shared/widgets/pill_badge.dart';

import 'support/layout_probe.dart';

/// Layout guard for the course-offering cards. The probe itself, and why an
/// overflow-only harness is not enough, live in `support/layout_probe.dart`.
///
/// What shipped broken and is pinned here: the Teaching Load cards carried
/// 'ACCEPTED — CREATE OFFERING' and 'DECLINED — REASSIGN' in a badge that
/// starved the title beside it, and My Course Offerings had an uncapped
/// ended-course line beside a fixed-width Restore button.
void main() {
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
    // Delete + Restore together: two buttons and the longest text line in the
    // card, which is the exact shape that produced the vertical-letter column.
    'EndedOfferingRow (deletable)': () => EndedOfferingRow(
        offering: offeringRow(archived: true),
        busy: false, onRestore: () {}, onDelete: () {}),
    'EndedOfferingRow (deletable, enrolled)': () => EndedOfferingRow(
        offering: {...offeringRow(archived: true), 'enrollments': [{'count': 42}]},
        busy: false, onRestore: () {}, onDelete: () {}),
    'EndedOfferingRow (deletable, busy)': () => EndedOfferingRow(
        offering: offeringRow(archived: true),
        busy: true, onRestore: () {}, onDelete: () {}),

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

    // --- Browse Courses: the student's own history section.
    'UnlistedEnrollmentsHeader': () => const UnlistedEnrollmentsHeader(count: 2),
    for (final s in ['pending', 'approved'])
      'UnlistedEnrollmentRow ($s, ended course)': () => UnlistedEnrollmentRow(
            enrollment: {
              'status': s,
              'offering_id': 'off-1',
              'course_offerings': {...offeringRow(archived: true)},
            },
          ),
    'UnlistedEnrollmentRow (filtered out, not ended)': () => UnlistedEnrollmentRow(
          enrollment: {
            'status': 'approved',
            'offering_id': 'off-1',
            'course_offerings': {...offeringRow()},
          },
        ),

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

  runLayoutSweep('layout', cases);
}
