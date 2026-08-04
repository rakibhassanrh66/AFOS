import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/button_styles.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/marks_repository.dart';
import 'marks_entry_screen.dart';

const _publisherRoles = ['admin', 'dept_admin', 'super_admin', 'exam_controller'];

/// Results, dispatched by role.
///
/// Supersedes the old single-letter flow, which wrote a hand-picked
/// `grades.grade_letter` and never recorded a number at all. Grades are now
/// derived from the DIU component distribution and `grading_scale` in the
/// database, so a teacher enters marks and the letter follows.
class GradesScreen extends StatelessWidget {
  const GradesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final role = RoleSession.role;
    if (_publisherRoles.contains(role)) return const ResultApprovalScreen();
    if (role == 'teacher') return const MarksEntryScreen();
    return const StudentResultsScreen();
  }
}

// ---------------------------------------------------------------- student

/// A student's published results, with the credit-weighted CGPA on top.
class StudentResultsScreen extends StatefulWidget {
  const StudentResultsScreen({super.key});
  @override
  State<StudentResultsScreen> createState() => _StudentResultsScreenState();
}

class _StudentResultsScreenState extends State<StudentResultsScreen> {
  final _repo = MarksRepository();
  List<Map<String, dynamic>> _results = [];
  Map<String, Map<String, dynamic>> _labels = {};
  Map<String, dynamic>? _cgpa;
  /// semester -> SGPA, from `student_sgpa()`. Results are grouped under a
  /// per-semester header carrying this, which is how a DIU transcript reads and
  /// how students actually think about their record.
  Map<int, double> _sgpas = {};
  final Map<String, List<Map<String, dynamic>>> _breakdowns = {};
  String? _expanded;
  bool _loading = true;
  String? _error;

  /// Published results bucketed by the semester of their offering, newest
  /// first. The semester lives on `course_offerings`, not on
  /// `enrollment_results`, so it comes from the labels already fetched for
  /// course titles rather than from a second query.
  Map<int, List<Map<String, dynamic>>> get _bySemester {
    final out = <int, List<Map<String, dynamic>>>{};
    for (final r in _results) {
      final sem = (_labels[r['offering_id']]?['semester'] as num?)?.toInt() ?? 0;
      (out[sem] ??= []).add(r);
    }
    return out;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Three round-trips, not four. The CGPA depends on nothing this screen
      // fetches, so it rides along with the offering labels instead of waiting
      // behind them; only the SGPAs genuinely need the labels first, because
      // the semester lives on the offering rather than on the result row.
      final results = await _repo.fetchMyResults();
      final offeringIds = [for (final r in results) r['offering_id'] as String];
      final (labels, cgpa) = await (
        _repo.fetchOfferingLabels(offeringIds),
        _repo.fetchMyCgpa(),
      ).wait;
      final sgpas = await _repo.fetchMySemesterGpas([
        for (final r in results)
          (labels[r['offering_id']]?['semester'] as num?)?.toInt() ?? 0,
      ]);
      if (!mounted) return;
      setState(() {
        _results = results;
        _labels = labels;
        _cgpa = cgpa;
        _sgpas = sgpas;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _toggle(String enrollmentId) async {
    if (_expanded == enrollmentId) {
      setState(() => _expanded = null);
      return;
    }
    setState(() => _expanded = enrollmentId);
    if (_breakdowns.containsKey(enrollmentId)) return;
    try {
      final rows = await _repo.fetchMyBreakdown(enrollmentId);
      if (mounted) setState(() => _breakdowns[enrollmentId] = rows);
    } catch (_) {
      // A failed breakdown must not take the whole result list down with it —
      // the grade itself is already on screen and is the thing that matters.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'My Results'),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(children: [
                    ShimmerCard(height: 120), SizedBox(height: 12),
                    ShimmerCard(height: 70), SizedBox(height: 12),
                    ShimmerCard(height: 70),
                  ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: NavInsets.content(context),
                    children: [
                      _CgpaCard(cgpa: _cgpa)
                          .animate().fadeIn(duration: 300.ms)
                          .slideY(begin: -0.06, curve: Curves.easeOutCubic),
                      const SizedBox(height: 14),
                      if (_results.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 30),
                          child: EmptyState(
                              icon: Icons.assignment_turned_in_outlined,
                              title: 'No published results yet',
                              subtitle:
                                  'A result appears here once your teacher submits it and the admin approves it'),
                        )
                      else
                        // Grouped by semester, newest first, each group headed
                        // by its own SGPA. A flat list gave no sense of how a
                        // particular term had gone, which is the comparison a
                        // student actually makes.
                        for (final sem in (_bySemester.keys.toList()..sort((a, b) => b.compareTo(a)))) ...[
                          _SemesterHeader(semester: sem, sgpa: _sgpas[sem]),
                          for (final r in _bySemester[sem]!) _resultCard(r),
                          const SizedBox(height: 6),
                        ],
                    ],
                  ),
                ),
    );
  }

  Widget _resultCard(Map<String, dynamic> r) {
    final eid = r['enrollment_id'] as String;
    final offering = _labels[r['offering_id']] ?? const {};
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final letter = r['letter_grade'] as String?;
    final color = gradeColor(letter);
    final total = ((r['total_marks'] as num?) ?? 0).toDouble();
    final gp = (r['grade_point'] as num?)?.toDouble();
    final credits = (r['credit_hours'] as num?)?.toDouble();
    final open = _expanded == eid;
    final breakdown = _breakdowns[eid];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => _toggle(eid),
          borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(course['title'] as String? ?? course['code'] as String? ?? '—',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium
                          .copyWith(color: AppColors.textPrimaryOf(context))),
                  Text([
                    course['code'] as String? ?? '',
                    if (credits != null) '${credits.toStringAsFixed(0)} cr',
                    if (gp != null) 'GP ${gp.toStringAsFixed(2)}',
                  ].where((s) => s.isNotEmpty).join(' · '),
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondaryOf(context))),
                ]),
              ),
              Text(total.toStringAsFixed(total % 1 == 0 ? 0 : 1),
                  style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.textSecondaryOf(context))),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [color, color.withValues(alpha: 0.65)]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(letter ?? '—',
                    textHeightBehavior: const TextHeightBehavior(
                        applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                    style: const TextStyle(
                        color: Colors.white, height: 1.0,
                        fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: AppColors.textSecondaryOf(context)),
            ]),
          ),
        ),
        if (open)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: breakdown == null
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(minHeight: 2))
                : Column(children: [
                    for (final row in breakdown)
                      _BreakdownRow(
                        label: (row['mark_components'] as Map?)?['label'] as String? ?? '',
                        marks: ((row['marks'] as num?) ?? 0).toDouble(),
                        max: (((row['mark_components'] as Map?)?['max_marks'] as num?) ?? 0)
                            .toDouble(),
                      ),
                  ]),
          ),
      ]),
    );
  }
}

/// Header above one semester's results, carrying that semester's own GPA.
class _SemesterHeader extends StatelessWidget {
  final int semester;
  final double? sgpa;
  const _SemesterHeader({required this.semester, required this.sgpa});

  @override
  Widget build(BuildContext context) {
    final v = sgpa;
    final color = v == null
        ? AppColors.textSecondaryOf(context)
        : v < 2.0
            ? AppColors.red
            : v >= 3.75
                ? AppColors.gold
                : AppColors.green;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(children: [
        Text(semester > 0 ? 'Semester $semester' : 'Other',
            style: AppTextStyles.titleMedium
                .copyWith(color: AppColors.textPrimaryOf(context))),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
              color: AppColors.borderOf(context), thickness: 0.5, height: 1),
        ),
        const SizedBox(width: 8),
        if (v != null)
          PillBadge(label: 'SGPA ${v.toStringAsFixed(2)}', color: color),
      ]),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final String label;
  final double marks, max;
  const _BreakdownRow({required this.label, required this.marks, required this.max});

  @override
  Widget build(BuildContext context) {
    final ratio = max <= 0 ? 0.0 : (marks / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          flex: 4,
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondaryOf(context))),
        ),
        Expanded(
          flex: 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 5,
              backgroundColor: AppColors.textSecondaryOf(context).withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(
                  ratio >= 0.5 ? AppColors.green : AppColors.amber),
            ),
          ),
        ),
        SizedBox(
          width: 66,
          child: Text(
              '${marks.toStringAsFixed(marks % 1 == 0 ? 0 : 1)} / ${max.toStringAsFixed(0)}',
              textAlign: TextAlign.right,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textPrimaryOf(context))),
        ),
      ]),
    );
  }
}

/// CGPA, standing and honours. Everything here is computed server-side by
/// `student_cgpa()` from the counting attempt of each course — a retake
/// replaces the earlier grade outright, per DIU policy.
class _CgpaCard extends StatelessWidget {
  final Map<String, dynamic>? cgpa;
  const _CgpaCard({required this.cgpa});

  @override
  Widget build(BuildContext context) {
    final value = (cgpa?['cgpa'] as num?)?.toDouble();
    final credits = (cgpa?['earned_credits'] as num?)?.toDouble() ?? 0;
    final standing = cgpa?['standing'] as String?;
    final honour = cgpa?['honour'] as String?;
    final hasF = cgpa?['has_f'] as bool? ?? false;
    final onProbation = standing == 'probation';

    final accent = value == null
        ? AppColors.textSecondaryOf(context)
        : onProbation
            ? AppColors.red
            : value >= 3.75
                ? AppColors.gold
                : AppColors.green;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0.06)]),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(value?.toStringAsFixed(2) ?? '—',
              style: TextStyle(
                  color: accent, fontSize: 42, height: 1.0, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Text('/ 4.00',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.textSecondaryOf(context))),
          ),
          const Spacer(),
          if (honour != null) PillBadge(label: honour, color: AppColors.gold),
        ]),
        const SizedBox(height: 8),
        Text(
            value == null
                ? 'No published results yet'
                : 'Cumulative GPA · ${credits.toStringAsFixed(0)} credits earned',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondaryOf(context))),
        // Probation and a standing F are the two states that actually change
        // what a student must do next, so neither is left to be inferred from
        // the number.
        if (onProbation) ...[
          const SizedBox(height: 10),
          const _Notice(
              color: AppColors.red,
              icon: Icons.warning_amber_rounded,
              text: 'Below the 2.00 minimum — you are on academic probation. '
                  'Three consecutive semesters below 2.00 means removal from the programme.'),
        ],
        if (hasF) ...[
          const SizedBox(height: 8),
          const _Notice(
              color: AppColors.amber,
              icon: Icons.error_outline_rounded,
              text: 'You have a standing F. The degree cannot be awarded until '
                  'it is cleared by repeating the course.'),
        ],
      ]),
    );
  }
}

class _Notice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Notice({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: AppTextStyles.labelSmall.copyWith(color: color)),
          ),
        ]),
      );
}

// ------------------------------------------------------------------ admin

/// Admin/exam-controller queue: approve a teacher's marks to release them.
class ResultApprovalScreen extends StatefulWidget {
  const ResultApprovalScreen({super.key});
  @override
  State<ResultApprovalScreen> createState() => _ResultApprovalScreenState();
}

class _ResultApprovalScreenState extends State<ResultApprovalScreen> {
  final _repo = MarksRepository();
  List<Map<String, dynamic>> _pending = [];
  final Set<String> _busy = {};
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
      final pending = await _repo.fetchPendingSubmissions();
      if (mounted) setState(() => _pending = pending);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _review(Map<String, dynamic> row, bool approve) async {
    final id = row['id'] as String;
    String? reason;
    if (!approve) {
      reason = await _askReason();
      if (reason == null) return;
    }
    setState(() => _busy.add(id));
    try {
      await _repo.reviewSubmission(
          submissionId: id, approve: approve, reason: reason);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(approve
                ? 'Results published — the class has been notified ✓'
                : 'Returned to the teacher'),
            backgroundColor: approve ? AppColors.green : AppColors.amber));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busy.remove(id));
  }

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Return to teacher'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
              hintText: 'What needs fixing? The teacher sees this.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(d, ctrl.text.trim()),
              child: const Text('Return')),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Publish Results'),
      body: Column(children: [
        FeatureHeader(
          title: 'Publish Results',
          subtitle: _loading
              ? 'Loading…'
              : '${_pending.length} course${_pending.length == 1 ? '' : 's'} waiting for review',
          icon: Icons.publish_rounded,
          gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.blue, AppColors.indigo]),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        ),
        Expanded(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _loading
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(children: [
                        ShimmerCard(height: 92), SizedBox(height: 10),
                        ShimmerCard(height: 92),
                      ]))
                  : _pending.isEmpty
                      ? const EmptyState(
                          icon: Icons.publish_outlined,
                          title: 'Nothing waiting to publish',
                          subtitle: 'Submitted results appear here for approval')
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: NavInsets.content(context, top: 0),
                            itemCount: _pending.length,
                            itemBuilder: (ctx, i) => _card(_pending[i]),
                          ),
                        ),
        ),
      ]),
    );
  }

  Widget _card(Map<String, dynamic> row) {
    final offering = row['course_offerings'] as Map<String, dynamic>? ?? const {};
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final teacher = offering['profiles'] as Map<String, dynamic>? ?? const {};
    final busy = _busy.contains(row['id']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${course['code'] ?? ''} — ${course['title'] ?? ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.textPrimaryOf(context))),
          ),
          Flexible(
            child: PillBadge(
                label:
                    (course['course_type'] as String? ?? 'theory').toUpperCase(),
                color: AppColors.purple),
          ),
        ]),
        const SizedBox(height: 4),
        Text(
            'Batch ${offering['batch'] ?? ''} · Section ${offering['section'] ?? ''}'
            ' · by ${teacher['full_name'] ?? 'Unknown'}',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 12),
        // Wrap + rowAction, not a bare Row: the theme gives OutlinedButton
        // `minimumSize: Size(double.infinity, 52)`, so 'Return' demanded the
        // whole row and pushed 'Approve & publish' off the right edge — the
        // reviewer could see the submission and could not publish it.
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
            onPressed: busy ? null : () => _review(row, false),
            style: rowAction(OutlinedButton.styleFrom(foregroundColor: AppColors.red)),
            child: const Text('Return', maxLines: 1),
          ),
          FilledButton(
            onPressed: busy ? null : () => _review(row, true),
            style: rowAction(FilledButton.styleFrom(backgroundColor: AppColors.green)),
            child: busy
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Approve & publish', maxLines: 1),
          ),
        ]),
      ]),
    );
  }
}
