import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/depth.dart';
import '../../../../config/theme/spacing.dart';
import '../../data/repositories/schedule_repository.dart';

/// Shown once a department's final exams are over and before its next routine
/// arrives.
///
/// WHY IT REPLACES THE ROUTINE RATHER THAN FILLING AN EMPTY DAY. Last
/// semester's slots stay in `schedule_slots` after the exams end — CSE holds
/// 1854 of them uploaded 2026-07-11, with finals ending 2026-08-27 — so the
/// day view was still printing a finished semester's timetable, with times, as
/// though term were running. An empty-state would never have fired, because
/// the days are not empty. See [ScheduleRepository.semesterBreak].
class SemesterBreakCard extends StatelessWidget {
  final SemesterBreak brk;

  /// Shown on the dashboard in a tighter form than on the routine screen.
  final bool compact;

  const SemesterBreakCard({super.key, required this.brk, this.compact = false});

  /// A line to end on, chosen by the DAY rather than at random.
  ///
  /// The constitution forbids motion on rebuild; the same reasoning applies to
  /// copy. A message that changes every time the widget rebuilds — a scroll, a
  /// keyboard opening — reads as broken rather than as encouragement. Keyed to
  /// the date so it is steady all day and different tomorrow.
  static String lineFor(DateTime day) {
    const lines = [
      'Rest properly. The next term starts whether or not you did.',
      'Nothing is due. That is the whole point of a break.',
      'Sleep, eat, see people who are not on your course.',
      'You finished. Let that be enough for a few days.',
      'Put the books down. They will still be there.',
      'A term you survived is a term you learned from.',
      'Take the break you actually earned.',
    ];
    return lines[(day.difference(DateTime(2020)).inDays) % lines.length];
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final term = brk.termLabel;

    return Container(
      padding: EdgeInsets.all(compact ? AppSpace.md : AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppDepth.radius(compact ? 1 : 2),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.green.withValues(alpha: 0.14),
              borderRadius: AppDepth.radius(1),
            ),
            child: const Icon(Icons.celebration_outlined,
                color: AppColors.green, size: 20),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  term.isEmpty
                      ? 'Final exams are over'
                      : '$term finals are over',
                  style: AppTextStyles.titleMedium.copyWith(
                      color: textPrimary, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Enjoy your semester break.',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: textSecondary)),
            ]),
          ),
        ]),
        const SizedBox(height: AppSpace.md),
        Text(lineFor(DateTime.now()),
            style: AppTextStyles.bodyMedium.copyWith(color: textPrimary)),
        const SizedBox(height: AppSpace.sm),
        // States plainly what ends this screen, so nobody wonders whether the
        // app has simply stopped working.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.schedule_rounded, size: 14, color: textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
                'Your class routine returns here as soon as next semester’s '
                'is published.',
                style:
                    AppTextStyles.labelSmall.copyWith(color: textSecondary)),
          ),
        ]),
      ]),
    );
  }
}
