import 'package:flutter/material.dart';

import '../../../../config/supabase_config.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/spacing.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../../core/utils/error_formatter.dart';
import '../../../../shared/widgets/afos_button.dart';
import '../../../../shared/widgets/afos_text_field.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../data/repositories/advising_repository.dart';

/// Weekday names, index-aligned to `teacher_office_hours.day_of_week`
/// (0 = Sunday, matching Postgres `extract(dow)` and the Bangladeshi week,
/// which starts on Sunday).
const _days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// A teacher's own office hours and leave.
///
/// This is what makes "when is my advisor free" answerable. A student sees the
/// result on the advisor card without any link existing, which is why the read
/// policy on both tables is open to authenticated users while the write policy
/// is not.
class AvailabilityEditor extends StatefulWidget {
  const AvailabilityEditor({super.key});

  @override
  State<AvailabilityEditor> createState() => _AvailabilityEditorState();
}

class _AvailabilityEditorState extends State<AvailabilityEditor> {
  final _repo = AdvisingRepository();

  List<Map<String, dynamic>> _hours = const [];
  List<Map<String, dynamic>> _leave = const [];
  bool _loading = true;
  String? _error;

  String? get _uid => SupabaseConfig.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final hours = await _repo.officeHours(uid);
      final leave = await _repo.upcomingLeave(uid);
      if (!mounted) return;
      setState(() {
        _hours = hours;
        _leave = leave;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  Future<void> _addHours() async {
    final uid = _uid;
    if (uid == null) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _OfficeHourDialog(),
    );
    if (result == null) return;
    try {
      await SupabaseConfig.client.from('teacher_office_hours').insert({
        'teacher_id': uid,
        ...result,
      });
      AppHaptics.success();
      await _load();
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    }
  }

  Future<void> _addLeave() async {
    final uid = _uid;
    if (uid == null) return;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (range == null) return;
    try {
      await SupabaseConfig.client.from('teacher_leave').insert({
        'teacher_id': uid,
        'starts_on': range.start.toIso8601String().split('T').first,
        'ends_on': range.end.toIso8601String().split('T').first,
      });
      AppHaptics.success();
      await _load();
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    }
  }

  Future<void> _removeHours(Map<String, dynamic> row) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      await SupabaseConfig.client
          .from('teacher_office_hours')
          .delete()
          .eq('teacher_id', uid)
          .eq('day_of_week', row['day_of_week'] as int)
          .eq('start_time', row['start_time'] as String);
      await _load();
    } catch (e) {
      if (mounted) _toast(friendlyError(e));
    }
  }

  void _toast(String m) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SurfaceCard(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpace.lg),
            child: SizedBox(
                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ),
      );
    }

    return SurfaceCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('When you are free',
            style: AppTextStyles.titleMedium
                .copyWith(color: AppColors.textPrimaryOf(context))),
        AppSpace.vGapXs,
        Text(
          'Your students see this on your card, so they know when to come and '
          'when not to.',
          style: AppTextStyles.labelSmall
              .copyWith(color: AppColors.textSecondaryOf(context)),
        ),
        AppSpace.vGapMd,
        if (_error != null)
          Text(_error!,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.red))
        else ...[
          if (_hours.isEmpty)
            Text('No office hours set.',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondaryOf(context)))
          else
            for (final h in _hours)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      '${_days[(h['day_of_week'] as int).clamp(0, 6)]}  '
                      '${_hhmm(h['start_time'])} – ${_hhmm(h['end_time'])}'
                      '${(h['note'] as String?)?.isNotEmpty == true ? '  ·  ${h['note']}' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyLarge
                          .copyWith(color: AppColors.textPrimaryOf(context)),
                    ),
                  ),
                  AppSpace.gapSm,
                  SizedBox(
                    width: AppSpace.minTouchTarget,
                    height: AppSpace.minTouchTarget,
                    child: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () => _removeHours(h),
                    ),
                  ),
                ]),
              ),
          AppSpace.vGapSm,
          AfosButton(
              label: 'Add office hours',
              icon: Icons.add_rounded,
              outlined: true,
              onTap: _addHours),
          AppSpace.vGapLg,
          Text('Leave',
              style: AppTextStyles.titleMedium
                  .copyWith(color: AppColors.textPrimaryOf(context))),
          AppSpace.vGapSm,
          if (_leave.isEmpty)
            Text('No leave booked.',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondaryOf(context)))
          else
            for (final l in _leave)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.xs),
                child: Text('${l['starts_on']} → ${l['ends_on']}',
                    style: AppTextStyles.bodyLarge
                        .copyWith(color: AppColors.textPrimaryOf(context))),
              ),
          AppSpace.vGapSm,
          AfosButton(
              label: 'Book leave',
              icon: Icons.event_busy_rounded,
              outlined: true,
              onTap: _addLeave),
        ],
      ]),
    );
  }

  /// Postgres returns `time` as 'HH:MM:SS'. Students do not need the seconds.
  static String _hhmm(Object? raw) {
    final s = raw?.toString() ?? '';
    final parts = s.split(':');
    return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : s;
  }
}

class _OfficeHourDialog extends StatefulWidget {
  const _OfficeHourDialog();

  @override
  State<_OfficeHourDialog> createState() => _OfficeHourDialogState();
}

class _OfficeHourDialogState extends State<_OfficeHourDialog> {
  int _day = 0;
  TimeOfDay _start = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 12, minute: 0);
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  String _wire(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Office hours'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            initialValue: _day,
            decoration: const InputDecoration(labelText: 'Day'),
            items: [
              for (var i = 0; i < _days.length; i++)
                DropdownMenuItem(value: i, child: Text(_days[i])),
            ],
            onChanged: (v) => setState(() => _day = v ?? 0),
          ),
          AppSpace.vGapMd,
          Row(children: [
            Expanded(
              child: AfosButton(
                label: 'From ${_start.format(context)}',
                outlined: true,
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _start);
                  if (t != null) setState(() => _start = t);
                },
              ),
            ),
            AppSpace.gapSm,
            Expanded(
              child: AfosButton(
                label: 'To ${_end.format(context)}',
                outlined: true,
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _end);
                  if (t != null) setState(() => _end = t);
                },
              ),
            ),
          ]),
          AppSpace.vGapMd,
          AfosTextField(hint: 'Where (optional)', controller: _noteCtrl),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          onPressed: () {
            // The table has a CHECK (end_time > start_time); catching it here
            // means the teacher gets a sentence instead of a constraint name.
            if (_end.hour * 60 + _end.minute <= _start.hour * 60 + _start.minute) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('The end time has to be after the start time.')));
              return;
            }
            Navigator.pop(context, {
              'day_of_week': _day,
              'start_time': _wire(_start),
              'end_time': _wire(_end),
              if (_noteCtrl.text.trim().isNotEmpty) 'note': _noteCtrl.text.trim(),
            });
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
