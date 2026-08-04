import 'package:flutter/material.dart';

import 'package:afos_v7/config/theme/app_colors.dart';
import 'package:afos_v7/shared/widgets/afos_button.dart';
import 'package:afos_v7/shared/widgets/empty_state.dart';
import 'package:afos_v7/shared/widgets/error_view.dart';
import 'package:afos_v7/shared/widgets/feature_header.dart';
import 'package:afos_v7/shared/widgets/glass_chip.dart';
import 'package:afos_v7/shared/widgets/info_card.dart';
import 'package:afos_v7/shared/widgets/label_value_row.dart';
import 'package:afos_v7/shared/widgets/pill_badge.dart';
import 'package:afos_v7/shared/widgets/sheet_header.dart';
import 'package:afos_v7/shared/widgets/stat_tile.dart';

import 'support/layout_probe.dart';

/// The widgets in `lib/shared/widgets/` — swept because they are the pieces
/// every screen is built from, so one fault here is a fault in many places at
/// once and one fix covers all of them.
///
/// Driven with ADVERSARIAL content, not placeholder content. These bugs are
/// invisible with "Test" and "Lorem ipsum": the whole failure mode is a real
/// string being longer than the box it was given, so the fixtures use the
/// longest values this app actually holds — a full Bangladeshi name, a real
/// course title, a department spelled out.
void main() {
  // Real values from this project, at the long end of what the database holds.
  const longName = 'Md. Masukur Rahman Chowdhury';
  const longCourse = 'CSE321 · Computer Architecture and Organization';
  const longDept = 'Computer Science and Engineering';
  const longSentence =
      'Courses you asked to join or were enrolled in that are no longer shown '
      'above — usually because the teacher ended them.';

  final cases = <String, Widget Function()>{
    // --- Text pairs, the classic starve shape. ---------------------------
    'LabelValueRow (long value)': () => const LabelValueRow(
        label: 'Department', value: longDept, icon: Icons.school_outlined),
    // 'Designation' is the LONGEST label this widget is given anywhere in the
    // app (checked against every call site). An earlier version of this case
    // invented a 19-character label and duly reported a starve — a bug in the
    // fixture, not the widget, whose 100px column is documented as sized for
    // the labels it actually carries. Adversarial content has to stay real.
    'LabelValueRow (longest real label + long value)': () => const LabelValueRow(
        label: 'Designation', value: longName, icon: Icons.person),

    // --- A header with a trailing action: the shape that starved the
    // Teaching Load cards. ------------------------------------------------
    'FeatureHeader (long title + trailing)': () => FeatureHeader(
          title: longCourse,
          subtitle: longDept,
          icon: Icons.menu_book_outlined,
          trailing: FilledButton(onPressed: () {}, child: const Text('Allocate')),
        ),
    'FeatureHeader (long title, no trailing)': () =>
        const FeatureHeader(title: longCourse, subtitle: longDept),

    'SheetHeader (long title + trailing)': () => SheetHeader(
          title: longCourse,
          subtitle: longName,
          trailing: IconButton(onPressed: () {}, icon: const Icon(Icons.close)),
        ),

    // --- Cards. ------------------------------------------------------------
    'InfoCard (long title/subtitle + trailing badge)': () => const InfoCard(
          icon: Icons.menu_book_outlined,
          title: longCourse,
          subtitle: longName,
          trailing: PillBadge(label: 'SUBMITTED', color: AppColors.blue),
        ),
    'InfoCard (long title + wide trailing)': () => InfoCard(
          icon: Icons.groups_outlined,
          title: longCourse,
          subtitle: longDept,
          trailing: OutlinedButton(
              onPressed: () {}, child: const Text('Remove from this course')),
        ),

    // --- A stat tile's number must never be the thing that wraps. ---------
    'StatTile (long label)': () => const StatTile(
        value: '128', label: 'Pending approvals', icon: Icons.inbox_outlined),
    'StatTile (long value)': () =>
        const StatTile(value: '1,284,000', label: 'Total', icon: Icons.numbers),

    // --- Full-width buttons have to fit their own label. -------------------
    'AfosButton (long label)': () =>
        const AfosButton(label: 'Remove this student from the course'),
    'AfosButton (long label, outlined + icon)': () => const AfosButton(
        label: 'Put this request back in the queue',
        outlined: true,
        icon: Icons.undo_rounded),

    // --- Chips wrap in filter rows. ---------------------------------------
    'GlassChip (long label)': () => const GlassChip(label: 'All $longDept'),
    'GlassChip (long label, expand)': () =>
        const GlassChip(label: 'All $longDept', expand: true, selected: true),

    // --- Empty and error states carry the longest prose in the app. -------
    'EmptyState (long subtitle)': () => const EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'No courses for your section',
        subtitle: longSentence),
    'EmptyState (with action)': () => EmptyState(
        icon: Icons.error_outline,
        title: 'Nothing running yet',
        subtitle: longSentence,
        actionLabel: 'Show all of $longDept',
        onAction: () {}),
    'ErrorView (long message + retry)': () =>
        ErrorView(message: longSentence, onRetry: () {}),

    // --- The badge itself, at the labels this app actually uses. ----------
    for (final label in const [
      'UNANSWERED',
      'AWAITING',
      'SUBMITTED',
      'SUPER ADMIN',
    ])
      'PillBadge on its own line ($label)': () => Align(
            alignment: Alignment.centerLeft,
            child: PillBadge(
                label: label,
                color: AppColors.amber,
                maxWidth: double.infinity),
          ),
  };

  runLayoutSweep('shared', cases);
}
