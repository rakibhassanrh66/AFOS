import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/glass_chip.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';

import '../../../core/services/realtime_channel.dart';
import '../../../core/layout/nav_insets.dart';
import '../../web/presentation/widgets/adaptive_list.dart';
class ManageConferenceRoomsScreen extends StatefulWidget {
  const ManageConferenceRoomsScreen({super.key});
  @override State<ManageConferenceRoomsScreen> createState() => _ManageConferenceRoomsScreenState();
}

class _ManageConferenceRoomsScreenState extends State<ManageConferenceRoomsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  String? _error;
  String _filter = 'pending';
  RealtimeChannel? _sub;
  final _refresh = RealtimeRefresh();
  static const _filters = ['pending', 'approved', 'rejected', 'cancelled', 'all'];

  @override
  void initState() {
    super.initState();
    _load();
    _sub = SupabaseConfig.client.channel(screenChannel('manage_conference_rooms', this))
        // Debounced: every event reloads the whole request table, so approving
        // a batch turned N row changes into N full refetches.
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'conference_room_requests',
            callback: (_) => _refresh.schedule(_load))
        .subscribe();
  }

  @override
  void dispose() {
    _sub?.unsubscribe();
    // Cancel any queued refetch, or it fires against an unmounted widget.
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await SupabaseConfig.client.from('conference_room_requests')
          .select('*, profiles!requester_id(full_name, role)')
          .order('created_at', ascending: false) as List;
      if (mounted) setState(() { _requests = res.cast(); _loading = false; _error = null; });
    } catch (e) {
      // Worse here than on the requester's own screen: this is the REVIEW
      // queue. Swallowing the failure showed an admin "No requests" while
      // real bookings sat waiting for a decision, and nothing anywhere said
      // the fetch had failed — so the queue looked done rather than unread.
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _visible =>
      _filter == 'all' ? _requests : _requests.where((r) => r['status'] == _filter).toList();

  Future<void> _approve(Map<String, dynamic> req) async {
    final roomCtrl = TextEditingController();
    bool saving = false;
    await showGlassModal(context,
        builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheetState) => SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Assign Room', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 16),
              AfosTextField(hint: 'Room number (e.g. Conf Room 4-201)', controller: roomCtrl),
              const SizedBox(height: 20),
              AfosButton(label: 'Confirm Approval', loading: saving, onTap: () async {
                if (roomCtrl.text.trim().isEmpty) return;
                setSheetState(() => saving = true);
                try {
                  await SupabaseConfig.client.from('conference_room_requests').update({
                    'status': 'approved', 'assigned_room': roomCtrl.text.trim(),
                    'reviewed_by': SupabaseConfig.uid, 'reviewed_at': DateTime.now().toIso8601String(),
                  }).eq('id', req['id']);
                  await NotificationService.sendToUsers(
                    userIds: [req['requester_id']],
                    title: 'Conference room approved',
                    message: 'Room ${roomCtrl.text.trim()} assigned for your request.',
                    deepLink: '/conference-room', category: 'general',
                  );
                  _load();
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                } catch (e) {
                  if (sheetCtx.mounted) {
                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                      SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                  }
                  setSheetState(() => saving = false);
                }
              }),
            ]))));
  }

  Future<void> _reject(Map<String, dynamic> req) async {
    final reasonCtrl = TextEditingController();
    bool saving = false;
    await showGlassModal(context,
        builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheetState) => SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Reject Request', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 16),
              AfosTextField(hint: 'Reason (e.g. room unavailable)', controller: reasonCtrl, maxLines: 3),
              const SizedBox(height: 20),
              AfosButton(label: 'Confirm Rejection', loading: saving, onTap: () async {
                if (reasonCtrl.text.trim().isEmpty) return;
                setSheetState(() => saving = true);
                try {
                  await SupabaseConfig.client.from('conference_room_requests').update({
                    'status': 'rejected', 'rejection_reason': reasonCtrl.text.trim(),
                    'reviewed_by': SupabaseConfig.uid, 'reviewed_at': DateTime.now().toIso8601String(),
                  }).eq('id', req['id']);
                  await NotificationService.sendToUsers(
                    userIds: [req['requester_id']],
                    title: 'Conference room request declined',
                    message: reasonCtrl.text.trim(),
                    category: 'general',
                  );
                  _load();
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                } catch (e) {
                  if (sheetCtx.mounted) {
                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                      SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                  }
                  setSheetState(() => saving = false);
                }
              }),
            ]))));
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Conference Rooms'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
          child: RepaintBoundary(
            child: GlassCard(
              borderRadius: 16,
              glowColor: AppColors.holoviolet,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                Expanded(child: _StatTile(label: 'Pending',
                    value: _requests.where((r) => r['status'] == 'pending').length)),
                Container(width: 0.5, height: 32, color: AppColors.borderOf(context)),
                Expanded(child: _StatTile(label: 'Approved',
                    value: _requests.where((r) => r['status'] == 'approved').length)),
                Container(width: 0.5, height: 32, color: AppColors.borderOf(context)),
                Expanded(child: _StatTile(label: 'Total', value: _requests.length)),
              ]),
            ),
          ),
        ),
        // Was a horizontal ListView — always left-anchored, leaving empty
        // space to the right of a short filter row instead of centering it.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8,
            children: _filters.map((f) {
              final sel = f == _filter;
              return GlassChip(
                label: f[0].toUpperCase() + f.substring(1),
                selected: sel,
                color: AppColors.holoviolet,
                onTap: () => setState(() => _filter = f));
            }).toList()),
        ),
        Expanded(child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
            : _visible.isEmpty
                ? EmptyState(icon: Icons.meeting_room_outlined, title: 'No requests', subtitle: 'Nothing in "$_filter" right now')
                : AdaptiveList(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: _visible.length,
                    itemBuilder: (ctx, i) {
                      final r = _visible[i];
                      final requester = r['profiles'] as Map<String, dynamic>? ?? {};
                      final status = r['status'] as String? ?? 'pending';
                      return SurfaceCard(
                          key: ValueKey(r['id']),
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${requester['full_name'] ?? 'Unknown'} (${requester['role'] ?? ''})',
                                style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                            Text(r['purpose'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                            // See conference_room_screen: raw Postgres `time`
                            // rendered as "14:00:00–15:00:00".
                            Text('${r['requested_date']} · '
                                '${AppFormatters.time12(r['start_time'].toString())}–'
                                '${AppFormatters.time12(r['end_time'].toString())}',
                                style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
                            if (status == 'pending') Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [
                              Expanded(child: OutlinedButton(onPressed: () => _reject(r),
                                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
                                  child: const Text('Reject'))),
                              const SizedBox(width: 8),
                              Expanded(child: ElevatedButton(onPressed: () => _approve(r),
                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white),
                                  child: const Text('Approve'))),
                            ])),
                          ]));
                    })),
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label; final int value;
  const _StatTile({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(children: [
        Text('$value', style: AppTextStyles.displayMedium.copyWith(
            color: AppColors.holoviolet, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondaryOf(context))),
      ]);
}
