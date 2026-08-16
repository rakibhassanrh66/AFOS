import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../config/theme/motion.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/attendance_repository.dart';
import '../../web/presentation/widgets/adaptive_list.dart';

/// Colour and short label for each attendance state. One table so the register
/// row, the summary chips and the session cards can't drift apart on what
/// "late" looks like.
const _statusMeta = <String, ({String short, String label, Color color})>{
  'present': (short: 'P', label: 'Present', color: AppColors.green),
  'absent': (short: 'A', label: 'Absent', color: AppColors.red),
  'late': (short: 'L', label: 'Late', color: AppColors.amber),
  'excused': (short: 'E', label: 'Excused', color: AppColors.blue),
};

Color attendanceStatusColor(String status) =>
    _statusMeta[status]?.color ?? AppColors.blue;

/// Roll call for a single session.
///
/// Everything writes through immediately rather than collecting into a Save
/// button: a register is dozens of independent one-tap decisions, and losing
/// the lot to a backgrounded app halfway through a class would be far worse
/// than a few extra round trips.
class AttendanceRegisterScreen extends StatefulWidget {
  final Map<String, dynamic> offering;
  final Map<String, dynamic> session;
  const AttendanceRegisterScreen({
    super.key,
    required this.offering,
    required this.session,
  });

  @override
  State<AttendanceRegisterScreen> createState() => _AttendanceRegisterScreenState();
}

class _AttendanceRegisterScreenState extends State<AttendanceRegisterScreen> {
  final _repo = AttendanceRepository();

  List<Map<String, dynamic>> _roster = [];
  /// studentId -> record row.
  Map<String, Map<String, dynamic>> _records = {};
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  String get _sessionId => widget.session['id'] as String;
  int? get _labSubgroup => widget.session['lab_subgroup'] as int?;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _repo.fetchRoster(widget.offering['id'] as String, labSubgroup: _labSubgroup),
        _repo.fetchRecords(_sessionId),
      ]);
      if (!mounted) return;
      final roster = results[0];
      final records = results[1];
      setState(() {
        _roster = roster;
        _records = {
          for (final r in records) r['student_id'] as String: r,
        };
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _setStatus(String studentId, String status) async {
    final record = _records[studentId];
    if (record == null) return;
    final recordId = record['id'] as String;
    final previous = record['status'] as String?;
    // Optimistic: a register is tapped fast, and waiting for a round trip per
    // student makes the whole list feel stuck.
    setState(() {
      _records[studentId] = {...record, 'status': status};
      _busy.add(recordId);
    });
    try {
      await _repo.updateRecord(recordId, status: status);
    } catch (e) {
      if (mounted) {
        setState(() => _records[studentId] = {...record, 'status': previous});
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busy.remove(recordId));
  }

  Future<void> _setBonus(String studentId, double bonus) async {
    final record = _records[studentId];
    if (record == null) return;
    final recordId = record['id'] as String;
    final previous = record['bonus'];
    setState(() => _records[studentId] = {...record, 'bonus': bonus});
    try {
      await _repo.updateRecord(recordId, bonus: bonus);
    } catch (e) {
      if (mounted) {
        setState(() => _records[studentId] = {...record, 'bonus': previous});
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _markAll(String status) async {
    final before = {..._records};
    setState(() {
      _records = {
        for (final e in _records.entries) e.key: {...e.value, 'status': status},
      };
    });
    try {
      await _repo.setAllStatuses(_sessionId, status);
    } catch (e) {
      if (mounted) {
        setState(() => _records = before);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  int _countOf(String status) =>
      _records.values.where((r) => (r['status'] as String?) == status).length;

  @override
  Widget build(BuildContext context) {
    final course = widget.offering['courses'] as Map<String, dynamic>? ?? const {};
    final group = labGroupLabel(
        widget.offering['batch'] as String?,
        widget.offering['section'] as String?,
        _labSubgroup);
    final date = widget.session['session_date'] as String? ?? '';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: '${course['code'] ?? 'Attendance'} · $group'),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : Column(children: [
              _RegisterSummaryBar(
                date: date,
                topic: widget.session['topic'] as String?,
                present: _countOf('present'),
                late: _countOf('late'),
                absent: _countOf('absent'),
                excused: _countOf('excused'),
                total: _records.length,
              ),
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : () => _markAll('present'),
                      icon: const Icon(Icons.done_all_rounded, size: 17),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.green),
                      label: const Text('All present'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : () => _markAll('absent'),
                      icon: const Icon(Icons.remove_done_rounded, size: 17),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                      label: const Text('All absent'),
                    ),
                  ),
                ]),
              ),
              Expanded(child: _body()),
            ]),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Column(children: [
          ShimmerCard(height: 64), SizedBox(height: 10),
          ShimmerCard(height: 64), SizedBox(height: 10),
          ShimmerCard(height: 64),
        ]),
      );
    }
    if (_roster.isEmpty) {
      return const EmptyState(
        icon: Icons.groups_outlined,
        title: 'Nobody on this register',
        subtitle: 'No approved students in this group yet',
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: AdaptiveList(
        padding: NavInsets.content(context, top: 0),
        itemCount: _roster.length,
        itemBuilder: (ctx, i) {
          final enrolment = _roster[i];
          final profile = enrolment['profiles'] as Map<String, dynamic>? ?? const {};
          final studentId = enrolment['student_id'] as String? ?? '';
          final record = _records[studentId];
          return _RegisterRow(
            profile: profile,
            status: record?['status'] as String? ?? 'present',
            bonus: ((record?['bonus'] as num?) ?? 0).toDouble(),
            saving: _busy.contains(record?['id']),
            onStatus: (s) => _setStatus(studentId, s),
            onBonus: (b) => _setBonus(studentId, b),
          );
        },
      ),
    );
  }
}

/// At-a-glance state of the register: the four counts and a fill bar. The
/// count that matters mid-class is "how many are still marked present", which
/// a plain list of 50 rows does not give you.
class _RegisterSummaryBar extends StatelessWidget {
  final String date;
  final String? topic;
  final int present, late, absent, excused, total;
  const _RegisterSummaryBar({
    required this.date,
    required this.topic,
    required this.present,
    required this.late,
    required this.absent,
    required this.excused,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final attended = present + late;
    final counted = total - excused;
    final pct = counted <= 0 ? 0.0 : attended / counted;

    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppDepth.radius(2),
        border: Border.all(color: AppColors.glassBorder(context), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(date,
                  style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.textPrimaryOf(context))),
              if (topic?.trim().isNotEmpty == true)
                Text(topic!,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.textSecondaryOf(context))),
            ]),
          ),
          // Attended-over-counted, recomputed on every status tap.
          Text('$attended/${counted <= 0 ? 0 : counted}',
              style: AppTextStyles.numericLarge.copyWith(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: pct >= 0.75 ? AppColors.green : AppColors.amber)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          // A 6px bar — the pill rung.
          borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 6,
            backgroundColor: AppColors.red.withValues(alpha: 0.18),
            valueColor: AlwaysStoppedAnimation(
                pct >= 0.75 ? AppColors.green : AppColors.amber),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          for (final entry in [
            ('present', present), ('late', late),
            ('absent', absent), ('excused', excused),
          ])
            _CountChip(
              label: _statusMeta[entry.$1]!.label,
              count: entry.$2,
              color: _statusMeta[entry.$1]!.color,
            ),
        ]),
      ]),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _CountChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: AppDepth.radius(0),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
        ),
        child: Text('$label $count',
            textHeightBehavior: const TextHeightBehavior(
                applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
            style: TextStyle(
                color: color, fontSize: 11, height: 1.0, fontWeight: FontWeight.w700)),
      );
}

/// One student. Status is a 4-way segmented control rather than a checkbox,
/// because "late" and "excused" are real outcomes that a present/absent toggle
/// would force the teacher to lie about.
class _RegisterRow extends StatelessWidget {
  final Map<String, dynamic> profile;
  final String status;
  final double bonus;
  final bool saving;
  final ValueChanged<String> onStatus;
  final ValueChanged<double> onBonus;

  const _RegisterRow({
    required this.profile,
    required this.status,
    required this.bonus,
    required this.saving,
    required this.onStatus,
    required this.onBonus,
  });

  @override
  Widget build(BuildContext context) {
    final name = profile['full_name'] as String? ?? 'Student';
    final avatarUrl = profile['avatar_url'] as String?;
    final uniId = profile['university_id'] as String?;
    final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppDepth.radius(2),
        border: Border.all(
            color: attendanceStatusColor(status).withValues(alpha: 0.3), width: 0.8),
      ),
      child: Column(children: [
        Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.blue.withValues(alpha: 0.15),
            backgroundImage: hasAvatar ? CachedNetworkImageProvider(avatarUrl, maxWidth: 128, maxHeight: 128) : null,
            child: hasAvatar
                ? null
                : Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        color: AppColors.blue, fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.textPrimaryOf(context))),
              if (uniId?.isNotEmpty == true)
                Text(uniId!,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.textSecondaryOf(context))),
            ]),
          ),
          if (saving)
            const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
          // Bonus is opt-in and starts hidden: it is a reward for a handful of
          // students, so showing a stepper on all 50 rows would be noise.
          _BonusControl(bonus: bonus, onChanged: onBonus),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          for (final key in kAttendanceStatuses)
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: _StatusButton(
                  meta: _statusMeta[key]!,
                  selected: status == key,
                  onTap: () => onStatus(key),
                ),
              ),
            ),
        ]),
      ]),
    );
  }
}

class _BonusControl extends StatelessWidget {
  final double bonus;
  final ValueChanged<double> onChanged;
  const _BonusControl({required this.bonus, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final has = bonus > 0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (has)
        GestureDetector(
          onTap: () { AppHaptics.selection(); onChanged((bonus - 0.5).clamp(0, 5)); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsetsDirectional.only(start: 6),
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.14),
              borderRadius: AppDepth.radius(0),
              border: Border.all(color: AppColors.purple.withValues(alpha: 0.35), width: 0.6),
            ),
            child: Text('+${bonus.toStringAsFixed(bonus % 1 == 0 ? 0 : 1)}',
                textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                style: AppTextStyles.numericSmall.copyWith(
                    color: AppColors.purple, fontSize: 11, height: 1.0,
                    fontWeight: FontWeight.w800)),
          ),
        ),
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: has ? 'Add bonus (tap the chip to reduce)' : 'Give bonus',
        onPressed: bonus >= 5
            ? null
            : () { AppHaptics.selection(); onChanged((bonus + 0.5).clamp(0, 5)); },
        icon: Icon(Icons.star_rounded,
            size: 19,
            color: has
                ? AppColors.purple
                : AppColors.textSecondaryOf(context).withValues(alpha: 0.5)),
      ),
    ]);
  }
}

class _StatusButton extends StatelessWidget {
  final ({String short, String label, Color color}) meta;
  final bool selected;
  final VoidCallback onTap;
  const _StatusButton({required this.meta, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () { AppHaptics.selection(); onTap(); },
        child: AnimatedContainer(
          // Was LiquidGlass.motionFast — same 160ms, but a bare constant that
          // reduce-motion never reached.
          duration: AppMotion.durationOf(context, AppMotion.tight),
          curve: AppMotion.standard,
          // This was 8px of padding around an 11px label: a ~27dp target, on
          // the control a teacher taps once per student and where a mis-tap
          // marks the wrong person absent. A minimum height clears the 48dp
          // floor without inventing an off-scale padding value.
          constraints: const BoxConstraints(minHeight: AppSpace.minTouchTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          decoration: BoxDecoration(
            color: meta.color.withValues(alpha: selected ? 0.9 : 0.09),
            borderRadius: AppDepth.radius(1),
            border: Border.all(
                color: meta.color.withValues(alpha: selected ? 1 : 0.3), width: 0.8),
          ),
          child: Text(meta.label,
              textAlign: TextAlign.center,
              textHeightBehavior: const TextHeightBehavior(
                  applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
              style: TextStyle(
                  color: selected ? Colors.white : meta.color,
                  fontSize: 11, height: 1.0, fontWeight: FontWeight.w700)),
        ),
      );
}
