import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

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

  const MyCompletenessRing({super.key, required this.missing, required this.total});

  @override
  Widget build(BuildContext context) {
    if (missing <= 0 || total <= 0) return const SizedBox.shrink();
    final done = (total - missing).clamp(0, total);
    final pct = ((done / total) * 100).round();

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => context.push('/complete-profile'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: AppDepth.radius(2),
            border: Border.all(color: AppColors.borderOf(context), width: 0.5),
            boxShadow: AppDepth.shadow(2, isDark: AppColors.isDark(context)),
          ),
          child: Row(children: [
            SizedBox(
              width: 64,
              height: 64,
              child: RingChart(
                stroke: 10,
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
