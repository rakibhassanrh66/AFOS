import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/chart_palette.dart';
import '../../../../config/theme/depth.dart';
import '../../../../config/theme/motion.dart';
import '../../../../config/theme/spacing.dart';
import '../../../web/presentation/widgets/chart_primitives.dart';

/// Every user's own ring, not just the super_admin's. The owner's ask was for
/// something "living" and personal, for every user's own interest — this is
/// the honest version of that: a real number about THEM (how much of their
/// own profile is filled in), not a decorative loop.
///
/// WHAT "LIVING" MEANS HERE, AND WHAT IT DELIBERATELY DOES NOT.
/// The constitution is explicit and was not reinterpreted: "Animate on first
/// mount or explicit user action only. Never on rebuild," motion tokens only,
/// nothing past 620ms, zero jank on scroll. A ring that perpetually spins or
/// pulses on every one of thousands of phones, all day, is exactly what that
/// rule exists to stop — it would be decoration wearing "3D" as a costume,
/// not information. What this DOES do: a genuine sweep-in the one time it
/// mounts (the ring drawing itself open, not looping), and real depth from
/// [AppDepth]'s shadow system — occlusion + directional light + scale, the
/// doctrine's own definition of depth, not a blur trick. That is the
/// difference between "feels alive" and "never stops moving."
///
/// Disappears once the profile is complete, same contract as the exam pulse
/// band: a banner nagging about a thing that is already done is worse than no
/// banner.
class MyCompletenessRing extends StatelessWidget {
  final int missing;
  final int total;
  final List<String> reasons;

  /// Owned by the caller rather than hardcoded here: the caller needs to
  /// AWAIT the trip to /complete-profile and refresh afterward. Save &
  /// Continue there does `context.go('/home')`, not a pop -- which can land
  /// back on an already-mounted Dashboard whose _load() never re-runs, so
  /// this ring kept showing a stale "1 detail left" for an account that had
  /// actually just finished. A plain unmanaged push here could not fix that;
  /// only the caller refreshing its own data on return can.
  final VoidCallback onTap;

  const MyCompletenessRing({
    super.key,
    required this.missing,
    required this.total,
    required this.reasons,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (missing <= 0 || total <= 0) return const SizedBox.shrink();
    final done = (total - missing).clamp(0, total);
    final pct = ((done / total) * 100).round();

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: AppDepth.radius(2),
            border: Border.all(color: AppColors.borderOf(context), width: 0.5),
            boxShadow: AppDepth.shadow(2, isDark: AppColors.isDark(context)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              // 96px, not the original 64px: RingChart's centre figure is a
              // fixed 24px numericLarge style (right, correctly, for the big
              // web-console rings it was built for) and does not shrink to
              // fit a smaller ring. At 64px with a 10px stroke, "100%" had
              // nowhere to go but across the stroke itself -- the literal
              // "percentage crosses the ring border" report. 96px with an 8px
              // stroke leaves genuine room.
              SizedBox(
                width: 96,
                height: 96,
                child: RingChart(
                  stroke: 8,
                  centerValue: '$pct%',
                  centerLabel: '',
                  slices: [
                    RingSlice(label: 'Done', value: done, color: ChartPalette.good(context)),
                    RingSlice(
                        label: 'Remaining', value: missing, color: ChartPalette.muted(context)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Your profile is $pct% complete',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium
                          .copyWith(color: AppColors.textPrimaryOf(context))),
                  const SizedBox(height: 2),
                  Text(
                    missing == 1 ? '1 detail left to finish' : '$missing details left to finish',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.textSecondaryOf(context)),
                  ),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: AppColors.textSecondaryOf(context)),
            ]),
            // WHICH ONE, not just how many — "1 detail left" with nothing
            // named left the reader guessing, and guessing "it must be the
            // photo" when the real gap was something else entirely (an
            // already-admin-approved photo should never be the thing someone
            // keeps worrying about).
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in reasons)
                  Container(
                    padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.12),
                      borderRadius: AppDepth.radius(0),
                    ),
                    child: Text(r,
                        style: AppTextStyles.labelSmall.copyWith(color: AppColors.amber)),
                  ),
              ]),
            ],
          ]),
        ),
      ),
    )
        // ONE sweep-in, on mount, gone the instant reduced motion is asked
        // for (AppMotion.durationOf collapses it to Duration.zero rather than
        // skipping the widget — the ring still appears, just without the
        // entrance).
        .animate()
        .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
        .scaleXY(begin: 0.96, duration: AppMotion.durationOf(context, AppMotion.base),
            curve: AppMotion.standard);
  }
}
