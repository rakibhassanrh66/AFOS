import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../config/theme/motion.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../attendance/data/repositories/attendance_repository.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/marks_repository.dart';

/// Colour for a letter grade, by band rather than by exact letter so a scale
/// change doesn't leave an unmapped grade rendering grey.
Color gradeColor(String? letter) {
  if (letter == null) return AppColors.textSecondary;
  if (letter == 'F') return AppColors.red;
  if (letter.startsWith('A')) return AppColors.green;
  if (letter.startsWith('B')) return AppColors.blue;
  if (letter.startsWith('C')) return AppColors.amber;
  return AppColors.orange;
}

/// Teacher-facing mark entry against the DIU distribution.
///
/// Theory is Final 40 / Mid 25 / Quiz 15 / Presentation 8 / Attendance 7 /
/// Assignment 5; lab is Project 40 / Viva 25 / Daily Report 25 / Attendance 10.
/// The component list and its caps come from the database, which enforces that
/// each set totals exactly 100 — they are never hardcoded here.
class MarksEntryScreen extends StatefulWidget {
  const MarksEntryScreen({super.key});
  @override
  State<MarksEntryScreen> createState() => _MarksEntryScreenState();
}

class _MarksEntryScreenState extends State<MarksEntryScreen> {
  final _repo = MarksRepository();
  final _attendance = AttendanceRepository();

  List<Map<String, dynamic>> _offerings = [];
  Map<String, dynamic>? _selected;
  List<Map<String, dynamic>> _components = [];
  List<Map<String, dynamic>> _roster = [];
  Map<String, Map<String, double>> _marks = {};
  Map<String, Map<String, dynamic>> _totals = {};
  Map<String, dynamic>? _submission;
  String? _expanded;
  bool _loading = true, _loadingDetail = false, _busy = false;
  String? _error;

  String get _courseType =>
      (_selected?['courses'] as Map<String, dynamic>?)?['course_type'] as String? ?? 'theory';

  bool get _locked => _submission?['status'] == 'approved';

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  Future<void> _loadOfferings() async {
    setState(() { _loading = true; _error = null; });
    try {
      final offerings = await _attendance.fetchMyOfferings();
      if (!mounted) return;
      setState(() {
        _offerings = offerings;
        _selected = offerings.isNotEmpty ? offerings.first : null;
        _loading = false;
      });
      if (_selected != null) await _loadDetail();
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _loadDetail() async {
    final offering = _selected;
    if (offering == null) return;
    setState(() { _loadingDetail = true; _error = null; });
    try {
      final id = offering['id'] as String;
      // All four are independent of each other, so they go out together —
      // this was three sequential trips before, and opening a class is the
      // screen's slowest moment on a phone connection.
      // Record `.wait` rather than Future.wait's list: fetchOfferingMarks
      // returns a record, which a List<Object?> cannot carry without an
      // untyped cast, and this keeps every element's static type intact.
      final (components, data, totals, submission) = await (
        _repo.fetchComponents(_courseType),
        _repo.fetchOfferingMarks(id),
        _repo.fetchTotals(id),
        _repo.fetchSubmission(id),
      ).wait;
      if (!mounted) return;
      setState(() {
        _components = components;
        _roster = data.roster;
        _marks = data.marks;
        _totals = totals;
        _submission = submission;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loadingDetail = false);
  }

  Future<void> _saveMark(String enrollmentId, String componentId, double value) async {
    final previous = _marks[enrollmentId]?[componentId];
    setState(() => _marks.putIfAbsent(enrollmentId, () => {})[componentId] = value);
    try {
      await _repo.upsertMark(
          enrollmentId: enrollmentId, componentId: componentId, marks: value);
      // Totals are derived by the view, so they must be re-read rather than
      // added up locally — that is the whole point of not duplicating the
      // grading rules on the client.
      final totals = await _repo.fetchTotals(_selected!['id'] as String);
      if (mounted) setState(() => _totals = totals);
    } catch (e) {
      if (mounted) {
        setState(() {
          if (previous == null) {
            _marks[enrollmentId]?.remove(componentId);
          } else {
            _marks[enrollmentId]![componentId] = previous;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _syncAttendance() async {
    setState(() => _busy = true);
    try {
      final n = await _repo.syncAttendanceMarks(_selected!['id'] as String);
      await _loadDetail();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Attendance marks filled for $n student'
                '${n == 1 ? '' : 's'}'),
            backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _submit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Send results for approval?'),
        content: Text(
            'All ${_roster.length} students\' marks go to the admin for review. '
            'Students see nothing until it is approved, and you can keep '
            'editing while it is still pending.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _repo.submitResults(_selected!['id'] as String);
      await _loadDetail();
      if (mounted) {
        AppHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Sent for approval'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Marks'),
      body: _error != null && _offerings.isEmpty
          ? ErrorView(message: _error!, onRetry: _loadOfferings)
          : _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(children: [
                    ShimmerCard(height: 90), SizedBox(height: 12),
                    ShimmerCard(height: 64), SizedBox(height: 12),
                    ShimmerCard(height: 64),
                  ]))
              : _offerings.isEmpty
                  ? const EmptyState(
                      icon: Icons.grade_outlined,
                      title: 'No approved courses',
                      subtitle: 'Marks open once an admin approves one of your offerings')
                  : _content(),
    );
  }

  Widget _content() {
    final course = _selected?['courses'] as Map<String, dynamic>? ?? const {};
    final status = _submission?['status'] as String?;

    return Column(children: [
      FeatureHeader(
        title: (course['code'] as String?) ?? 'Marks',
        subtitle: '${course['title'] ?? ''} · '
            '${_courseType == 'lab' ? 'Lab' : 'Theory'} · ${_roster.length} students',
        icon: AppIcons.results,
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.gold, AppColors.orange]),
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      ).animate().fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
          .slideY(begin: -0.06, curve: AppMotion.standard),

      if (_offerings.length > 1)
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _offerings.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final o = _offerings[i];
              final c = o['courses'] as Map<String, dynamic>? ?? const {};
              final sel = o['id'] == _selected?['id'];
              return GestureDetector(
                onTap: () {
                  AppHaptics.selection();
                  setState(() {
                    _selected = o;
                    _roster = []; _marks = {}; _totals = {};
                    _submission = null; _expanded = null;
                  });
                  _loadDetail();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: sel ? 0.9 : 0.1),
                    borderRadius: AppDepth.radius(1),
                    border: Border.all(
                        color: AppColors.gold.withValues(alpha: sel ? 1 : 0.3), width: 0.8),
                  ),
                  child: Text('${c['code'] ?? ''} · ${o['section'] ?? ''}',
                      textHeightBehavior: const TextHeightBehavior(
                          applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                      style: TextStyle(
                          color: sel ? Colors.white : AppColors.gold,
                          fontSize: 12, height: 1.0, fontWeight: FontWeight.w700)),
                ),
              );
            },
          ),
        ),

      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          if (status != null)
            PillBadge(
                label: status.toUpperCase(),
                color: status == 'approved'
                    ? AppColors.green
                    : status == 'rejected'
                        ? AppColors.red
                        : AppColors.amber),
          const Spacer(),
          TextButton.icon(
            onPressed: (_busy || _locked) ? null : _syncAttendance,
            icon: const Icon(Icons.sync_rounded, size: 17),
            label: const Text('Fill attendance'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: (_busy || _locked || _roster.isEmpty) ? null : _submit,
            style: FilledButton.styleFrom(backgroundColor: AppColors.green),
            child: Text(_locked ? 'Published' : 'Submit'),
          ),
        ]),
      ),

      if (_submission?['status'] == 'rejected' &&
          (_submission?['rejection_reason'] as String?)?.isNotEmpty == true)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
              border: Border.all(color: AppColors.red.withValues(alpha: 0.25), width: 0.5),
            ),
            child: Text('Returned by admin: ${_submission!['rejection_reason']}',
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.red)),
          ),
        ),

      Expanded(child: _rosterList()),
    ]);
  }

  Widget _rosterList() {
    if (_loadingDetail) {
      return const Padding(
          padding: EdgeInsets.all(16),
          child: Column(children: [
            ShimmerCard(height: 60), SizedBox(height: 10), ShimmerCard(height: 60),
          ]));
    }
    if (_roster.isEmpty) {
      return const EmptyState(
          icon: Icons.groups_outlined,
          title: 'No students enrolled',
          subtitle: 'Approved students on this course appear here');
    }
    return RefreshIndicator(
      onRefresh: _loadDetail,
      child: ListView.builder(
        padding: NavInsets.content(context, top: 0),
        itemCount: _roster.length,
        itemBuilder: (ctx, i) {
          final e = _roster[i];
          final eid = e['id'] as String;
          final p = e['profiles'] as Map<String, dynamic>? ?? const {};
          final total = _totals[eid];
          return _StudentMarksCard(
            name: p['full_name'] as String? ?? 'Student',
            universityId: p['university_id'] as String?,
            total: (total?['total'] as double?) ?? 0,
            letter: total?['letter'] as String?,
            components: _components,
            values: _marks[eid] ?? const {},
            expanded: _expanded == eid,
            locked: _locked,
            onToggle: () => setState(() => _expanded = _expanded == eid ? null : eid),
            onChanged: (componentId, value) => _saveMark(eid, componentId, value),
          );
        },
      ),
    );
  }
}

class _StudentMarksCard extends StatelessWidget {
  final String name;
  final String? universityId;
  final double total;
  final String? letter;
  final List<Map<String, dynamic>> components;
  final Map<String, double> values;
  final bool expanded, locked;
  final VoidCallback onToggle;
  final void Function(String componentId, double value) onChanged;

  const _StudentMarksCard({
    required this.name,
    required this.universityId,
    required this.total,
    required this.letter,
    required this.components,
    required this.values,
    required this.expanded,
    required this.locked,
    required this.onToggle,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = gradeColor(letter);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Column(children: [
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium
                          .copyWith(color: AppColors.textPrimaryOf(context))),
                  if (universityId?.isNotEmpty == true)
                    Text(universityId!,
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.textSecondaryOf(context))),
                ]),
              ),
              // Running total per student, recomputed as marks are typed, one
              // per roster row — it must not jitter and it must align.
              Text(total.toStringAsFixed(total % 1 == 0 ? 0 : 1),
                  style: AppTextStyles.numericLarge.copyWith(
                      fontSize: 18, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(width: 8),
              Flexible(child: PillBadge(label: letter ?? '—', color: color)),
              Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: AppColors.textSecondaryOf(context)),
            ]),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 13, 13),
            child: Column(children: [
              for (final c in components)
                _ComponentField(
                  label: c['label'] as String? ?? '',
                  max: ((c['max_marks'] as num?) ?? 0).toDouble(),
                  value: values[c['id'] as String] ?? 0,
                  // The attendance component is filled from the registers by
                  // "Fill attendance"; typing over it by hand would be
                  // overwritten on the next sync, so it is read-only.
                  readOnly: locked || (c['is_auto'] as bool? ?? false),
                  auto: c['is_auto'] as bool? ?? false,
                  onChanged: (v) => onChanged(c['id'] as String, v),
                ),
            ]),
          ),
      ]),
    );
  }
}

class _ComponentField extends StatefulWidget {
  final String label;
  final double max, value;
  final bool readOnly, auto;
  final ValueChanged<double> onChanged;
  const _ComponentField({
    required this.label,
    required this.max,
    required this.value,
    required this.readOnly,
    required this.auto,
    required this.onChanged,
  });
  @override
  State<_ComponentField> createState() => _ComponentFieldState();
}

class _ComponentFieldState extends State<_ComponentField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: _format(widget.value));
  final _focus = FocusNode();

  static String _format(double v) => v == 0 ? '' : v.toStringAsFixed(v % 1 == 0 ? 0 : 2);

  @override
  void initState() {
    super.initState();
    // Commit on blur rather than on every keystroke: a write per character
    // would be a round trip per digit and would reject "1" on the way to "15"
    // for a component capped at 8.
    _focus.addListener(() { if (!_focus.hasFocus) _commit(); });
  }

  @override
  void didUpdateWidget(covariant _ComponentField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focus.hasFocus) {
      _ctrl.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _commit() {
    final parsed = double.tryParse(_ctrl.text.trim());
    final value = (parsed ?? 0).clamp(0, widget.max).toDouble();
    _ctrl.text = _format(value);
    if (value != widget.value) widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final over = (double.tryParse(_ctrl.text.trim()) ?? 0) > widget.max;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(
          child: Row(children: [
            Flexible(
              child: Text(widget.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textPrimaryOf(context))),
            ),
            if (widget.auto)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.sync_rounded,
                    size: 13, color: AppColors.textSecondaryOf(context)),
              ),
          ]),
        ),
        SizedBox(
          width: 76,
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            readOnly: widget.readOnly,
            textAlign: TextAlign.center,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            onSubmitted: (_) => _commit(),
            // The whole point of this screen is a COLUMN of these fields, one
            // per student, each holding a number the teacher is typing. With
            // proportional figures a '1' is narrower than a '0', so the digits
            // shift under the caret as you type and no two rows line up.
            style: AppTextStyles.numericMedium.copyWith(
                color: over ? AppColors.red : AppColors.textPrimaryOf(context),
                fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              isDense: true,
              hintText: '0',
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              filled: true,
              fillColor: widget.readOnly
                  ? AppColors.textSecondaryOf(context).withValues(alpha: 0.06)
                  : AppColors.blue.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                  borderRadius: AppDepth.radius(0), borderSide: BorderSide.none),
            ),
          ),
        ),
        SizedBox(
          width: 42,
          child: Text('/ ${widget.max.toStringAsFixed(0)}',
              textAlign: TextAlign.right,
              style: AppTextStyles.numericSmall
                  .copyWith(fontWeight: FontWeight.w500, color: AppColors.textSecondaryOf(context))),
        ),
      ]),
    );
  }
}
