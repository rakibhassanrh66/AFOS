import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/liquid_glass_tokens.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/info_card.dart';
import '../../../../core/layout/nav_insets.dart';
import '../../../../shared/widgets/pill_badge.dart';
import '../../../../shared/widgets/shimmer_card.dart';
import '../../data/repositories/course_offering_repository.dart';

/// Sat=0 .. Fri=6 — the DIU convention `schedule_slots.day_of_week` uses.
/// NOT ISO weekday order; keep in step with schedule_screen's `_dayLabels`.
const kDayLabels = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

Color offeringStatusColor(String s) => switch (s) {
      'approved' => AppColors.green,
      'rejected' => AppColors.red,
      _ => AppColors.amber,
    };

/// One offering, rendered the same way everywhere it appears (student browse,
/// teacher's own list, admin approval queue).
///
/// Built on [InfoCard]/[PillBadge] rather than a hand-rolled Container so it
/// picks up the glass treatment and the signature corner cut, and reads as
/// part of the same system as the routine's class cards. The three screens
/// previously each had their own copy of a flat 4-line grey text stack with
/// no visual hierarchy, where day/time — the most scannable attribute — was
/// buried on the last line.
class OfferingCard extends StatelessWidget {
  final Map<String, dynamic> offering;

  /// Right-hand action (join button, approve/decline pair, status pill).
  final Widget? trailing;

  /// Shown under the header, e.g. a rejection reason.
  final Widget? footer;
  final VoidCallback? onTap;
  final int index;

  const OfferingCard({
    super.key,
    required this.offering,
    this.trailing,
    this.footer,
    this.onTap,
    this.index = 0,
  });

  List<OfferingMeeting> get _meetings {
    final raw = offering['course_offering_meetings'] as List?;
    if (raw == null) return const [];
    final list = raw
        .cast<Map<String, dynamic>>()
        .map(OfferingMeeting.fromJson)
        .toList();
    list.sort((a, b) {
      final d = a.dayOfWeek.compareTo(b.dayOfWeek);
      return d != 0 ? d : a.startTime.compareTo(b.startTime);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final teacher = offering['profiles'] as Map<String, dynamic>? ?? const {};
    final meetings = _meetings;
    final isLab = meetings.any((m) => m.classType == 'lab');
    final outline = (offering['outline_text'] as String?)?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InfoCard(
        accent: isLab ? AppColors.purple : AppColors.blue,
        stripe: true,
        onTap: onTap,
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Course identity — the strongest line in the card.
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Text(
                '${course['code'] ?? '—'} · ${course['title'] ?? ''}',
                style: AppTextStyles.titleMedium.copyWith(color: textPrimary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isLab) const PillBadge(label: 'LAB', color: AppColors.purple),
          ]),
          const SizedBox(height: 6),

          // Who teaches it, and which cohort it's for.
          //
          // Cohort badge on its own line, not beside the name.
          //
          // As a non-flex sibling it was laid out first and left the Expanded
          // 80.9px for a name needing 300+ — "Md. Masukur Rahman Chowdhury"
          // reduced to "Md…" at a 2.0x text scale. Making it `Flexible` instead
          // just moved the damage: the badge then shrank below its own label
          // and hid half of "B68 · D". A person's name and their cohort are
          // both short strings that must be read in full, so neither can be the
          // one that gives way — they need separate lines rather than a
          // negotiation.
          Row(children: [
            Icon(Icons.person_outline_rounded, size: 14, color: textSecondary),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                teacher['full_name'] as String? ?? 'Faculty',
                style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: PillBadge(
              label: 'B${offering['batch'] ?? '—'} · ${offering['section'] ?? '—'}',
              color: AppColors.blue,
              // Uncapped: nothing beside it to starve.
              maxWidth: double.infinity,
            ),
          ),

          // Meetings get their own chips: a course meeting twice a week, or a
          // lab split into J1/J2, is several rows here rather than one line.
          if (meetings.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final m in meetings) _MeetingChip(meeting: m)],
            ),
          ],

          if (outline.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              outline,
              style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          if (footer != null) ...[const SizedBox(height: 8), footer!],
          if (trailing != null) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerRight, child: trailing!),
          ],
        ]),
      ),
    )
        .animate(delay: Duration(milliseconds: index * 55))
        .fadeIn(duration: LiquidGlass.motionFast)
        .slideY(begin: 0.05, curve: LiquidGlass.motionCurve);
  }
}

class _MeetingChip extends StatelessWidget {
  final OfferingMeeting meeting;
  const _MeetingChip({required this.meeting});

  @override
  Widget build(BuildContext context) {
    final isLab = meeting.classType == 'lab';
    final accent = isLab ? AppColors.purple : AppColors.blue;
    final day = meeting.dayOfWeek >= 0 && meeting.dayOfWeek < 7
        ? kDayLabels[meeting.dayOfWeek]
        : '—';
    final where = [meeting.building, meeting.roomNumber]
        .where((s) => s.trim().isNotEmpty)
        .join(' ');
    final subgroup = meeting.labSubgroup > 0 ? ' · J${meeting.labSubgroup}' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        border: Border.all(color: accent.withValues(alpha: 0.22), width: 0.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isLab ? Icons.science_outlined : Icons.schedule_rounded, size: 12, color: accent),
        const SizedBox(width: 5),
        // Flexible + ellipsis, NOT a bare Text. A chip carrying day, time,
        // subgroup AND building/room ("Mon 08:00–08:35 · AV4 220") is wider
        // than the card on a 360dp phone, and an unconstrained Text inside a
        // min-size Row overflowed by up to 44px — so the time and room, the
        // one thing a reviewer actually needs, sat behind overflow stripes.
        // Flexible still sizes to content whenever there IS room.
        Flexible(
          child: Text(
            '$day ${AppFormatters.timeRange12(meeting.startTime, meeting.endTime)}'
            '$subgroup${where.isEmpty ? '' : ' · $where'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(
              color: accent, fontWeight: FontWeight.w600, height: 1.1,
            ),
          ),
        ),
      ]),
    );
  }
}

/// Layout-matched loading placeholder.
///
/// The generic [ShimmerList] draws uniform 80px blocks, but an offering card
/// is ~140px with a title, a teacher row and a row of meeting chips — so the
/// content visibly jumped on load. Matching the real shape keeps the
/// transition still.
class OfferingCardSkeleton extends StatelessWidget {
  final int count;
  const OfferingCardSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // Matches the padding the loaded list uses (NavInsets.content), so the
      // rows don't shift when the real data replaces the shimmer.
      padding: NavInsets.content(context),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: ShimmerCard(height: 140, radius: LiquidGlass.radiusCard),
      ),
    );
  }
}
