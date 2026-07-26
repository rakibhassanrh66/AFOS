import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/info_card.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/attendance_repository.dart';
import 'attendance_register_screen.dart';

/// Teacher-facing attendance.
///
/// A theory course is taken for the whole section; a lab is taken one group at
/// a time, so the group selector only appears for labs. Group labels are
/// batch+section+subgroup (batch 63 section M gives 63M1 and 63M2).
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});
  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  final _repo = AttendanceRepository();
  late final TabController _tab = TabController(length: 2, vsync: this);

  List<Map<String, dynamic>> _offerings = [];
  Map<String, dynamic>? _selected;
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _roster = [];
  Map<String, Map<String, int>> _sessionCounts = {};
  Map<String, Map<String, num>> _summary = {};
  int? _labGroup;
  bool _loading = true, _loadingDetail = false;
  String? _error;

  bool get _isLab => _selected != null && AttendanceRepository.isLab(_selected!);

  @override
  void initState() {
    super.initState();
    _loadOfferings();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _loadOfferings() async {
    setState(() { _loading = true; _error = null; });
    try {
      final offerings = await _repo.fetchMyOfferings();
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
      final sessions = await _repo.fetchSessions(id);
      final results = await Future.wait([
        _repo.fetchRoster(id),
        _repo.fetchSessionCounts(sessions.map((s) => s['id'] as String).toList()),
        _repo.fetchSummary(id),
      ]);
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _roster = results[0] as List<Map<String, dynamic>>;
        _sessionCounts = results[1] as Map<String, Map<String, int>>;
        _summary = results[2] as Map<String, Map<String, num>>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loadingDetail = false);
  }

  void _selectOffering(Map<String, dynamic> offering) {
    setState(() {
      _selected = offering;
      _labGroup = null;
      _sessions = [];
      _roster = [];
      _sessionCounts = {};
      _summary = {};
    });
    _loadDetail();
  }

  int get _ungroupedCount =>
      _roster.where((r) => r['lab_subgroup'] == null).length;

  Future<void> _splitLabGroups() async {
    final offering = _selected;
    if (offering == null) return;
    try {
      final n = await _repo.assignLabGroups(offering['id'] as String);
      await _loadDetail();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(n == 0
                ? 'Everyone is already in a group'
                : 'Split $n students into two lab groups'),
            backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _openRegister(Map<String, dynamic> session) async {
    final offering = _selected;
    if (offering == null) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            AttendanceRegisterScreen(offering: offering, session: session)));
    await _loadDetail();
  }

  Future<void> _takeAttendance() async {
    final offering = _selected;
    if (offering == null) return;

    // A lab register is per group, so there is no sensible "both groups at
    // once" session — make the teacher pick before anything is created.
    if (_isLab && _labGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Pick a lab group first'), backgroundColor: AppColors.amber));
      return;
    }

    final created = await showGlassSheet<Map<String, dynamic>>(
      context,
      child: _NewSessionForm(
        repo: _repo,
        offering: offering,
        labSubgroup: _isLab ? _labGroup : null,
      ),
    );
    if (created == null) return;
    await _loadDetail();
    if (mounted) await _openRegister(created);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Attendance'),
      floatingActionButton: _selected == null
          ? null
          : FloatingActionButton.extended(
              onPressed: _takeAttendance,
              backgroundColor: AppColors.blue,
              icon: const Icon(Icons.how_to_reg_rounded, color: Colors.white),
              label: const Text('Take Attendance',
                  style: TextStyle(color: Colors.white)),
            ),
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
                      icon: Icons.how_to_reg_outlined,
                      title: 'No approved courses',
                      subtitle:
                          'Attendance opens once an admin approves one of your course offerings')
                  : _content(),
    );
  }

  Widget _content() {
    final course = _selected?['courses'] as Map<String, dynamic>? ?? const {};
    final group = labGroupLabel(
        _selected?['batch'] as String?, _selected?['section'] as String?, _labGroup);

    return Column(children: [
      FeatureHeader(
        title: (course['code'] as String?) ?? 'Attendance',
        subtitle: '${course['title'] ?? ''} · $group'
            '${_isLab ? ' · Lab' : ' · Theory'}',
        icon: AppIcons.schedule,
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.blueLight, AppColors.blue]),
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.06, curve: Curves.easeOutCubic),

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
              final selected = o['id'] == _selected?['id'];
              return _Chip(
                label: '${c['code'] ?? ''} · ${o['section'] ?? ''}',
                selected: selected,
                onTap: () => _selectOffering(o),
              );
            },
          ),
        ),

      if (_isLab) ...[
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (final g in [1, 2])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _Chip(
                  label: labGroupLabel(_selected?['batch'] as String?,
                      _selected?['section'] as String?, g),
                  selected: _labGroup == g,
                  onTap: () => setState(() => _labGroup = _labGroup == g ? null : g),
                ),
              ),
            const Spacer(),
            if (_ungroupedCount > 0)
              TextButton.icon(
                onPressed: _splitLabGroups,
                icon: const Icon(Icons.call_split_rounded, size: 17),
                label: Text('Split $_ungroupedCount'),
              ),
          ]),
        ),
      ],

      const SizedBox(height: 10),
      AnimatedBuilder(
        animation: _tab,
        builder: (ctx, _) => GlassTabBar(
          currentIndex: _tab.index,
          onChanged: (i) => setState(() => _tab.animateTo(i)),
          tabs: [
            GlassTab(_sessions.isEmpty ? 'Sessions' : 'Sessions (${_sessions.length})',
                icon: Icons.event_note_rounded),
            const GlassTab('Students', icon: Icons.groups_rounded),
          ],
        ),
      ),
      const SizedBox(height: 10),
      Expanded(
        child: TabBarView(controller: _tab, children: [
          RefreshIndicator(onRefresh: _loadDetail, child: _sessionsTab()),
          RefreshIndicator(onRefresh: _loadDetail, child: _studentsTab()),
        ]),
      ),
    ]);
  }

  Widget _sessionsTab() {
    if (_loadingDetail) {
      return const Padding(
          padding: EdgeInsets.all(16),
          child: Column(children: [
            ShimmerCard(height: 64), SizedBox(height: 10), ShimmerCard(height: 64),
          ]));
    }
    final visible = _labGroup == null
        ? _sessions
        : _sessions.where((s) => s['lab_subgroup'] == _labGroup).toList();

    if (visible.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 40),
        EmptyState(
            icon: Icons.event_note_outlined,
            title: 'No attendance taken yet',
            subtitle: 'Tap "Take Attendance" to start today\'s register'),
      ]);
    }
    return ListView.builder(
      padding: NavInsets.content(context, top: 0, fab: true),
      itemCount: visible.length,
      itemBuilder: (ctx, i) {
        final s = visible[i];
        final counts = _sessionCounts[s['id']] ?? const {'attended': 0, 'total': 0};
        final attended = counts['attended'] ?? 0;
        final total = counts['total'] ?? 0;
        final pct = total <= 0 ? 0.0 : attended / total;
        final sub = s['lab_subgroup'] as int?;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InfoCard(
            accent: pct >= 0.75 ? AppColors.green : AppColors.amber,
            stripe: true,
            onTap: () => _openRegister(s),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['session_date'] as String? ?? '',
                      style: AppTextStyles.titleMedium
                          .copyWith(color: AppColors.textPrimaryOf(ctx))),
                  if ((s['topic'] as String?)?.trim().isNotEmpty == true)
                    Text(s['topic'] as String,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.textSecondaryOf(ctx))),
                ]),
              ),
              if (sub != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PillBadge(
                      label: labGroupLabel(_selected?['batch'] as String?,
                          _selected?['section'] as String?, sub),
                      color: AppColors.purple),
                ),
              Text('$attended/$total',
                  style: AppTextStyles.titleMedium.copyWith(
                      color: pct >= 0.75 ? AppColors.green : AppColors.amber)),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.textSecondaryOf(ctx), size: 20),
            ]),
          ),
        ).animate(delay: Duration(milliseconds: i * 45)).fadeIn().slideY(begin: 0.05);
      },
    );
  }

  Widget _studentsTab() {
    if (_loadingDetail) {
      return const Padding(
          padding: EdgeInsets.all(16),
          child: Column(children: [
            ShimmerCard(height: 56), SizedBox(height: 10), ShimmerCard(height: 56),
          ]));
    }
    final visible = _labGroup == null
        ? _roster
        : _roster.where((r) => r['lab_subgroup'] == _labGroup).toList();

    if (visible.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 40),
        EmptyState(
            icon: Icons.groups_outlined,
            title: 'No students yet',
            subtitle: 'Approved students on this course appear here'),
      ]);
    }
    return ListView.builder(
      padding: NavInsets.content(context, top: 0, fab: true),
      itemCount: visible.length,
      itemBuilder: (ctx, i) {
        final e = visible[i];
        final p = e['profiles'] as Map<String, dynamic>? ?? const {};
        final sid = e['student_id'] as String? ?? '';
        final tally = _summary[sid];
        final pct = (tally?['percent'] ?? 0).toDouble();
        final sessions = (tally?['sessions'] ?? 0).toInt();
        final bonus = (tally?['bonus'] ?? 0).toDouble();
        final sub = e['lab_subgroup'] as int?;
        // Below 75% is the number that actually costs a student marks, so it
        // is the one the colour has to call out.
        final color = sessions == 0
            ? AppColors.textSecondaryOf(ctx)
            : pct >= 75
                ? AppColors.green
                : AppColors.red;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InfoCard(
            accent: color,
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['full_name'] as String? ?? 'Student',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium
                          .copyWith(color: AppColors.textPrimaryOf(ctx))),
                  Text(
                      sessions == 0
                          ? 'No sessions yet'
                          : '$sessions session${sessions == 1 ? '' : 's'}'
                              '${bonus > 0 ? ' · +${bonus.toStringAsFixed(bonus % 1 == 0 ? 0 : 1)} bonus' : ''}',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondaryOf(ctx))),
                ]),
              ),
              if (_isLab)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PillBadge(
                      label: sub == null
                          ? 'No group'
                          : labGroupLabel(_selected?['batch'] as String?,
                              _selected?['section'] as String?, sub),
                      color: sub == null ? AppColors.amber : AppColors.purple),
                ),
              Text(sessions == 0 ? '—' : '${pct.toStringAsFixed(0)}%',
                  style: AppTextStyles.titleMedium.copyWith(color: color)),
            ]),
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: LiquidGlass.motionFast,
          curve: LiquidGlass.motionCurve,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.blue.withValues(alpha: selected ? 0.9 : 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: AppColors.blue.withValues(alpha: selected ? 1 : 0.3), width: 0.8),
          ),
          child: Text(label,
              textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
              style: TextStyle(
                  color: selected ? Colors.white : AppColors.blue,
                  fontSize: 12, height: 1.0, fontWeight: FontWeight.w700)),
        ),
      );
}

/// Date + optional topic for a new register. Pops the created session row so
/// the caller can go straight into taking the roll.
class _NewSessionForm extends StatefulWidget {
  final AttendanceRepository repo;
  final Map<String, dynamic> offering;
  final int? labSubgroup;
  const _NewSessionForm({
    required this.repo,
    required this.offering,
    required this.labSubgroup,
  });
  @override
  State<_NewSessionForm> createState() => _NewSessionFormState();
}

class _NewSessionFormState extends State<_NewSessionForm> {
  final _topicCtrl = TextEditingController();
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _topicCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      // Backdating is allowed (a register written up after class), but a
      // future register would be a record of something that hasn't happened.
      firstDate: DateTime.now().subtract(const Duration(days: 180)),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    try {
      final roster = await widget.repo.fetchRoster(
          widget.offering['id'] as String,
          labSubgroup: widget.labSubgroup);
      final sessionId = await widget.repo.createSession(
        offeringId: widget.offering['id'] as String,
        date: _date,
        labSubgroup: widget.labSubgroup,
        topic: _topicCtrl.text,
        studentIds: [
          for (final r in roster)
            if (r['student_id'] != null) r['student_id'] as String,
        ],
      );
      if (mounted) {
        Navigator.pop(context, {
          'id': sessionId,
          'session_date': AttendanceRepository.dateOnly(_date),
          'lab_subgroup': widget.labSubgroup,
          'topic': _topicCtrl.text.trim(),
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final group = labGroupLabel(widget.offering['batch'] as String?,
        widget.offering['section'] as String?, widget.labSubgroup);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Take Attendance',
                style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
            const SizedBox(height: 4),
            Text('Everyone starts marked present — change only the ones who '
                'were not there.',
                style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
                  border: Border.all(
                      color: AppColors.blue.withValues(alpha: 0.25), width: 0.5),
                ),
                child: Row(children: [
                  const Icon(Icons.event_rounded, size: 18, color: AppColors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(AttendanceRepository.dateOnly(_date),
                        style: AppTextStyles.bodyMedium.copyWith(color: textPrimary)),
                  ),
                  Text('Change',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.blue)),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            AfosTextField(hint: 'Topic (optional)', controller: _topicCtrl),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.groups_2_outlined, size: 16, color: AppColors.purple),
              const SizedBox(width: 8),
              Text('Register for $group',
                  style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
            ]),
            const SizedBox(height: 18),
            AfosButton(label: 'Start Register', loading: _saving, onTap: _submit),
          ]),
    );
  }
}
