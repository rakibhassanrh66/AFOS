import 'package:flutter/material.dart';

import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/attendance_repository.dart';

/// A student's own attendance record. Read-only, by design.
///
/// The RLS policy for this (`student_read_own_attendance_records`) has existed
/// since attendance shipped, and nothing ever called it — a student could be
/// marked absent all term and had no way to find out until it reached their
/// Attendance component mark, by which point it is too late to query.
///
/// Read-only is deliberate and not a shortcut: attendance is the teacher's
/// record of what happened. A student who believes a mark is wrong should be
/// disputing it with the teacher, who can edit the register, rather than
/// editing it themselves.
class MyAttendanceScreen extends StatefulWidget {
  const MyAttendanceScreen({super.key});

  @override
  State<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends State<MyAttendanceScreen> {
  final _repo = AttendanceRepository();
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await _repo.fetchMyAttendance();
      if (mounted) setState(() => _records = rows);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Grouped by course, because "am I short on CSE221?" is the question this
  /// screen exists to answer — a flat chronological list of every class the
  /// student has ever attended answers nothing.
  Map<String, List<Map<String, dynamic>>> get _byCourse {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final r in _records) {
      final session = r['attendance_sessions'] as Map<String, dynamic>? ?? const {};
      final offering = session['course_offerings'] as Map<String, dynamic>? ?? const {};
      final course = offering['courses'] as Map<String, dynamic>? ?? const {};
      final key = (course['code'] as String?) ?? 'Other';
      (out[key] ??= []).add(r);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _byCourse;
    final courses = grouped.keys.toList()..sort();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'My Attendance'),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(children: [
                    ShimmerCard(height: 110), SizedBox(height: 12),
                    ShimmerCard(height: 110),
                  ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: NavInsets.content(context),
                    children: [
                      if (_records.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 40),
                          child: EmptyState(
                              icon: Icons.how_to_reg_outlined,
                              title: 'No attendance recorded yet',
                              subtitle:
                                  'Once your teacher takes a register for a course you are enrolled in, it appears here'),
                        )
                      else
                        for (final code in courses)
                          _CourseAttendance(code: code, records: grouped[code]!),
                    ],
                  ),
                ),
    );
  }
}

/// One course: the percentage that actually matters, then each class.
class _CourseAttendance extends StatelessWidget {
  final String code;
  final List<Map<String, dynamic>> records;
  const _CourseAttendance({required this.code, required this.records});

  @override
  Widget build(BuildContext context) {
    // Matches fetchSummary() and sync_attendance_marks() exactly: late counts
    // as attended, excused is excluded from the denominator entirely. If this
    // drifted from the server the student would be shown a percentage that
    // disagrees with the mark they are eventually given.
    var attended = 0, total = 0;
    num bonus = 0;
    for (final r in records) {
      final status = r['status'] as String? ?? 'present';
      bonus += (r['bonus'] as num?) ?? 0;
      if (status == 'excused') continue;
      total++;
      if (status == 'present' || status == 'late') attended++;
    }
    final pct = total == 0 ? 0.0 : attended / total;
    final short = total > 0 && pct < 0.75;
    final color = total == 0
        ? AppColors.textSecondaryOf(context)
        : short
            ? AppColors.red
            : AppColors.green;

    final first = records.first['attendance_sessions'] as Map<String, dynamic>? ?? const {};
    final offering = first['course_offerings'] as Map<String, dynamic>? ?? const {};
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final subgroup = (first['lab_subgroup'] as num?)?.toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$code — ${course['title'] ?? ''}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.textPrimaryOf(context))),
              Text(
                  subgroup == null
                      ? 'Batch ${offering['batch'] ?? ''} · Section ${offering['section'] ?? ''}'
                      : 'Lab group ${labGroupLabel(offering['batch'] as String?, offering['section'] as String?, subgroup)}',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textSecondaryOf(context))),
            ]),
          ),
          Flexible(
            child: PillBadge(
                label: total == 0 ? '—' : '${(pct * 100).round()}%',
                color: color),
          ),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: AppColors.textSecondaryOf(context).withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 6),
        Text(
            '$attended of $total counted'
            '${bonus > 0 ? ' · +$bonus bonus' : ''}'
            '${records.length > total ? ' · ${records.length - total} excused' : ''}',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context))),
        // Said plainly rather than left for the student to work out from a
        // percentage: below 75% is where the Attendance component starts
        // costing real marks.
        if (short) ...[
          const SizedBox(height: 6),
          Text('Below 75% — this reduces your Attendance marks. Speak to your teacher.',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.red)),
        ],
        const SizedBox(height: 10),
        for (final r in records) _AttendanceRow(record: r),
      ]),
    );
  }
}

class _AttendanceRow extends StatelessWidget {
  final Map<String, dynamic> record;
  const _AttendanceRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final session = record['attendance_sessions'] as Map<String, dynamic>? ?? const {};
    final date = DateTime.tryParse(session['session_date'] as String? ?? '');
    final status = record['status'] as String? ?? 'present';
    final bonus = (record['bonus'] as num?) ?? 0;

    final (label, color) = switch (status) {
      'present' => ('Present', AppColors.green),
      'late' => ('Late', AppColors.amber),
      'excused' => ('Excused', AppColors.blue),
      _ => ('Absent', AppColors.red),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(Icons.circle, size: 8, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              date == null ? '—' : AppFormatters.date(date),
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondaryOf(context))),
        ),
        if ((session['topic'] as String?)?.isNotEmpty == true)
          Expanded(
            flex: 2,
            child: Text(session['topic'] as String,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondaryOf(context))),
          ),
        if (bonus > 0)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text('+$bonus',
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.gold)),
          ),
        Text(label, style: AppTextStyles.labelSmall.copyWith(color: color)),
      ]),
    );
  }
}
