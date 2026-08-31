import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/chart_palette.dart';
import '../../../../config/theme/spacing.dart';
import '../../../../core/utils/role_labels.dart';
import '../../../web/presentation/consoles/admin_overview.dart' show AdminOverviewData;
import '../../../web/presentation/widgets/chart_primitives.dart';
import '../../../web/presentation/widgets/console_grid.dart';

/// The phone counterpart to the web console's AdminOverview.
///
/// SAME DATA, SAME PRIMITIVES, DIFFERENT SHAPE. AdminOverviewData.load() was
/// already one parallel wave of six existing calls, already permission-gated
/// (null for anyone who is not super_admin/admin/dept_admin/users:approve) --
/// this needed zero backend changes and zero new RPCs. RingChart/BarList/
/// ChartLegend/GridPanel/GridFigure are ChartPalette-driven CustomPainter
/// widgets with no platform dependency, despite living under features/web:
/// only their CALLER there is kIsWeb-gated, so importing them here is exactly
/// as safe as this file (dashboard_screen.dart) already does for
/// role_console.dart.
///
/// ConsoleGrid itself (the 12-column layout) is NOT reused -- it is a desktop
/// grid and does not mean anything at 320-430dp. This lays the same panels
/// out as a single scrolling column with explicit heights instead.
class AdminInsightsPanel extends StatelessWidget {
  final AdminOverviewData? data;
  const AdminInsightsPanel({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final d = data;
    // Null means "this viewer gets no panel" (student/teacher, or the fetch
    // has not resolved yet) -- rendered as nothing, matching AdminOverview's
    // own contract, not as an error or a skeleton with nothing to show yet.
    if (d == null || d.error != null || d.total == 0) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Insights',
          style: AppTextStyles.headlineLarge
              .copyWith(color: AppColors.textPrimaryOf(context))),
      const SizedBox(height: AppSpace.md),
      SizedBox(
        height: 84,
        child: Row(children: [
          Expanded(
            child: GridFigure(
              label: 'Classes running',
              value: '${d.liveSlots}',
              note: 'across ${d.rooms} rooms',
              icon: Icons.calendar_view_week_rounded,
              accent: ChartPalette.series(context, 2),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: GridFigure(
              label: 'Awaiting approval',
              value: '${d.pending}',
              note: d.pending == 0 ? 'nothing waiting' : 'needs a decision',
              icon: Icons.how_to_reg_rounded,
              accent: d.pending > 0
                  ? ChartPalette.warning(context)
                  : ChartPalette.good(context),
            ),
          ),
        ]),
      ),
      if (d.liveSlots > 0 || d.beds > 0) ...[
        const SizedBox(height: AppSpace.sm),
        SizedBox(
          height: 224,
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (d.liveSlots > 0)
              Expanded(
                child: _RingPanel(
                  title: 'Labs and theory',
                  centerValue: '${d.liveSlots}',
                  centerLabel: 'timetabled',
                  slices: [
                    RingSlice(
                        label: 'Lab',
                        value: d.labSlots,
                        color: ChartPalette.series(context, 0)),
                    RingSlice(
                        label: 'Theory',
                        value: d.theorySlots,
                        color: ChartPalette.series(context, 1)),
                  ],
                ),
              ),
            if (d.liveSlots > 0 && d.beds > 0) const SizedBox(width: AppSpace.sm),
            if (d.beds > 0)
              Expanded(
                child: _RingPanel(
                  title: 'Hall occupancy',
                  centerValue: '${d.beds}',
                  centerLabel: 'total beds',
                  slices: [
                    RingSlice(
                        label: 'Occupied',
                        value: d.occupied,
                        color: ChartPalette.series(context, 0)),
                    RingSlice(
                        label: 'Available',
                        value: (d.beds - d.occupied).clamp(0, d.beds),
                        color: ChartPalette.series(context, 1)),
                  ],
                ),
              ),
          ]),
        ),
      ],
      if (d.roles.isNotEmpty) ...[
        const SizedBox(height: AppSpace.sm),
        SizedBox(
          height: 208,
          child: GridPanel(
            title: 'Who is in AFOS',
            child: BarList(
              total: d.total,
              data: [
                for (final r in d.roles)
                  BarDatum(roleLabel('${r['value']}'),
                      (r['count'] as num?)?.toInt() ?? 0),
              ],
            ),
          ),
        ),
      ],
    ]);
  }
}

class _RingPanel extends StatelessWidget {
  final String title;
  final String centerValue;
  final String centerLabel;
  final List<RingSlice> slices;

  const _RingPanel({
    required this.title,
    required this.centerValue,
    required this.centerLabel,
    required this.slices,
  });

  @override
  Widget build(BuildContext context) {
    return GridPanel(
      title: title,
      child: Column(children: [
        Expanded(
          child: RingChart(
              slices: slices, centerValue: centerValue, centerLabel: centerLabel),
        ),
        const SizedBox(height: AppSpace.sm),
        ChartLegend(slices: slices),
      ]),
    );
  }
}
