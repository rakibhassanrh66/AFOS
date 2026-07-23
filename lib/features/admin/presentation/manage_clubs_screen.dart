import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';

import '../../../shared/widgets/glass_bottom_nav.dart';
import '../../../core/services/realtime_channel.dart';
/// Super-admin-only: approve/reject club membership requests and officer
/// post (secretary/vice_president/president) requests. Regular admins have
/// no route here — clubs.president_id carries real notification-broadcast
/// power (see send-notification's clubId mode), so who gets to grant it is
/// deliberately narrow.
class ManageClubsScreen extends StatefulWidget {
  const ManageClubsScreen({super.key});
  @override State<ManageClubsScreen> createState() => _ManageClubsScreenState();
}

class _ManageClubsScreenState extends State<ManageClubsScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _membershipRequests = [], _postRequests = [];
  bool _loading = true;
  RealtimeChannel? _memberSub, _postSub;
  final _refresh = RealtimeRefresh();
  // Guards against a double-tap (or a retry after a lost network response
  // for a write that actually went through) re-submitting the same
  // approval — without this, a second attempt on an already-approved
  // request would hit the club_members unique constraint and show a
  // confusing "error" even though the first attempt fully succeeded.
  final Set<String> _processingIds = {};

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
    // ONE debouncer for both channels: they share `_load()`, which fetches both
    // request tables, so a change on either used to trigger a full double fetch.
    _memberSub = SupabaseConfig.client.channel(screenChannel('manage_club_membership_requests', this))
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'club_membership_requests',
            callback: (_) => _refresh.schedule(_load))
        .subscribe();
    _postSub = SupabaseConfig.client.channel(screenChannel('manage_club_post_requests', this))
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'club_post_requests',
            callback: (_) => _refresh.schedule(_load))
        .subscribe();
  }

  @override
  void dispose() {
    _tab.dispose();
    _memberSub?.unsubscribe();
    _postSub?.unsubscribe();
    // Cancel any queued refetch, or it fires against an unmounted widget.
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        SupabaseConfig.client.from('club_membership_requests')
            .select('*, clubs(name), profiles!student_id(full_name, university_id, avatar_url)')
            .eq('status', 'pending').order('created_at', ascending: false) as Future,
        SupabaseConfig.client.from('club_post_requests')
            .select('*, clubs(name), profiles!member_id(full_name, university_id, avatar_url)')
            .eq('status', 'pending').order('created_at', ascending: false) as Future,
      ]);
      if (mounted) {
        setState(() {
        _membershipRequests = (results[0] as List).cast();
        _postRequests = (results[1] as List).cast();
        _loading = false;
      });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approveMembership(Map<String, dynamic> req) async {
    final id = req['id'] as String;
    if (_processingIds.contains(id)) return;
    setState(() => _processingIds.add(id));
    try {
      // upsert, not insert — if this exact membership already exists (a
      // retried tap after a lost network response for a write that had
      // actually already gone through), this is a no-op instead of a
      // unique-constraint error.
      await SupabaseConfig.client.from('club_members').upsert({
        'club_id': req['club_id'], 'member_id': req['student_id'], 'role': 'member',
      }, onConflict: 'club_id,member_id');
      await SupabaseConfig.client.from('club_membership_requests').update({
        'status': 'approved', 'reviewed_by': SupabaseConfig.uid, 'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', id);
      await NotificationService.sendToUsers(
        userIds: [req['student_id']],
        title: 'Club membership approved',
        message: 'You are now a member of ${(req['clubs'] as Map?)?['name'] ?? 'the club'}.',
        category: 'club', deepLink: '/clubs',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Membership approved ✓'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\'t approve — please try again. (${friendlyError(e)})'), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _processingIds.remove(id));
  }

  Future<void> _rejectMembership(Map<String, dynamic> req) async {
    await _reasonSheet('Reject Membership', (reason) async {
      await SupabaseConfig.client.from('club_membership_requests').update({
        'status': 'rejected', 'rejection_reason': reason,
        'reviewed_by': SupabaseConfig.uid, 'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', req['id']);
      await NotificationService.sendToUsers(
        userIds: [req['student_id']],
        title: 'Club membership declined',
        message: reason.isNotEmpty ? reason : 'Your membership request was not approved.',
        category: 'club',
      );
    });
  }

  Future<void> _approvePost(Map<String, dynamic> req) async {
    final id = req['id'] as String;
    if (_processingIds.contains(id)) return;
    setState(() => _processingIds.add(id));
    final clubId = req['club_id'] as String;
    final memberId = req['member_id'] as String;
    final role = req['requested_role'] as String;
    try {
      if (role == 'president') {
        // Demote whoever currently holds the post first — otherwise both
        // the outgoing and incoming president would show role='president'
        // in club_members simultaneously, even though clubs.president_id
        // (the actual source of truth for broadcast power) only points to
        // the new one.
        await SupabaseConfig.client.from('club_members').update({'role': 'member'})
            .eq('club_id', clubId).eq('role', 'president');
        await SupabaseConfig.client.from('clubs').update({'president_id': memberId}).eq('id', clubId);
      }
      await SupabaseConfig.client.from('club_members').update({'role': role})
          .eq('club_id', clubId).eq('member_id', memberId);
      await SupabaseConfig.client.from('club_post_requests').update({
        'status': 'approved', 'reviewed_by': SupabaseConfig.uid, 'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', req['id']);
      await NotificationService.sendToUsers(
        userIds: [memberId],
        title: 'Club post approved',
        message: 'You are now ${role.replaceAll('_', ' ')} of ${(req['clubs'] as Map?)?['name'] ?? 'the club'}.',
        category: 'club', deepLink: '/clubs',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post approved ✓'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Couldn\'t approve — please try again. (${friendlyError(e)})'), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _processingIds.remove(id));
  }

  Future<void> _rejectPost(Map<String, dynamic> req) async {
    await _reasonSheet('Reject Post Application', (reason) async {
      await SupabaseConfig.client.from('club_post_requests').update({
        'status': 'rejected', 'rejection_reason': reason,
        'reviewed_by': SupabaseConfig.uid, 'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', req['id']);
      await NotificationService.sendToUsers(
        userIds: [req['member_id']],
        title: 'Club post application declined',
        message: reason.isNotEmpty ? reason : 'Your post application was not approved.',
        category: 'club',
      );
    });
  }

  Future<void> _reasonSheet(String title, Future<void> Function(String reason) onConfirm) async {
    final reasonCtrl = TextEditingController();
    await showGlassModal(context,
        builder: (sheetCtx) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 16),
              AfosTextField(hint: 'Reason (optional)', controller: reasonCtrl, maxLines: 2),
              const SizedBox(height: 20),
              AfosButton(label: 'Confirm', onTap: () async {
                Navigator.pop(sheetCtx);
                await onConfirm(reasonCtrl.text.trim());
              }),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Manage Clubs'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: RepaintBoundary(
            child: GlassCard(
              borderRadius: 16,
              glowColor: AppColors.holoviolet,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                Expanded(child: _StatTile(label: 'Membership', value: _membershipRequests.length)),
                Container(width: 0.5, height: 32, color: AppColors.borderOf(context)),
                Expanded(child: _StatTile(label: 'Post Requests', value: _postRequests.length)),
              ]),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _tab,
          builder: (ctx, _) => GlassTabBar(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            currentIndex: _tab.index,
            onChanged: (i) => _tab.animateTo(i),
            tabs: [
              GlassTab('Membership (${_membershipRequests.length})', icon: Icons.group_add_rounded),
              GlassTab('Post Requests (${_postRequests.length})', icon: Icons.post_add_rounded),
            ],
          ),
        ),
        Expanded(child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
            : TabBarView(controller: _tab, children: [
                _membershipRequests.isEmpty
                    ? const EmptyState(icon: Icons.group_add_outlined, title: 'No pending requests', subtitle: 'Membership requests will show up here')
                    : ListView.builder(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + GlassBottomNav.navContentClearance), itemCount: _membershipRequests.length,
                        itemBuilder: (ctx, i) {
                          final r = _membershipRequests[i];
                          final student = r['profiles'] as Map<String, dynamic>? ?? {};
                          final club = r['clubs'] as Map<String, dynamic>? ?? {};
                          return _RequestCard(
                            key: ValueKey(r['id']),
                            name: student['full_name'] ?? 'Unknown',
                            subtitle: '${student['university_id'] ?? ''} → ${club['name'] ?? ''}',
                            onApprove: () => _approveMembership(r),
                            onReject: () => _rejectMembership(r),
                            isBusy: _processingIds.contains(r['id']),
                          );
                        }),
                _postRequests.isEmpty
                    ? const EmptyState(icon: Icons.workspace_premium_outlined, title: 'No pending post applications', subtitle: 'Officer post applications will show up here')
                    : ListView.builder(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + GlassBottomNav.navContentClearance), itemCount: _postRequests.length,
                        itemBuilder: (ctx, i) {
                          final r = _postRequests[i];
                          final member = r['profiles'] as Map<String, dynamic>? ?? {};
                          final club = r['clubs'] as Map<String, dynamic>? ?? {};
                          final role = (r['requested_role'] as String? ?? '').replaceAll('_', ' ');
                          return _RequestCard(
                            key: ValueKey(r['id']),
                            name: member['full_name'] ?? 'Unknown',
                            subtitle: '${club['name'] ?? ''} · applying for $role',
                            onApprove: () => _approvePost(r),
                            onReject: () => _rejectPost(r),
                            isBusy: _processingIds.contains(r['id']),
                          );
                        }),
              ])),
      ]),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final String name, subtitle;
  final VoidCallback onApprove, onReject;
  final bool isBusy;
  const _RequestCard({super.key, required this.name, required this.subtitle, required this.onApprove, required this.onReject, this.isBusy = false});
  @override
  Widget build(BuildContext context) => SurfaceCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
        Text(subtitle, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: isBusy ? null : onReject,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
              child: const Text('Reject'))),
          const SizedBox(width: 8),
          Expanded(child: ElevatedButton(onPressed: isBusy ? null : onApprove,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white),
              child: isBusy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Approve'))),
        ]),
      ]));
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
