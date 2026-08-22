import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../config/supabase_config.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/chart_palette.dart';
import '../../../../config/theme/spacing.dart';
import '../widgets/chart_primitives.dart';
import '../widgets/console_grid.dart';

/// The dashboard for everybody who is not an administrator.
///
/// WHY IT EXISTS. Four of the seven roles — student, teacher, staff, exam
/// controller — had no dashboard at all. The console gated its only panel set
/// behind super_admin/admin/dept_admin, so everyone else landed on a grid of
/// launcher tiles: twelve buttons and not one number. A student opening AFOS
/// could not see how many classes they had this week without navigating to the
/// routine and counting.
///
/// Every figure here is the CALLER'S OWN, read through `my_campus_facets()`,
/// which takes no user id and resolves `auth.uid()` itself — there is no
/// parameter anyone could point at somebody else. The campus-wide panels
/// beside them are the same numbers every role sees, and are not sensitive:
/// how busy the timetable is, how many clubs exist, how many bus routes run.
class PersonalOverviewData {
  final Map<String, dynamic> mine;
  final Map<String, dynamic> campus;
  final String? error;

  const PersonalOverviewData({
    this.mine = const {},
    this.campus = const {},
    this.error,
  });

  const PersonalOverviewData.failed(this.error)
      : mine = const {},
        campus = const {};

  int _m(String k) => (mine[k] as num?)?.toInt() ?? 0;
  int _c(String k) => (campus[k] as num?)?.toInt() ?? 0;

  int get mySlots => _m('myslots');
  int get myLabs => _m('mylabs');
  int get myTheory => (mySlots - myLabs).clamp(0, 1 << 30);
  int get myClubs => _m('clubs');
  int get myCourses => _m('enrollments');
  int get unread => _m('unread');

  String? get batch => mine['batch'] as String?;
  String? get section => mine['section'] as String?;

  /// "Batch 68 · Section D", or null when this person has no cohort — a staff
  /// member or an officer, who correctly has no timetable of their own.
  String? get cohort {
    final b = batch;
    if (b == null || b.isEmpty) return null;
    final s = section;
    return (s == null || s.isEmpty) ? 'Batch $b' : 'Batch $b · Section $s';
  }

  int get liveSlots => _c('liveSlots');
  int get clubs => _c('clubs');
  int get routes => _c('routes');
  int get stops => _c('stops');
  int get books => _c('books');
  int get rooms => _c('rooms');

  /// My classes per weekday, as bars. Days with no class are omitted rather
  /// than drawn as empty bars — a zero bar and a missing day look identical
  /// and only one of them is true.
  List<BarDatum> get byDay {
    const names = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    return ((mine['byDay'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((m) {
          final d = (m['d'] as num?)?.toInt() ?? 0;
          return BarDatum(names[d % names.length], (m['n'] as num?)?.toInt() ?? 0);
        })
        .toList();
  }

  static Future<PersonalOverviewData?> load() async {
    if (SupabaseConfig.client.auth.currentUser == null) return null;
    try {
      final r = await Future.wait<dynamic>([
        SupabaseConfig.client.rpc('my_campus_facets'),
        SupabaseConfig.client.rpc('campus_activity_facets'),
      ]);
      return PersonalOverviewData(
        mine: r[0] is Map ? Map<String, dynamic>.from(r[0] as Map) : const {},
        campus: r[1] is Map ? Map<String, dynamic>.from(r[1] as Map) : const {},
      );
    } catch (e) {
      return PersonalOverviewData.failed(e.toString());
    }
  }
}

class PersonalOverview extends StatelessWidget {
  final PersonalOverviewData? data;
  const PersonalOverview({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final d = data;
    if (d == null) return const SizedBox.shrink();

    if (d.error != null) {
      // SIZED, because GridPanel is built for a fixed box — it gives its child
      // `Expanded`, which cannot resolve inside the console's scroll view. The
      // grid normally supplies that height; off the grid the caller must.
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xl),
        child: SizedBox(
          height: ConsoleGrid.heightFor(PanelSpan.small),
          child: GridPanel(
            title: 'Your figures are unavailable',
            child: Center(
              child: Text(
                'Could not load your dashboard. The rest of the page is '
                'unaffected.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondaryOf(context)),
              ),
            ),
          ),
        ),
      );
    }

    final hasWeek = d.mySlots > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      child: ConsoleGrid(panels: [
        ConsolePanel(
          span: PanelSpan.stat,
          child: GridFigure(
            label: 'Your classes',
            value: '${d.mySlots}',
            note: d.cohort ?? 'no cohort assigned',
            icon: Icons.event_note_rounded,
            accent: ChartPalette.series(context, 0),
            onTap: () => context.push('/routine'),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.stat,
          child: GridFigure(
            label: 'Unread notifications',
            value: '${d.unread}',
            note: d.unread == 0 ? 'nothing new' : 'waiting for you',
            icon: Icons.notifications_rounded,
            accent: d.unread > 0
                ? ChartPalette.warning(context)
                : ChartPalette.good(context),
            onTap: () => context.push('/notifications'),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.stat,
          child: GridFigure(
            label: 'Clubs joined',
            value: '${d.myClubs}',
            note: 'of ${d.clubs} on campus',
            icon: Icons.groups_2_rounded,
            accent: ChartPalette.series(context, 2),
            onTap: () => context.push('/clubs'),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.stat,
          child: GridFigure(
            label: 'Courses enrolled',
            value: '${d.myCourses}',
            note: 'this semester',
            icon: Icons.menu_book_rounded,
            accent: ChartPalette.series(context, 1),
            onTap: () => context.push('/course-registration'),
          ),
        ),

        ConsolePanel(
          span: PanelSpan.tall,
          child: GridPanel(
            title: 'Your week',
            child: !hasWeek
                ? Center(
                    child: Text(
                      d.cohort == null
                          ? 'You have no cohort, so no timetable of your own.'
                          : 'No classes are timetabled for ${d.cohort}.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textSecondaryOf(context)),
                    ),
                  )
                : Column(children: [
                    Expanded(
                      child: RingChart(
                        centerValue: '${d.mySlots}',
                        centerLabel: 'classes',
                        slices: [
                          RingSlice(
                              label: 'Lab',
                              value: d.myLabs,
                              color: ChartPalette.series(context, 0)),
                          RingSlice(
                              label: 'Theory',
                              value: d.myTheory,
                              color: ChartPalette.series(context, 1)),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    ChartLegend(slices: [
                      RingSlice(
                          label: 'Lab',
                          value: d.myLabs,
                          color: ChartPalette.series(context, 0)),
                      RingSlice(
                          label: 'Theory',
                          value: d.myTheory,
                          color: ChartPalette.series(context, 1)),
                    ]),
                  ]),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.tall,
          child: GridPanel(
            title: 'Your busiest days',
            child: d.byDay.isEmpty
                ? Center(
                    child: Text('Nothing timetabled.',
                        style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textSecondaryOf(context))),
                  )
                : BarList(data: d.byDay, maxRows: 6),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.tall,
          child: GridPanel(
            title: 'Campus this week',
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MiniStat(
                    label: 'Classes timetabled', value: '${d.liveSlots}'),
                _MiniStat(label: 'Rooms in use', value: '${d.rooms}'),
                _MiniStat(label: 'Bus routes', value: '${d.routes}'),
                _MiniStat(label: 'Stops served', value: '${d.stops}'),
                _MiniStat(label: 'Library titles', value: '${d.books}'),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

/// A label/value pair on one line. Not a chart, because five unrelated totals
/// are five facts, not a distribution — putting them on a shared axis would
/// invite a comparison that means nothing.
class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondaryOf(context))),
        ),
        Text(value,
            style: AppTextStyles.numericSmall
                .copyWith(color: AppColors.textPrimaryOf(context))),
      ]);
}
