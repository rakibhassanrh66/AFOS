import 'package:flutter/material.dart';

import 'package:afos_v7/config/theme/app_colors.dart';
import 'package:afos_v7/config/theme/button_styles.dart';
import 'package:afos_v7/features/schedule/presentation/join_request_detail_screen.dart';
import 'package:afos_v7/features/schedule/presentation/join_requests_screen.dart';
import 'package:afos_v7/features/schedule/presentation/widgets/offering_card.dart';
import 'package:afos_v7/shared/widgets/pill_badge.dart';
import 'package:afos_v7/shared/widgets/user_details_sheet.dart';

import 'support/layout_probe.dart';

/// Layout guard for the screens a teacher or admin makes decisions on. The
/// probe, and why an overflow-only harness is not enough, live in
/// `support/layout_probe.dart`.
///
/// WHY THESE SCREENS SPECIFICALLY. The app theme sets
/// `minimumSize: Size(double.infinity, 52)` on `outlinedButtonTheme` and
/// `elevatedButtonTheme`, so every Decline/Accept, Remove/Reconsider and
/// Delete/Restore pair had one button demanding the entire row: clipped off the
/// edge inside a `Row`, or alone on its own line inside a `Wrap`. These are the
/// screens built almost entirely out of such pairs, and the reported symptom —
/// "the teacher can see the request and cannot act on it" — is invisible to a
/// test that does not measure at a narrow width.
///
/// Fixtures are deliberately long and realistic. A short name and a two-word
/// course title fit anywhere and would hide exactly this class of bug.
void main() {
  const longName = 'Md. Masukur Rahman Chowdhury';
  const longTitle = 'Computer Architecture and Organisation';

  Map<String, dynamic> requestRow({
    String status = 'pending',
    bool archived = false,
    bool matches = true,
    bool noBatch = false,
  }) =>
      {
        'id': 'enr-1',
        'status': status,
        'created_at': '2026-07-27T04:56:12.206972Z',
        'profiles': {
          'id': 'stu-1',
          'full_name': longName,
          'university_id': '221-15-5431',
          'email': 'masukur.rahman5431@diu.edu.bd',
          'avatar_url': null,
          'is_verified': true,
          'role': 'student',
          'department': 'Computer Science and Engineering',
          'semester': 8,
          'batch': noBatch ? null : '68',
          'section': noBatch ? null : (matches ? 'D' : 'B'),
        },
        'course_offerings': {
          'batch': '68',
          'section': 'D',
          'is_archived': archived,
          'courses': {'code': 'CSE321', 'title': longTitle},
        },
      };

  Map<String, dynamic> offeringRow({String status = 'pending'}) => {
        'id': 'off-1',
        'batch': '68',
        'section': 'D',
        'status': status,
        'is_archived': false,
        'created_at': '2026-07-26T16:43:12.206972Z',
        'reviewed_at': '2026-07-27T04:56:12.206972Z',
        'courses': {
          'code': 'CSE321',
          'title': longTitle,
          'credit_hours': 3,
          'course_type': 'theory',
        },
        'profiles': {'full_name': longName, 'teacher_initial': 'MRC'},
        'reviewer': {'full_name': 'Rakib Hassan'},
        'course_offering_meetings': const [],
      };

  final cases = <String, Widget Function()>{
    // --- Join Requests: every status, and every state the buttons take. -------
    for (final status in ['pending', 'approved', 'rejected'])
      'JoinRequestCard ($status)': () => JoinRequestCard(
            request: requestRow(status: status),
            busy: false,
            selectable: status == 'pending',
            selected: false,
            onToggleSelected: () {},
            onOpen: () {}, onAccept: () {}, onDecline: () {},
            onRemove: () {}, onReconsider: () {},
          ),
    // Ticked: adds a checkbox to the widest row in the card.
    'JoinRequestCard (pending, selected)': () => JoinRequestCard(
          request: requestRow(),
          busy: false, selectable: true, selected: true,
          onToggleSelected: () {},
          onOpen: () {}, onAccept: () {}, onDecline: () {},
          onRemove: () {}, onReconsider: () {},
        ),
    // Busy swaps a label for a spinner, which changes the pair's widths.
    'JoinRequestCard (pending, busy)': () => JoinRequestCard(
          request: requestRow(),
          busy: true, selectable: true, selected: false,
          onToggleSelected: () {},
          onOpen: () {}, onAccept: () {}, onDecline: () {},
          onRemove: () {}, onReconsider: () {},
        ),
    // Ended course: adds a red sentence between the notice and the buttons.
    'JoinRequestCard (pending, ended course)': () => JoinRequestCard(
          request: requestRow(archived: true),
          busy: false, selectable: true, selected: false,
          onToggleSelected: () {},
          onOpen: () {}, onAccept: () {}, onDecline: () {},
          onRemove: () {}, onReconsider: () {},
        ),
    'JoinRequestCard (mismatched section)': () => JoinRequestCard(
          request: requestRow(matches: false),
          busy: false, selectable: true, selected: false,
          onToggleSelected: () {},
          onOpen: () {}, onAccept: () {}, onDecline: () {},
          onRemove: () {}, onReconsider: () {},
        ),

    // --- The bars. Three controls plus a count, and a two-line explanation. ---
    'SelectionBar': () => SelectionBar(
        count: 12, busy: false, onClear: () {}, onAccept: () {}, onDecline: () {}),
    'SelectionBar (busy)': () => SelectionBar(
        count: 12, busy: true, onClear: () {}, onAccept: () {}, onDecline: () {}),
    'BulkAdmitBar': () =>
        BulkAdmitBar(matching: 47, total: 52, busy: false, onTap: () {}),
    'BulkAdmitBar (everyone matches)': () =>
        BulkAdmitBar(matching: 47, total: 47, busy: false, onTap: () {}),
    'BulkAdmitBar (busy)': () =>
        BulkAdmitBar(matching: 47, total: 52, busy: true, onTap: () {}),

    // --- The verdict notice, in all three of its readings. -------------------
    'BatchMatchNotice (match)': () => const BatchMatchNotice(
        studentBatch: '68', studentSection: 'D',
        offeringBatch: '68', offeringSection: 'D'),
    'BatchMatchNotice (mismatch)': () => const BatchMatchNotice(
        studentBatch: '67', studentSection: 'B',
        offeringBatch: '68', offeringSection: 'D'),
    'BatchMatchNotice (student has neither)': () => const BatchMatchNotice(
        studentBatch: null, studentSection: null,
        offeringBatch: '68', offeringSection: 'D'),

    // --- The identity block. This is the reported "scrambled" one: every row
    // is label-left / value-right, and a Spacer+Flexible pair used to split the
    // free space 50/50 so each value right-aligned to its OWN half.
    'UserDetailsSheet (as Review Request shows it)': () => UserDetailsSheet(
          profile: requestRow()['profiles'] as Map<String, dynamic>,
          extraRows: const {
            'Email': 'masukur.rahman5431@diu.edu.bd',
            'Semester': '8',
            'Requested': '27 Jul 2026, 4:56 AM',
          },
        ),
    'UserDetailsSheet (unverified, no student rows)': () => const UserDetailsSheet(
          profile: {
            'full_name': longName,
            'role': 'teacher',
            'department': 'Computer Science and Engineering',
            'is_verified': false,
          },
        ),

    // --- The whole Review Request page. Height is pinned because the probe
    // scrolls; width is what these bugs live in.
    for (final status in ['pending', 'approved', 'rejected'])
      'JoinRequestDetailScreen ($status)': () => SizedBox(
            height: 1400,
            child: JoinRequestDetailScreen(
              request: requestRow(status: status),
              onAccept: status == 'pending' ? () async {} : null,
              onDecline: status == 'pending' ? () async {} : null,
              onRemove: status == 'approved' ? () async {} : null,
              onReconsider: status == 'rejected' ? () async {} : null,
            ),
          ),
    'JoinRequestDetailScreen (ended course)': () => SizedBox(
          height: 1400,
          child: JoinRequestDetailScreen(
            request: requestRow(archived: true),
            onAccept: () async {},
            onDecline: () async {},
          ),
        ),

    // --- Admin review: the pair that could be seen and not acted on. ---------
    //
    // The admin screen builds these inline inside its State rather than as
    // widget classes, so this reproduces its `trailing` exactly — including
    // `rowAction`, which is the thing under test. Keep the two in step: if the
    // screen's trailing changes and this does not, the guard is worthless.
    'OfferingCard (admin pending: Decline + Approve)': () => OfferingCard(
          offering: offeringRow(),
          trailing: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8, runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: () {},
                style: rowAction(OutlinedButton.styleFrom(foregroundColor: AppColors.red)),
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: () {},
                style: rowAction(FilledButton.styleFrom(backgroundColor: AppColors.green)),
                child: const Text('Approve'),
              ),
            ],
          ),
        ),
    'OfferingCard (admin reviewed: badge + Withdraw)': () => OfferingCard(
          offering: offeringRow(status: 'approved'),
          trailing: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8, runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const PillBadge(label: 'APPROVED', color: AppColors.green),
              OutlinedButton(
                onPressed: () {},
                style: rowAction(OutlinedButton.styleFrom(foregroundColor: AppColors.red)),
                child: const Text('Withdraw', maxLines: 1),
              ),
            ],
          ),
          footer: const Text('Approved by Rakib Hassan · 27 Jul 2026, 4:56 AM'),
        ),
    'OfferingCard (admin reviewed: badge + Reopen)': () => OfferingCard(
          offering: offeringRow(status: 'rejected'),
          trailing: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8, runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const PillBadge(label: 'DECLINED', color: AppColors.red),
              OutlinedButton.icon(
                onPressed: () {},
                style: rowAction(),
                icon: const Icon(Icons.undo_rounded, size: 16),
                label: const Text('Reopen', maxLines: 1),
              ),
            ],
          ),
          footer: const Text('Declined by Rakib Hassan · 27 Jul 2026, 4:56 AM'),
        ),
  };

  runLayoutSweep('review layout', cases);
}
