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
  final List<Map<String, dynamic>> exams;
  final int beds;
  final int occupied;

  /// Set when the fetch threw. The overview then renders a single explanatory
  /// panel instead of figures, and the rest of the console is unaffected.
  final String? error;

  const AdminOverviewData({
    required this.facets,
    required this.recent,
    required this.stuck,
    required this.exams,
    required this.beds,
    required this.occupied,
    this.error,
  });

  const AdminOverviewData.failed(this.error)
      : facets = const {},
        recent = const [],
        stuck = 0,
        exams = const [],
        beds = 0,
        occupied = 0;

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
      ]);

      final facets = results[0];
      final halls = (results[4] as List).cast<Map<String, dynamic>>();
      return AdminOverviewData(
        facets: facets is Map ? Map<String, dynamic>.from(facets) : const {},
        recent: (results[1] as List).cast<Map<String, dynamic>>(),
        stuck: (results[2] as List).length,
        exams: (results[3] as List).cast<Map<String, dynamic>>(),
        beds: halls.fold<int>(
            0, (sum, h) => sum + ((h['capacity'] as num?)?.toInt() ?? 0)),
        occupied: (results[5] as List).length,
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

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      WebStatStrip(stats: [
        WebStat(
          label: 'People in AFOS',
          value: '${d.total}',
          icon: Icons.groups_rounded,
          accent: AppColors.holoBlue,
          note: 'across every role',
          onTap: () => context.push('/admin/users'),
        ),
        WebStat(
          label: 'Awaiting approval',
          value: '${d.pending}',
          icon: Icons.how_to_reg_rounded,
          accent: d.pending > 0 ? AppColors.amber : AppColors.holoTeal,
          // The note carries the meaning, not the colour — an amber tile with
          // no words is a puzzle to anyone who cannot see the difference.
          note: d.pending == 0 ? 'nothing waiting' : 'needs a decision',
          onTap: () => context.push('/admin/users'),
        ),
        WebStat(
          label: 'Code failed',
          value: '${d.stuck}',
          icon: Icons.mark_email_unread_rounded,
          accent: d.stuck > 0 ? AppColors.red : AppColors.holoTeal,
          note: d.stuck == 0 ? 'none stuck' : 'verification did not settle',
          onTap: () => context.push('/admin/users'),
        ),
      ]),
      const SizedBox(height: AppSpace.xl),

      // Population breakdown and recent joiners, side by side on a wide
      // window and stacked below it.
      LayoutBuilder(builder: (ctx, box) {
        final wide = box.maxWidth >= 900;
        final left = _RoleBreakdown(roles: d.roles, total: d.total);
        final right = _RecentJoiners(rows: d.recent);
        if (!wide) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            left,
            const SizedBox(height: AppSpace.lg),
            right,
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 2, child: left),
          const SizedBox(width: AppSpace.lg),
          Expanded(flex: 3, child: right),
        ]);
      }),
      const SizedBox(height: AppSpace.lg),

      // Exam schedule and hall occupancy — the two reference panels the first
      // pass dropped without checking whether the data existed. It did.
      LayoutBuilder(builder: (ctx, box) {
        final wide = box.maxWidth >= 900;
        final left = _ExamSchedule(rows: d.exams);
        final right = _HallOccupancy(beds: d.beds, occupied: d.occupied);
        if (!wide) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            left,
            const SizedBox(height: AppSpace.lg),
            right,
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: left),
          const SizedBox(width: AppSpace.lg),
          Expanded(flex: 2, child: right),
        ]);
      }),
      const SizedBox(height: AppSpace.xl),
    ]);
  }
}

/// Who is actually in the system, as labelled bars.
///
/// A donut was the obvious import from the reference, and was rejected: with
/// four categories where one holds most of the mass, a ring makes the small
/// slices unreadable and forces a colour-to-legend lookup for every value.
/// Bars put the label, the count and the share on the same line, so the chart
/// is legible in greyscale and to a screen reader — colour is decoration here,
/// never the carrier of meaning.
class _RoleBreakdown extends StatelessWidget {
  final List<Map<String, dynamic>> roles;
  final int total;
  const _RoleBreakdown({required this.roles, required this.total});

  static const _accents = [
    AppColors.holoBlue,
    AppColors.holoTeal,
    AppColors.holoviolet,
    AppColors.amber,
  ];

  @override
  Widget build(BuildContext context) {
    final sorted = [...roles]..sort((a, b) =>
        ((b['count'] as num?) ?? 0).compareTo((a['count'] as num?) ?? 0));
    final max = sorted.isEmpty
        ? 1
        : ((sorted.first['count'] as num?) ?? 1).toInt().clamp(1, 1 << 30);

    return WebPanel(
      title: 'Who is in AFOS',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (sorted.isEmpty)
          Text('No accounts yet.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondaryOf(context)))
        else
          for (var i = 0; i < sorted.length; i++) ...[
            _Bar(
              label: roleLabel('${sorted[i]['value']}'),
              count: ((sorted[i]['count'] as num?) ?? 0).toInt(),
              max: max,
              total: total,
              accent: _accents[i % _accents.length],
            ),
            if (i != sorted.length - 1) const SizedBox(height: AppSpace.md),
          ],
      ]),
    );
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final int count;
  final int max;
  final int total;
  final Color accent;
  const _Bar({
    required this.label,
    required this.count,
    required this.max,
    required this.total,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final share = total == 0 ? 0 : (count * 100 / total).round();
    return Semantics(
      label: '$label: $count of $total, $share percent',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textPrimaryOf(context))),
          ),
          const SizedBox(width: AppSpace.sm),
          Text('$count',
              style: AppTextStyles.numericMedium
                  .copyWith(color: AppColors.textPrimaryOf(context))),
          const SizedBox(width: AppSpace.xs),
          SizedBox(
            width: 44,
            child: Text('$share%',
                textAlign: TextAlign.end,
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondaryOf(context))),
          ),
        ]),
        const SizedBox(height: AppSpace.xs),
        ClipRRect(
          borderRadius: AppDepth.radius(0),
          child: LinearProgressIndicator(
            value: count / max,
            minHeight: 6,
            backgroundColor: AppColors.textSecondaryOf(context).withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(accent),
          ),
        ),
      ]),
    );
  }
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
    return WebPanel(
      title: 'Exam schedule',
      actions: [
        TextButton(
          // NOT /exam-seat — that is the student's own seat, and the router
          // blocks teachers from it outright (teacherHiddenRoutes). The
          // console's reader is an administrator, so this goes to the
          // management screen they can actually act on.
          onPressed: () => context.push('/manage-exam-seats'),
          child: const Text('See all', style: TextStyle(color: AppColors.holoBlue)),
        ),
      ],
      child: rows.isEmpty
          ? Text('No exams have been scheduled yet.',
              style: AppTextStyles.bodyMedium.copyWith(color: secondary))
          : Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                _ExamRow(row: rows[i]),
                if (i != rows.length - 1)
                  Divider(height: AppSpace.lg, color: AppColors.borderOf(context)),
              ],
            ]),
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

/// Hall occupancy, as the reference's ring with the total in the middle.
///
/// A DONUT IS DEFENSIBLE HERE and was not for the role split. This is two
/// mutually exclusive parts of one known whole, which is the one shape a ring
/// reads well; the role breakdown was four uneven categories, where a ring
/// forces a colour-to-legend lookup per value. Same reference, different
/// question, different mark.
///
/// It currently renders as very nearly a full "available" ring — 3 of 2800
/// beds. That is not a bug and is not padded to look busier: an almost-empty
/// hall system is the true state, and a chart that hid it would be worth less
/// than no chart.
class _HallOccupancy extends StatelessWidget {
  final int beds;
  final int occupied;
  const _HallOccupancy({required this.beds, required this.occupied});

  @override
  Widget build(BuildContext context) {
    final secondary = AppColors.textSecondaryOf(context);
    final available = (beds - occupied).clamp(0, beds);
    final pct = beds == 0 ? 0.0 : occupied / beds;

    return WebPanel(
      title: 'Hall occupancy',
      child: beds == 0
          ? Text('No halls are configured.',
              style: AppTextStyles.bodyMedium.copyWith(color: secondary))
          : Column(children: [
              SizedBox(
                height: 168,
                child: Center(
                  child: SizedBox(
                    width: 168,
                    height: 168,
                    child: CustomPaint(
                      painter: RingPainter(
                        fraction: pct,
                        filled: AppColors.holoBlue,
                        rest: AppColors.holoTeal,
                        track: AppColors.borderOf(context),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Total beds',
                                style: AppTextStyles.labelSmall
                                    .copyWith(color: secondary)),
                            const SizedBox(height: 2),
                            Text(_grouped(beds),
                                style: AppTextStyles.numericLarge.copyWith(
                                    color: AppColors.textPrimaryOf(context))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // The legend carries the NUMBERS, not just the colours, so the
              // panel is still readable when one slice is too thin to see —
              // which at 3/2800 it is.
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _LegendDot(color: AppColors.holoBlue, label: 'Occupied', value: occupied),
                const SizedBox(width: AppSpace.lg),
                _LegendDot(color: AppColors.holoTeal, label: 'Available', value: available),
              ]),
            ]),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final int value;
  const _LegendDot({required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: AppSpace.xs),
      Text('$label  ',
          style: AppTextStyles.labelSmall
              .copyWith(color: AppColors.textSecondaryOf(context))),
      Text(_grouped(value),
          style: AppTextStyles.numericSmall
              .copyWith(color: AppColors.textPrimaryOf(context))),
    ]);
  }
}

/// Two-part ring. Deliberately not a package: one arc pair does not justify a
/// charting dependency against a 2 MB budget, and the depth tokens already say
/// how thick and how rounded a stroke here should be.
class RingPainter extends CustomPainter {
  final double fraction;
  final Color filled;
  final Color rest;
  final Color track;
  const RingPainter({
    required this.fraction,
    required this.filled,
    required this.rest,
    required this.track,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 18.0;
    final rect = Offset.zero & size;
    final inner = rect.deflate(stroke / 2);

    Paint pen(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Track first so a zero-width slice still leaves a complete ring rather
    // than a gap that reads as missing data.
    canvas.drawArc(inner, 0, 6.28318, false, pen(track.withValues(alpha: 0.35)));
    // Available fills the remainder; occupied is drawn last so even a sliver
    // sits on top and stays visible.
    canvas.drawArc(inner, -1.5708 + 6.28318 * fraction,
        6.28318 * (1 - fraction), false, pen(rest));
    if (fraction > 0) {
      canvas.drawArc(inner, -1.5708, 6.28318 * fraction, false, pen(filled));
    }
  }

  // `track` IS COMPARED, and it is the one that actually changes.
  //
  // The first version compared fraction, filled and rest — but filled and rest
  // are the two compile-time constants here (holoBlue, holoTeal), while track
  // is AppColors.borderOf(context), which is theme-dependent. So the check was
  // exactly inverted: switching light/dark rebuilt the widget, made a new
  // painter, got `false` back, and left the ring wearing the previous theme's
  // track ring until something else forced a repaint.
  @override
  bool shouldRepaint(covariant RingPainter old) =>
      old.fraction != fraction ||
      old.filled != filled ||
      old.rest != rest ||
      old.track != track;
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
    return WebPanel(
      title: 'Recently joined',
      actions: [
        TextButton(
          onPressed: () => context.push('/admin/users'),
          child: const Text('See all', style: TextStyle(color: AppColors.holoBlue)),
        ),
      ],
      child: rows.isEmpty
          ? Text('Nobody has registered yet.',
              style: AppTextStyles.bodyMedium.copyWith(color: secondary))
          : Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                _JoinerRow(row: rows[i]),
                if (i != rows.length - 1)
                  Divider(height: AppSpace.lg, color: AppColors.borderOf(context)),
              ],
            ]),
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
