import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../config/supabase_config.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/depth.dart';
import '../../../../config/theme/spacing.dart';
import '../../../../core/auth/permission_session.dart';
import '../../../../core/auth/role_session.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/role_labels.dart';
import '../../../../config/theme/chart_palette.dart';
import '../widgets/chart_primitives.dart';
import '../widgets/console_grid.dart';
import '../widgets/web_layout.dart';

/// The desktop console's data half — figures, a population breakdown, and the
/// most recent registrations.
///
/// WHY THIS EXISTS. Removing the duplicated capability grid left the console
/// with three work-area cards and roughly 700px of nothing. The grid was the
/// right thing to delete (it repeated the sidebar verbatim) but deleting it
/// exposed that the page had never carried any actual information — it was a
/// launcher wearing a dashboard's name.
///
/// MEASURED AGAINST THE REFERENCE, 2026-08-17. The reference console has ten
/// panels. The first pass built two of them and dropped the rest on my own
/// judgement without checking the data — which was wrong twice over, because
/// two of those panels ARE supported here. Every row below is a real count
/// taken from the live project, not an assumption:
///
///   BUILT, data confirmed
///     Recent registrations  12 profiles, with is_verified + identity_source
///     Population breakdown  role facets
///     Exam schedule         38 exams, 1632 room allocations
///     Hall occupancy        5 active halls, 2800 beds, 3 approved applications
///
///   NOT BUILT, because the table is genuinely empty
///     Fee collection    payment_records = 0 rows
///     Salary status     no payroll table exists at all
///     Scholarships      no scholarship concept in this schema
///     Student result    marks = 0, semester_results = 0
///     Attendance trend  attendance_sessions = 2, attendance_records = 4
///     Admission trend   12 profiles over ~4 months
///
/// The last two are the ones worth restating: a twelve-month line drawn
/// through two sessions, or a trend through three monthly points, is an
/// invented curve. Those panels become honest the moment the data exists and
/// can be added then — the omission is about row counts, not about effort.
///
/// WEB ONLY. Gated on kIsWeb + isExpanded inside [AdminOverview]; the phone
/// dashboard is a launcher by design and is not touched.
///
/// ---
///
/// [AdminOverviewData] is everything the overview draws, fetched in ONE wave,
/// by the console rather than by the widget.
///
/// WHY THIS IS NOT A StatefulWidget ANY MORE. It was, and it fetched in its own
/// initState — which meant it could not even start until RoleConsole had
/// finished its own three awaits and painted. The result was two loading
/// stages: the console's shimmer resolved, the page painted with the overview
/// at zero height, and then ~900px of panels dropped in ABOVE the work areas
/// and shoved them down the screen.
///
/// That is the layout shift the constitution bans, and no skeleton could have
/// fixed it honestly, because the shift was not caused by a missing
/// placeholder — it was caused by fetching in the wrong place. The console now
/// loads this alongside its own data and holds its single shimmer until both
/// are in, so there is exactly one loading state and the overview is at its
/// final height on the first frame it is visible.
class AdminOverviewData {
  final Map<String, dynamic> facets;
  final List<Map<String, dynamic>> recent;
  final int stuck;

  /// Verified accounts still failing `profile_is_complete()` — the same
  /// population the Profile Inspection screen lists, and the web counterpart
  /// of the banner the phone's Manage Users screen carries. Without it the
  /// console had no route to that tool at all on web.
  final int incomplete;
  final List<Map<String, dynamic>> exams;
  final int beds;
  final int occupied;

  /// Everything `campus_activity_facets()` returns — the routine density grid,
  /// room and teacher counts, load per batch, and the campus-wide totals. One
  /// RPC, roughly sixty numbers, instead of the 1854 schedule rows a browser
  /// would otherwise have to download to count them itself.
  final Map<String, dynamic> campus;

  /// Set when the fetch threw. The overview then renders a single explanatory
  /// panel instead of figures, and the rest of the console is unaffected.
  final String? error;

  const AdminOverviewData({
    required this.facets,
    required this.recent,
    required this.stuck,
    required this.incomplete,
    required this.exams,
    required this.beds,
    required this.occupied,
    this.campus = const {},
    this.error,
  });

  const AdminOverviewData.failed(this.error)
      : facets = const {},
        recent = const [],
        stuck = 0,
        incomplete = 0,
        exams = const [],
        beds = 0,
        occupied = 0,
        campus = const {};

  int _c(String k) => (campus[k] as num?)?.toInt() ?? 0;

  int get liveSlots => _c('liveSlots');
  int get labSlots => _c('labSlots');
  int get theorySlots => (liveSlots - labSlots).clamp(0, 1 << 30);
  int get rooms => _c('rooms');
  int get routineTeachers => _c('teachers');
  int get clubs => _c('clubs');
  int get stops => _c('stops');
  int get routes => _c('routes');
  int get books => _c('books');

  /// `[{k, n}]` pairs from the campus payload, already sorted by the database.
  List<BarDatum> _pairs(String key) => ((campus[key] as List?) ?? const [])
      .cast<Map<String, dynamic>>()
      .map((m) => BarDatum('${m['k']}', (m['n'] as num?)?.toInt() ?? 0))
      .toList();

  List<BarDatum> get loadByBatch => _pairs('byBatch');
  List<BarDatum> get busiestRooms => _pairs('topRooms');

  /// The density grid as `[day][hourIndex]`, over the hours that actually have
  /// classes. Built here rather than in the widget so the panel stays a pure
  /// render of a prepared matrix.
  ({List<List<num>> grid, List<String> days, List<String> hours})
      get densityGrid {
    final cells = ((campus['density'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    if (cells.isEmpty) {
      return (grid: const [], days: const [], hours: const []);
    }

    final hourSet = <int>{};
    var maxDay = 0;
    for (final c in cells) {
      hourSet.add((c['h'] as num).toInt());
      final d = (c['d'] as num).toInt();
      if (d > maxDay) maxDay = d;
    }
    final hours = hourSet.toList()..sort();

    // DIU's week starts Saturday, and day_of_week is stored 0-based from it.
    const names = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];
    final dayCount = maxDay + 1;

    final grid = List.generate(
        dayCount, (_) => List<num>.filled(hours.length, 0), growable: false);
    for (final c in cells) {
      final d = (c['d'] as num).toInt();
      final hi = hours.indexOf((c['h'] as num).toInt());
      if (d >= 0 && d < dayCount && hi >= 0) {
        grid[d][hi] = (c['n'] as num?)?.toInt() ?? 0;
      }
    }

    return (
      grid: grid,
      days: [for (var i = 0; i < dayCount; i++) names[i % names.length]],
      hours: [for (final h in hours) '$h'],
    );
  }

  int get total => (facets['total'] as num?)?.toInt() ?? 0;
  int get pending => (facets['pending'] as num?)?.toInt() ?? 0;

  List<Map<String, dynamic>> get roles =>
      ((facets['roles'] as List?) ?? const []).cast<Map<String, dynamic>>();

  /// Returns null when this viewer has no business seeing the panel at all —
  /// which the caller renders as nothing, not as an error.
  static Future<AdminOverviewData?> load() async {
    // Checked client-side first so a student never fires three RPCs that the
    // database will refuse anyway. RLS and the functions' own guard remain the
    // real boundary — this only avoids the pointless round trip and the error
    // state it would paint.
    final role = await RoleSession.ensureLoaded();
    final grants = await PermissionSession.ensureLoaded();
    final allowed = const {'super_admin', 'admin', 'dept_admin'}.contains(role) ||
        grants.contains('users:approve');
    if (!allowed) return null;

    try {
      // ALL SIX TOGETHER, not three-then-three.
      //
      // The second half of this list was already parallel and the first half
      // was not, so the console sat through FOUR sequential round trips before
      // it could paint one figure — and it does that after RoleConsole has
      // already finished its own three. Six independent reads of six different
      // tables; the only reason to await one at a time is if a later call
      // needs an earlier answer, and none of them does.
      //
      // The fallback queue is a count here, not a list: the console's job is to
      // say "there is something to look at", and manage_users owns the doing.
      final results = await Future.wait<dynamic>([
        SupabaseConfig.client.rpc('admin_user_facets'),
        SupabaseConfig.client.rpc('admin_search_users', params: {'p_limit': 6}),
        SupabaseConfig.client.rpc('admin_list_stuck_registrations'),
        SupabaseConfig.client
            .from('exams')
            .select('subject, subject_code, exam_date, start_time, batch, '
                'section, room, building, exam_type, is_retake')
            .order('exam_date', ascending: false)
            .limit(6),
        SupabaseConfig.client.from('halls').select('capacity').eq('is_active', true),
        SupabaseConfig.client
            .from('hall_applications')
            .select('id')
            .eq('status', 'approved'),
        // The campus panels. Joins the same wave rather than adding an eighth
        // round trip after it.
        SupabaseConfig.client.rpc('campus_activity_facets'),
        // Incomplete profiles, counted server-side off the trigger-maintained
        // `profile_completed` flag — a HEAD request like the rest, and in the
        // same wave for the same reason. Mirrors the count behind the phone's
        // Profile Inspection banner so the two surfaces cannot disagree.
        SupabaseConfig.client
            .from('profiles')
            .count()
            .eq('is_verified', true)
            .eq('profile_completed', false),
      ]);

      final facets = results[0];
      final halls = (results[4] as List).cast<Map<String, dynamic>>();
      return AdminOverviewData(
        facets: facets is Map ? Map<String, dynamic>.from(facets) : const {},
        recent: (results[1] as List).cast<Map<String, dynamic>>(),
        stuck: (results[2] as List).length,
        incomplete: (results[7] as num?)?.toInt() ?? 0,
        exams: (results[3] as List).cast<Map<String, dynamic>>(),
        beds: halls.fold<int>(
            0, (sum, h) => sum + ((h['capacity'] as num?)?.toInt() ?? 0)),
        occupied: (results[5] as List).length,
        campus: results[6] is Map
            ? Map<String, dynamic>.from(results[6] as Map)
            : const {},
      );
    } catch (e) {
      return AdminOverviewData.failed(e.toString());
    }
  }
}

class AdminOverview extends StatelessWidget {
  /// Null means "this viewer gets no overview" — a student, or a console that
  /// has not been given any. It is NOT a loading state: the console does not
  /// build this widget until its data is in.
  final AdminOverviewData? data;
  const AdminOverview({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    // THE kIsWeb / isExpanded GATE LIVES IN THE CALLER, not here.
    //
    // Keeping it here made the whole widget untestable: kIsWeb is a const
    // false under the Dart VM, so every widget test of this file would have
    // asserted against an empty SizedBox and passed while proving nothing.
    // RoleConsole decides whether to build it; this decides how to draw it.
    final d = data;
    if (d == null) return const SizedBox.shrink();

    if (d.error != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.xl),
        child: WebPanel(
          title: 'Overview unavailable',
          child: Text(
            'Could not load the figures for this console. The rest of the page '
            'is unaffected.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondaryOf(context)),
          ),
        ),
      );
    }

    final density = d.densityGrid;

    // EVERY PANEL DECLARES A SPAN, and the rows total twelve. That is the whole
    // difference from the version this replaces, where two hand-rolled
    // LayoutBuilders each guessed a flex and every panel's height was whatever
    // its content came to. Reading down the spans below tells you the page
    // layout without running it — which is what "designed" means here.
    //
    //   3+3+3+3   figures
    //   3         incomplete profiles (wraps onto its own line)
    //   12        routine density
    //   4+4+4     population · lab split · halls
    //   6+6       load by batch · exam schedule
    //   6+6       busiest rooms · recently joined
    //   3+3+3+3   campus figures
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xl),
      child: ConsoleGrid(panels: [
        ConsolePanel(
          span: PanelSpan.stat,
          child: GridFigure(
            label: 'People in AFOS',
            value: '${d.total}',
            note: 'across every role',
            icon: Icons.groups_rounded,
            accent: ChartPalette.series(context, 0),
            onTap: () => context.push('/admin/users'),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.stat,
          child: GridFigure(
            label: 'Awaiting approval',
            value: '${d.pending}',
            // The note carries the meaning, not the colour — a warning-tinted
            // tile with no words is a puzzle to anyone who cannot see the tint.
            note: d.pending == 0 ? 'nothing waiting' : 'needs a decision',
            icon: Icons.how_to_reg_rounded,
            accent: d.pending > 0
                ? ChartPalette.warning(context)
                : ChartPalette.good(context),
            onTap: () => context.push('/admin/users'),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.stat,
          child: GridFigure(
            label: 'Code failed',
            value: '${d.stuck}',
            note: d.stuck == 0 ? 'none stuck' : 'verification did not settle',
            icon: Icons.mark_email_unread_rounded,
            accent: d.stuck > 0
                ? ChartPalette.critical(context)
                : ChartPalette.good(context),
            onTap: () => context.push('/admin/users'),
          ),
        ),
        // The web counterpart of the phone's Profile Inspection banner, and
        // the ONLY route to /admin/inspection on this platform — the console
        // is the web dashboard, so without this tile a super admin working on
        // a desktop had no way to reach the tool at all.
        //
        // This is the NINTH stat figure, and `stat` is 3 columns — "four
        // across a full-width row" — so it cannot join the row above without
        // making it fifteen. It wraps onto its own line instead, which the
        // span map at the top of this method now says out loud rather than
        // leaving the next reader to discover it on a 1600px screen. Placed
        // here rather than in the campus figures at the bottom because this
        // one is WORK: it is the only figure on this console that asks the
        // viewer to go and do something about it.
        ConsolePanel(
          span: PanelSpan.stat,
          child: GridFigure(
            label: 'Incomplete profiles',
            value: '${d.incomplete}',
            note: d.incomplete == 0
                ? 'everyone passes'
                : 'missing required details',
            icon: Icons.fact_check_rounded,
            accent: d.incomplete > 0
                ? ChartPalette.warning(context)
                : ChartPalette.good(context),
            onTap: () => context.push('/admin/inspection'),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.stat,
          child: GridFigure(
            label: 'Classes running',
            value: _grouped(d.liveSlots),
            note: 'this week, across ${d.rooms} rooms',
            icon: Icons.calendar_view_week_rounded,
            accent: ChartPalette.series(context, 2),
            onTap: () => context.push('/routine'),
          ),
        ),

        // The single biggest dataset in the project — 1854 slots — and until
        // now it appeared on no panel anywhere.
        ConsolePanel(
          span: PanelSpan.wide,
          child: GridPanel(
            title: 'When the campus is busy',
            child: density.grid.isEmpty
                ? const _Empty('No routine has been uploaded yet.')
                : HeatGrid(
                    values: density.grid,
                    rowLabels: density.days,
                    colLabels: density.hours,
                  ),
          ),
        ),

        ConsolePanel(
          span: PanelSpan.tall,
          child: GridPanel(
            title: 'Who is in AFOS',
            child: d.roles.isEmpty
                ? const _Empty('No accounts yet.')
                : BarList(
                    total: d.total,
                    data: [
                      for (final r in d.roles)
                        BarDatum(roleLabel('${r['value']}'),
                            (r['count'] as num?)?.toInt() ?? 0),
                    ],
                  ),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.tall,
          child: _RingPanel(
            title: 'Labs and theory',
            centerValue: _grouped(d.liveSlots),
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
            empty: d.liveSlots == 0 ? 'No classes are timetabled.' : null,
          ),
        ),
        ConsolePanel(
          span: PanelSpan.tall,
          child: _RingPanel(
            title: 'Hall occupancy',
            centerValue: _grouped(d.beds),
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
            empty: d.beds == 0 ? 'No halls are configured.' : null,
          ),
        ),

        ConsolePanel(
          span: PanelSpan.large,
          child: GridPanel(
            title: 'Teaching load by batch',
            child: d.loadByBatch.isEmpty
                ? const _Empty('No routine has been uploaded yet.')
                : BarList(data: d.loadByBatch),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.large,
          child: GridPanel(
            title: 'Exam schedule',
            actions: const [_SeeAll(to: '/manage-exam-seats')],
            child: _ExamSchedule(rows: d.exams),
          ),
        ),

        ConsolePanel(
          span: PanelSpan.large,
          child: GridPanel(
            title: 'Busiest rooms',
            child: d.busiestRooms.isEmpty
                ? const _Empty('No rooms are timetabled.')
                : BarList(data: d.busiestRooms, maxRows: 6),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.large,
          child: GridPanel(
            title: 'Recently joined',
            actions: const [_SeeAll(to: '/admin/users')],
            child: _RecentJoiners(rows: d.recent),
          ),
        ),

        ConsolePanel(
          span: PanelSpan.stat,
          child: GridFigure(
            label: 'Teachers timetabled',
            value: '${d.routineTeachers}',
            note: 'named on the routine',
            icon: Icons.school_rounded,
            accent: ChartPalette.series(context, 1),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.stat,
          child: GridFigure(
            label: 'Clubs',
            value: '${d.clubs}',
            note: 'student societies',
            icon: Icons.groups_2_rounded,
            accent: ChartPalette.series(context, 2),
            onTap: () => context.push('/clubs'),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.stat,
          child: GridFigure(
            label: 'Transport',
            value: '${d.routes}',
            note: '${_grouped(d.stops)} stops served',
            icon: Icons.directions_bus_rounded,
            accent: ChartPalette.series(context, 3),
            onTap: () => context.push('/transport'),
          ),
        ),
        ConsolePanel(
          span: PanelSpan.stat,
          child: GridFigure(
            label: 'Library',
            value: '${d.books}',
            note: 'titles catalogued',
            icon: Icons.menu_book_rounded,
            accent: ChartPalette.series(context, 0),
            onTap: () => context.push('/library'),
          ),
        ),
      ]),
    );
  }
}

/// A ring with its legend underneath, sized for a grid cell.
class _RingPanel extends StatelessWidget {
  final String title;
  final String centerValue;
  final String centerLabel;
  final List<RingSlice> slices;
  final String? empty;

  const _RingPanel({
    required this.title,
    required this.centerValue,
    required this.centerLabel,
    required this.slices,
    this.empty,
  });

  @override
  Widget build(BuildContext context) {
    return GridPanel(
      title: title,
      child: empty != null
          ? _Empty(empty!)
          : Column(children: [
              Expanded(
                child: RingChart(
                  slices: slices,
                  centerValue: centerValue,
                  centerLabel: centerLabel,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              ChartLegend(slices: slices, format: (n) => _grouped(n.toInt())),
            ]),
    );
  }
}

class _SeeAll extends StatelessWidget {
  final String to;
  const _SeeAll({required this.to});

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: () => context.push(to),
        child: Text('See all',
            style: TextStyle(color: ChartPalette.series(context, 0))),
      );
}

/// The honest state for a panel whose table is empty.
///
/// A panel keeps its box on the grid rather than disappearing, so the layout is
/// final on the first frame and stays final the day the data arrives. What it
/// must never do is draw a chart over nothing.
class _Empty extends StatelessWidget {
  final String message;
  const _Empty(this.message);

  @override
  Widget build(BuildContext context) => Center(
        child: Text(message,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondaryOf(context))),
      );
}

/// Thousands separator. Uses intl directly rather than adding a second number
/// helper beside AppFormatters — 2800 beds reads as 2,800 or the eye has to
/// count digits.
String _grouped(int n) => NumberFormat.decimalPattern().format(n);

/// The exam schedule, as the reference's subject / class / date / status table.
///
/// TITLED "Exam schedule", NOT "Upcoming exams". The reference says upcoming,
/// and copying that label would have produced an empty panel: all 38 exams in
/// this project are in the past. A panel whose honest state is "nothing here"
/// on a console that has real data to show is a worse import than a renamed
/// one, so this shows the schedule newest-first and lets the pill say which
/// side of today each row falls on.
class _ExamSchedule extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _ExamSchedule({required this.rows});

  @override
  Widget build(BuildContext context) {
    final secondary = AppColors.textSecondaryOf(context);
    // NO PANEL OF ITS OWN ANY MORE — GridPanel supplies the chrome and the
    // "See all" now points at /manage-exam-seats from the caller. This returns
    // only the content, and it SCROLLS: the grid gives the panel a fixed box,
    // so a sixth row must scroll inside it rather than overflow out of it.
    if (rows.isEmpty) {
      return Center(
        child: Text('No exams have been scheduled yet.',
            style: AppTextStyles.bodyMedium.copyWith(color: secondary)),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      separatorBuilder: (_, __) =>
          Divider(height: AppSpace.lg, color: AppColors.borderOf(context)),
      itemBuilder: (_, i) => _ExamRow(row: rows[i]),
    );
  }
}

class _ExamRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _ExamRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final secondary = AppColors.textSecondaryOf(context);
    final date = DateTime.tryParse('${row['exam_date']}');
    final retake = row['is_retake'] == true;

    // Retake outranks the date, because it changes who the row is ABOUT — a
    // retake sitting is a different population from the cohort's main exam,
    // and that is exactly the distinction that made batch 'RE' rows invisible
    // to every student once before.
    final (pillText, pillColor) = retake
        ? ('Retake', AppColors.holoviolet)
        : date == null
            ? ('Undated', AppColors.amber)
            : date.isBefore(DateTime.now())
                ? ('Completed', AppColors.textSecondaryOf(context))
                : ('Scheduled', AppColors.holoBlue);

    final where = [
      if ('${row['batch'] ?? ''}'.isNotEmpty) 'Batch ${row['batch']}',
      if ('${row['section'] ?? ''}'.isNotEmpty) 'Sec ${row['section']}',
      if ('${row['room'] ?? ''}'.isNotEmpty) 'Room ${row['room']}',
    ].join(' · ');

    return Row(children: [
      Expanded(
        flex: 3,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${row['subject'] ?? row['subject_code'] ?? 'Untitled'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleMedium
                  .copyWith(color: AppColors.textPrimaryOf(context))),
          if (where.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(where,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSmall.copyWith(color: secondary)),
          ],
        ]),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        flex: 2,
        child: Text(
          date == null ? '—' : AppFormatters.date(date),
          textAlign: TextAlign.end,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          // Tabular so a column of dates lines up rather than shimmering.
          style: AppTextStyles.numericSmall.copyWith(color: secondary),
        ),
      ),
      const SizedBox(width: AppSpace.sm),
      _Pill(text: pillText, color: pillColor),
    ]);
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsetsDirectional.fromSTEB(
            AppSpace.sm, AppSpace.xs, AppSpace.sm, AppSpace.xs),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: AppDepth.radius(3),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(text,
            style: AppTextStyles.labelSmall
                .copyWith(color: color, fontWeight: FontWeight.w600)),
      );
}

/// The most recent joiners, with how each one proved who they are.
///
/// identity_source is the column worth surfacing: 'diu_email' means a mailbox
/// was proven by code, 'admin_override' means a named person vouched instead,
/// and 'self' is a legacy account from before either existed. That distinction
/// is the whole point of the verification work and had no reader anywhere.
class _RecentJoiners extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _RecentJoiners({required this.rows});

  @override
  Widget build(BuildContext context) {
    final secondary = AppColors.textSecondaryOf(context);
    // Content only; GridPanel owns the title and the "See all". Scrolls inside
    // its fixed box for the same reason the exam list does.
    if (rows.isEmpty) {
      return Center(
        child: Text('Nobody has registered yet.',
            style: AppTextStyles.bodyMedium.copyWith(color: secondary)),
      );
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: rows.length,
      separatorBuilder: (_, __) =>
          Divider(height: AppSpace.lg, color: AppColors.borderOf(context)),
      itemBuilder: (_, i) => _JoinerRow(row: rows[i]),
    );
  }
}

class _JoinerRow extends StatelessWidget {
  final Map<String, dynamic> row;
  const _JoinerRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final secondary = AppColors.textSecondaryOf(context);
    final verified = row['is_verified'] == true;
    final source = '${row['identity_source'] ?? 'self'}';

    // Text first, colour second. A pill that says only "green" tells a
    // colour-blind reader nothing, and this one carries an authorisation fact.
    final (pillText, pillColor) = switch ((verified, source)) {
      (false, _) => ('Awaiting approval', AppColors.amber),
      (true, 'diu_email') => ('Email proven', AppColors.holoTeal),
      (true, 'admin_override') => ('Approved by admin', AppColors.holoviolet),
      _ => ('Active', AppColors.holoBlue),
    };

    final created = DateTime.tryParse('${row['created_at']}');

    return Row(children: [
      Expanded(
        flex: 3,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${row['full_name'] ?? 'Unnamed'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleMedium
                  .copyWith(color: AppColors.textPrimaryOf(context))),
          const SizedBox(height: 2),
          Text(
            [
              roleLabel('${row['role']}'),
              if ((row['university_id'] ?? '').toString().isNotEmpty)
                '${row['university_id']}',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall.copyWith(color: secondary),
          ),
        ]),
      ),
      const SizedBox(width: AppSpace.sm),
      Expanded(
        flex: 2,
        child: Text(
          created == null ? '—' : AppFormatters.relativeTime(created),
          textAlign: TextAlign.end,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.labelSmall.copyWith(color: secondary),
        ),
      ),
      const SizedBox(width: AppSpace.sm),
      // Was a byte-for-byte copy of _Pill, sixty lines above it. Two copies of
      // one pill is how the two of them drift apart.
      _Pill(text: pillText, color: pillColor),
    ]);
  }
}
