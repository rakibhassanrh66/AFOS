import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_chip.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';

import '../../../shared/widgets/glass_bottom_nav.dart';
import '../../../core/services/realtime_channel.dart';
/// Super Admin / admin / staff hall-application review — the student side
/// (hall_screen.dart) could always apply/cancel, but until this screen there
/// was nowhere for anyone to actually approve/reject an application (the
/// admin_hall_all RLS policy already supported it, only the UI was missing).
class ManageHallScreen extends StatefulWidget {
  const ManageHallScreen({super.key});
  @override State<ManageHallScreen> createState() => _ManageHallScreenState();
}

class _ManageHallScreenState extends State<ManageHallScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _apps = [];
  bool _loading = true;
  String _filter = 'pending';
  String? _appsError;
  RealtimeChannel? _sub;

  List<Map<String, dynamic>> _complaints = [];
  bool _complaintsLoading = true;
  String _complaintFilter = 'open';
  String? _complaintsError;
  RealtimeChannel? _complaintsSub;

  static const _filters = ['pending', 'reviewing', 'cancel_requested', 'approved', 'rejected', 'cancelled', 'all'];
  static const _complaintFilters = ['open', 'in_progress', 'resolved', 'dismissed', 'all'];

  static String _filterLabel(String f) => f.replaceAll('_', ' ').split(' ')
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
    _loadComplaints();
    // hall_applications.stream() can't embed the student's profile, so we
    // refetch (like dept_chat's admin-moderation pattern) on any change
    // instead of relying on the raw realtime row.
    _sub = SupabaseConfig.client.channel(screenChannel('manage_hall_applications', this))
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
            table: 'hall_applications', callback: (_) => _load())
        .subscribe();
    _complaintsSub = SupabaseConfig.client.channel(screenChannel('manage_hall_complaints', this))
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
            table: 'hall_complaints', callback: (_) => _loadComplaints())
        .subscribe();
  }

  @override
  void dispose() { _tab.dispose(); _sub?.unsubscribe(); _complaintsSub?.unsubscribe(); super.dispose(); }

  Future<void> _loadComplaints() async {
    try {
      final res = await SupabaseConfig.client.from('hall_complaints')
          .select('*, profiles!student_id(full_name,university_id,email,department)')
          .order('created_at', ascending: false) as List;
      if (mounted) setState(() { _complaints = res.cast(); _complaintsLoading = false; _complaintsError = null; });
    } catch (e) {
      // Previously swallowed silently, which meant a real load failure
      // looked identical to "no complaints yet" — surfacing it so a genuine
      // problem doesn't hide behind a misleading empty state.
      if (mounted) setState(() { _complaintsLoading = false; _complaintsError = friendlyError(e); });
    }
  }

  List<Map<String, dynamic>> get _visibleComplaints => _complaintFilter == 'all'
      ? _complaints : _complaints.where((c) => c['status'] == _complaintFilter).toList();

  Future<void> _markInProgress(Map<String, dynamic> complaint) async {
    try {
      await SupabaseConfig.client.from('hall_complaints')
          .update({'status': 'in_progress'}).eq('id', complaint['id']);
      if (mounted) setState(() => complaint['status'] = 'in_progress');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _resolveComplaint(Map<String, dynamic> complaint, String status) async {
    final responseCtrl = TextEditingController(text: complaint['resolution'] as String? ?? '');
    bool saving = false;
    await showGlassModal(context,
        builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheetState) {
          final textPrimary = AppColors.textPrimaryOf(sheetCtx);
          return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(status == 'resolved' ? 'Resolve Complaint' : 'Dismiss Complaint',
                    style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
                const SizedBox(height: 8),
                Text('${complaint['profiles']?['full_name'] ?? 'Student'} · ${complaint['category'] ?? ''}',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
                const SizedBox(height: 20),
                AfosTextField(hint: 'Response to student', controller: responseCtrl, maxLines: 3),
                const SizedBox(height: 24),
                AfosButton(
                  label: 'Confirm',
                  loading: saving,
                  onTap: () async {
                    setSheetState(() => saving = true);
                    try {
                      await SupabaseConfig.client.from('hall_complaints').update({
                        'status': status,
                        'resolution': responseCtrl.text.trim(),
                        'resolved_by': SupabaseConfig.uid,
                        'resolved_at': DateTime.now().toIso8601String(),
                      }).eq('id', complaint['id']);
                      final studentId = complaint['student_id'] as String?;
                      if (studentId != null && responseCtrl.text.trim().isNotEmpty) {
                        await NotificationService.sendToUsers(
                          userIds: [studentId],
                          title: status == 'resolved' ? 'Complaint resolved' : 'Complaint update',
                          message: responseCtrl.text.trim(),
                          deepLink: '/hall',
                          category: 'hall',
                        );
                      }
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    } catch (e) {
                      if (sheetCtx.mounted) {
                        ScaffoldMessenger.of(sheetCtx).showSnackBar(
                          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                      }
                      setSheetState(() => saving = false);
                    }
                  },
                ),
              ]));
        }));
  }

  Future<void> _load() async {
    try {
      final res = await SupabaseConfig.client.from('hall_applications')
          .select('*, profiles!student_id(full_name,university_id,email,department)')
          .order('created_at', ascending: false) as List;
      if (mounted) setState(() { _apps = res.cast(); _loading = false; _appsError = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _appsError = friendlyError(e); });
    }
  }

  List<Map<String, dynamic>> get _visible =>
      _filter == 'all' ? _apps : _apps.where((a) => a['status'] == _filter).toList();

  Future<void> _markReviewing(Map<String, dynamic> app) async {
    await SupabaseConfig.client.from('hall_applications')
        .update({'status': 'reviewing', 'reviewed_by': SupabaseConfig.uid, 'reviewed_at': DateTime.now().toIso8601String()})
        .eq('id', app['id']);
  }

  Future<void> _approve(Map<String, dynamic> app) async {
    final roomCtrl = TextEditingController();
    final floorCtrl = TextEditingController();
    final buildingCtrl = TextEditingController(text: app['preferred_hall'] as String? ?? '');
    bool saving = false;
    await showGlassModal(context,
        builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheetState) {
          final textPrimary = AppColors.textPrimaryOf(sheetCtx);
          return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Approve Application', style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
                const SizedBox(height: 8),
                Text('${app['profiles']?['full_name'] ?? 'Student'} · ${app['preferred_hall'] ?? ''}',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
                const SizedBox(height: 20),
                AfosTextField(hint: 'Building', controller: buildingCtrl),
                const SizedBox(height: 12),
                AfosTextField(hint: 'Room number', controller: roomCtrl),
                const SizedBox(height: 12),
                AfosTextField(hint: 'Floor', controller: floorCtrl, keyboardType: TextInputType.number),
                const SizedBox(height: 24),
                AfosButton(
                  label: 'Confirm Approval',
                  loading: saving,
                  onTap: () async {
                    if (roomCtrl.text.trim().isEmpty) return;
                    setSheetState(() => saving = true);
                    try {
                      await SupabaseConfig.client.from('hall_applications').update({
                        'status': 'approved',
                        'assigned_room': roomCtrl.text.trim(),
                        'assigned_floor': int.tryParse(floorCtrl.text.trim()),
                        'assigned_building': buildingCtrl.text.trim(),
                        'reviewed_by': SupabaseConfig.uid,
                        'reviewed_at': DateTime.now().toIso8601String(),
                      }).eq('id', app['id']);
                      final studentId = app['student_id'] as String?;
                      if (studentId != null) {
                        await NotificationService.sendToUsers(
                          userIds: [studentId],
                          title: 'Hall application approved',
                          message: 'Room ${roomCtrl.text.trim()}, ${buildingCtrl.text.trim()}',
                          deepLink: '/hall',
                          category: 'hall',
                        );
                      }
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    } catch (e) {
                      if (sheetCtx.mounted) {
                        ScaffoldMessenger.of(sheetCtx).showSnackBar(
                          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                      }
                      setSheetState(() => saving = false);
                    }
                  },
                ),
              ]));
        }));
  }

  Future<void> _reject(Map<String, dynamic> app) async {
    final reasonCtrl = TextEditingController();
    bool saving = false;
    await showGlassModal(context,
        builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheetState) {
          final textPrimary = AppColors.textPrimaryOf(sheetCtx);
          return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Reject Application', style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
                const SizedBox(height: 8),
                Text(app['profiles']?['full_name'] ?? 'Student',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
                const SizedBox(height: 20),
                AfosTextField(hint: 'Reason (e.g. no seat available)', controller: reasonCtrl, maxLines: 3),
                const SizedBox(height: 24),
                AfosButton(
                  label: 'Confirm Rejection',
                  loading: saving,
                  onTap: () async {
                    if (reasonCtrl.text.trim().isEmpty) return;
                    setSheetState(() => saving = true);
                    try {
                      await SupabaseConfig.client.from('hall_applications').update({
                        'status': 'rejected',
                        'rejection_reason': reasonCtrl.text.trim(),
                        'reviewed_by': SupabaseConfig.uid,
                        'reviewed_at': DateTime.now().toIso8601String(),
                      }).eq('id', app['id']);
                      final studentId = app['student_id'] as String?;
                      if (studentId != null) {
                        await NotificationService.sendToUsers(
                          userIds: [studentId],
                          title: 'Hall application rejected',
                          message: reasonCtrl.text.trim(),
                          deepLink: '/hall',
                          category: 'hall',
                        );
                      }
                      if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                    } catch (e) {
                      if (sheetCtx.mounted) {
                        ScaffoldMessenger.of(sheetCtx).showSnackBar(
                          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                      }
                      setSheetState(() => saving = false);
                    }
                  },
                ),
              ]));
        }));
  }

  Future<void> _approveCancellation(Map<String, dynamic> app) async {
    try {
      await SupabaseConfig.client.from('hall_applications').update({
        'status': 'cancelled',
        'reviewed_by': SupabaseConfig.uid,
        'reviewed_at': DateTime.now().toIso8601String(),
      }).eq('id', app['id']);
      final studentId = app['student_id'] as String?;
      if (studentId != null) {
        await NotificationService.sendToUsers(
          userIds: [studentId],
          title: 'Hall cancellation approved',
          message: 'Your seat has been released as requested.',
          deepLink: '/hall',
          category: 'hall',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _denyCancellation(Map<String, dynamic> app) async {
    try {
      await SupabaseConfig.client.from('hall_applications').update({
        'status': 'approved',
      }).eq('id', app['id']);
      final studentId = app['student_id'] as String?;
      if (studentId != null) {
        await NotificationService.sendToUsers(
          userIds: [studentId],
          title: 'Cancellation request denied',
          message: 'Your hall seat stays allocated — contact administration if you still need to cancel.',
          deepLink: '/hall',
          category: 'hall',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _deleteApplication(Map<String, dynamic> app) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
              backgroundColor: AppColors.surfaceOf(dCtx),
              title: Text('Delete this application?', style: TextStyle(color: AppColors.textPrimaryOf(dCtx))),
              content: Text('Removes it permanently — the student can submit a new one afterward.',
                  style: TextStyle(color: AppColors.textSecondaryOf(dCtx))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('Delete', style: TextStyle(color: AppColors.red))),
              ],
            ));
    if (confirm != true) return;
    try {
      await SupabaseConfig.client.from('hall_applications').delete().eq('id', app['id']);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  static const _tabLabels = ['Applications', 'Complaints'];
  static const _tabIcons = [Icons.assignment_rounded, Icons.report_problem_rounded];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Manage Hall'),
      body: Column(children: [
        FeatureHeader(
          title: 'Manage Hall',
          subtitle: '${_apps.length} applications · ${_complaints.length} complaints',
          icon: Icons.apartment_rounded,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.amber, AppColors.gold]),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        ),
        AnimatedBuilder(
          animation: _tab,
          builder: (ctx, _) => GlassTabBar(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            currentIndex: _tab.index,
            onChanged: (i) => _tab.animateTo(i),
            tabs: [
              for (var i = 0; i < _tabLabels.length; i++)
                GlassTab(_tabLabels[i], icon: _tabIcons[i]),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: TabBarView(controller: _tab, children: [
          _buildApplicationsTab(context),
          _buildComplaintsTab(context),
        ])),
      ]),
    );
  }

  Widget _buildApplicationsTab(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Column(children: [
        SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: _filters.map((f) {
              final sel = f == _filter;
              return Padding(padding: const EdgeInsets.only(right: 8),
                child: Center(child: GlassChip(
                  label: _filterLabel(f),
                  selected: sel,
                  color: AppColors.blue,
                  onTap: () => setState(() => _filter = f))));
            }).toList())),
        Expanded(child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
            : _appsError != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 40),
                    const SizedBox(height: 12),
                    Text('Couldn\'t load applications: $_appsError', textAlign: TextAlign.center, style: TextStyle(color: textSecondary)),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ])))
                : _visible.isEmpty
                ? EmptyState(icon: Icons.apartment_outlined, title: 'No applications', subtitle: 'Nothing in "$_filter" right now')
                : ListView.builder(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + GlassBottomNav.navContentClearance), itemCount: _visible.length,
                    itemBuilder: (ctx, i) {
                      final a = _visible[i];
                      final profile = a['profiles'] as Map<String, dynamic>? ?? {};
                      final status = a['status'] as String? ?? 'pending';
                      return Container(key: ValueKey(a['id']), margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(profile['full_name'] ?? 'Unknown',
                                  style: AppTextStyles.titleMedium.copyWith(color: textPrimary))),
                              _StatusPill(status),
                              IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.red),
                                  onPressed: () => _deleteApplication(a)),
                            ]),
                            Text('${profile['university_id'] ?? ''} · ${profile['department'] ?? ''}',
                                style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
                            const SizedBox(height: 6),
                            Text('${a['preferred_hall'] ?? '-'} · ${a['preference'] ?? '-'}',
                                style: AppTextStyles.bodyMedium.copyWith(color: textPrimary)),
                            if ((a['reason'] as String?)?.isNotEmpty ?? false)
                              Padding(padding: const EdgeInsets.only(top: 4), child: Text(a['reason'],
                                  style: AppTextStyles.bodyMedium.copyWith(color: textSecondary), maxLines: 2, overflow: TextOverflow.ellipsis)),
                            if (status == 'approved' || status == 'cancel_requested')
                              Padding(padding: const EdgeInsets.only(top: 6), child: Text(
                                  'Room ${a['assigned_room'] ?? '-'}, ${a['assigned_building'] ?? '-'} (Floor ${a['assigned_floor'] ?? '-'})',
                                  style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w600))),
                            if (status == 'rejected')
                              Padding(padding: const EdgeInsets.only(top: 6), child: Text('Reason: ${a['rejection_reason'] ?? '-'}',
                                  style: const TextStyle(color: AppColors.red, fontSize: 12))),
                            if (status == 'cancel_requested')
                              Padding(padding: const EdgeInsets.only(top: 6), child: Text('Cancellation reason: ${a['cancellation_reason'] ?? '-'}',
                                  style: const TextStyle(color: AppColors.amber, fontSize: 12))),
                            if (status == 'pending' || status == 'reviewing') ...[
                              const SizedBox(height: 10),
                              Row(children: [
                                if (status == 'pending')
                                  TextButton(onPressed: () => _markReviewing(a), child: const Text('Mark Reviewing')),
                                const Spacer(),
                                OutlinedButton(onPressed: () => _reject(a),
                                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red), minimumSize: const Size(64, 36)),
                                    child: const Text('Reject')),
                                const SizedBox(width: 8),
                                ElevatedButton(onPressed: () => _approve(a),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white, minimumSize: const Size(64, 36)),
                                    child: const Text('Approve')),
                              ]),
                            ],
                            if (status == 'cancel_requested') ...[
                              const SizedBox(height: 10),
                              Row(children: [
                                const Spacer(),
                                OutlinedButton(onPressed: () => _denyCancellation(a),
                                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red), minimumSize: const Size(64, 36)),
                                    child: const Text('Deny')),
                                const SizedBox(width: 8),
                                ElevatedButton(onPressed: () => _approveCancellation(a),
                                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white, minimumSize: const Size(64, 36)),
                                    child: const Text('Approve Cancellation')),
                              ]),
                            ],
                          ]));
                    })),
      ]);
  }

  Widget _buildComplaintsTab(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Column(children: [
      SizedBox(height: 48, child: ListView(scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          children: _complaintFilters.map((f) {
            final sel = f == _complaintFilter;
            return Padding(padding: const EdgeInsets.only(right: 8),
              child: Center(child: GlassChip(
                label: f.replaceAll('_', ' ').split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' '),
                selected: sel,
                color: AppColors.blue,
                onTap: () => setState(() => _complaintFilter = f))));
          }).toList())),
      Expanded(child: _complaintsLoading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
          : _complaintsError != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 40),
                  const SizedBox(height: 12),
                  Text('Couldn\'t load complaints: $_complaintsError', textAlign: TextAlign.center, style: TextStyle(color: textSecondary)),
                  const SizedBox(height: 12),
                  TextButton(onPressed: _loadComplaints, child: const Text('Retry')),
                ])))
              : _visibleComplaints.isEmpty
              ? EmptyState(icon: Icons.report_problem_outlined, title: 'No complaints', subtitle: 'Nothing in "$_complaintFilter" right now')
              : ListView.builder(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + GlassBottomNav.navContentClearance), itemCount: _visibleComplaints.length,
                  itemBuilder: (ctx, i) {
                    final c = _visibleComplaints[i];
                    final profile = c['profiles'] as Map<String, dynamic>? ?? {};
                    final status = c['status'] as String? ?? 'open';
                    return Container(key: ValueKey(c['id']), margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text('${profile['full_name'] ?? 'Unknown'} · ${c['category'] ?? ''}',
                                style: AppTextStyles.titleMedium.copyWith(color: textPrimary))),
                            _StatusPill(status),
                          ]),
                          Text('${profile['university_id'] ?? ''} · ${profile['department'] ?? ''}',
                              style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
                          const SizedBox(height: 6),
                          Text(c['description'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textPrimary)),
                          if ((c['resolution'] as String?)?.isNotEmpty ?? false)
                            Padding(padding: const EdgeInsets.only(top: 6), child: Text('Response: ${c['resolution']}',
                                style: const TextStyle(color: AppColors.green, fontSize: 12))),
                          if (status == 'open' || status == 'in_progress') ...[
                            const SizedBox(height: 10),
                            Row(children: [
                              if (status == 'open')
                                TextButton(onPressed: () => _markInProgress(c),
                                    child: const Text('Mark In Progress')),
                              const Spacer(),
                              OutlinedButton(onPressed: () => _resolveComplaint(c, 'dismissed'),
                                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red), minimumSize: const Size(64, 36)),
                                  child: const Text('Dismiss')),
                              const SizedBox(width: 8),
                              ElevatedButton(onPressed: () => _resolveComplaint(c, 'resolved'),
                                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white, minimumSize: const Size(64, 36)),
                                  child: const Text('Resolve')),
                            ]),
                          ],
                        ]));
                  })),
    ]);
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill(this.status);
  Color get _color => switch (status) {
        'approved' => AppColors.green,
        'rejected' => AppColors.red,
        'reviewing' => AppColors.amber,
        'cancel_requested' => AppColors.amber,
        'cancelled' => AppColors.textSecondary,
        _ => AppColors.blue,
      };
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: _color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Text(status.toUpperCase(), style: TextStyle(color: _color, fontSize: 10, fontWeight: FontWeight.w700)));
}
