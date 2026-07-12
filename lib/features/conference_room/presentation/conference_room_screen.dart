import 'package:flutter/material.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';

/// Teacher/staff-facing conference room booking — request purpose/date/
/// time, super_admin approves and assigns the actual room number.
class ConferenceRoomScreen extends StatefulWidget {
  const ConferenceRoomScreen({super.key});
  @override State<ConferenceRoomScreen> createState() => _ConferenceRoomScreenState();
}

class _ConferenceRoomScreenState extends State<ConferenceRoomScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); _load(); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final res = await SupabaseConfig.client.from('conference_room_requests')
          .select().eq('requester_id', uid).order('created_at', ascending: false) as List;
      if (mounted) setState(() { _requests = res.cast(); _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _cancel(String id) async {
    try {
      await SupabaseConfig.client.from('conference_room_requests').update({'status': 'cancelled'}).eq('id', id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  static const _tabLabels = ['My Requests', 'New Request'];
  static const _tabIcons = [Icons.event_note_rounded, Icons.add_circle_outline_rounded];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Conference Room'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [AppColors.holoTeal, AppColors.holoBlue]),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: const Icon(Icons.meeting_room_rounded, color: Colors.white, size: 24)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Conference Room', style: AppTextStyles.titleLarge.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(_loading ? 'Loading…' : '${_requests.length} of your requests',
                    style: AppTextStyles.bodyMedium.copyWith(color: Colors.white.withValues(alpha: 0.9))),
              ])),
            ]),
          ),
        ),
        AnimatedBuilder(
          animation: _tab,
          builder: (ctx, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: List.generate(_tabLabels.length, (i) {
              final sel = _tab.index == i;
              return Expanded(child: GestureDetector(
                onTap: () => _tab.animateTo(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                      gradient: sel ? const LinearGradient(colors: [AppColors.holoTeal, AppColors.holoBlue]) : null,
                      color: sel ? null : AppColors.glassFill(context),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(_tabIcons[i], size: 16, color: sel ? Colors.white : AppColors.textSecondaryOf(context)),
                    const SizedBox(width: 6),
                    Text(_tabLabels[i],
                        textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                        style: TextStyle(color: sel ? Colors.white : AppColors.textSecondaryOf(context),
                            fontSize: 12.5, height: 1.0, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                  ]),
                ),
              ));
            })),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: TabBarView(controller: _tab, children: [
          _loading ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _RequestsList(requests: _requests, onCancel: _cancel),
          _NewRequestForm(onSubmitted: () { _load(); _tab.animateTo(0); }),
        ])),
      ]),
    );
  }
}

class _RequestsList extends StatelessWidget {
  final List<Map<String, dynamic>> requests; final ValueChanged<String> onCancel;
  const _RequestsList({required this.requests, required this.onCancel});

  Color _statusColor(String s) => switch (s) {
    'approved' => AppColors.green, 'rejected' => AppColors.red,
    'cancelled' => AppColors.textSecondary, _ => AppColors.amber,
  };

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const EmptyState(icon: Icons.meeting_room_outlined,
        title: 'No requests yet', subtitle: 'Submit a new request from the other tab');
    }
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: requests.length,
        itemBuilder: (ctx, i) {
          final r = requests[i];
          final status = r['status'] as String? ?? 'pending';
          return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(r['purpose'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Text(status.toUpperCase(), textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                          style: TextStyle(color: _statusColor(status), fontSize: 10, height: 1.0, fontWeight: FontWeight.w700))),
                ]),
                Text('${r['requested_date']} · ${r['start_time']}–${r['end_time']}',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
                if (status == 'approved')
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text('Room: ${r['assigned_room'] ?? '-'}',
                      style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w600))),
                if (status == 'rejected')
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text('Reason: ${r['rejection_reason'] ?? '-'}',
                      style: const TextStyle(color: AppColors.red, fontSize: 12))),
                if (status == 'pending')
                  Padding(padding: const EdgeInsets.only(top: 8), child: OutlinedButton(
                      onPressed: () => onCancel(r['id']),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
                      child: const Text('Cancel'))),
              ]));
        });
  }
}

class _NewRequestForm extends StatefulWidget {
  final VoidCallback onSubmitted;
  const _NewRequestForm({required this.onSubmitted});
  @override State<_NewRequestForm> createState() => _NewRequestFormState();
}

class _NewRequestFormState extends State<_NewRequestForm> {
  final _purposeCtrl = TextEditingController();
  DateTime? _date;
  TimeOfDay? _start, _end;
  bool _saving = false;

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.now(),
        firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 180)));
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime(bool isStart) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (t == null) return;
    setState(() { if (isStart) {
      _start = t;
    } else {
      _end = t;
    } });
  }

  Future<void> _submit() async {
    if (_purposeCtrl.text.trim().isEmpty || _date == null || _start == null || _end == null) return;
    setState(() => _saving = true);
    try {
      await SupabaseConfig.client.from('conference_room_requests').insert({
        'requester_id': SupabaseConfig.uid,
        'purpose': _purposeCtrl.text.trim(),
        'requested_date': _date!.toIso8601String().split('T').first,
        'start_time': '${_start!.hour.toString().padLeft(2, '0')}:${_start!.minute.toString().padLeft(2, '0')}',
        'end_time': '${_end!.hour.toString().padLeft(2, '0')}:${_end!.minute.toString().padLeft(2, '0')}',
      });
      NotificationService.notifyRoles(
        roles: const ['super_admin'],
        title: 'New conference room request',
        message: _purposeCtrl.text.trim(),
        category: 'general', deepLink: '/admin/conference-rooms',
      );
      _purposeCtrl.clear();
      setState(() { _date = null; _start = null; _end = null; });
      widget.onSubmitted();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    return SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Request a Conference Room', style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
      const SizedBox(height: 20),
      AfosTextField(hint: 'Purpose (e.g. Department meeting)', controller: _purposeCtrl, maxLines: 2),
      const SizedBox(height: 16),
      OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event_outlined),
          label: Text(_date == null ? 'Pick date' : _date!.toIso8601String().split('T').first)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: OutlinedButton.icon(onPressed: () => _pickTime(true), icon: const Icon(Icons.access_time),
            label: Text(_start == null ? 'Start time' : _start!.format(context)))),
        const SizedBox(width: 12),
        Expanded(child: OutlinedButton.icon(onPressed: () => _pickTime(false), icon: const Icon(Icons.access_time),
            label: Text(_end == null ? 'End time' : _end!.format(context)))),
      ]),
      const SizedBox(height: 24),
      AfosButton(label: 'Submit Request', loading: _saving, onTap: _submit),
    ]));
  }
}
