import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../core/auth/permission_session.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/role_labels.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/glass_chip.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';

import '../../../core/services/realtime_channel.dart';
import '../../../core/layout/nav_insets.dart';
import '../../web/presentation/widgets/adaptive_list.dart';
import 'widgets/user_admin_actions_mixin.dart';
import 'widgets/user_card.dart';
import 'widgets/user_group_tree.dart';
/// Super-admin-only: every user in the system with role + join date, an
/// approval queue for new (unverified) signups, and full delete-everywhere
/// (auth + storage + every owned row, via the delete-user edge function —
/// see 20260706000100_user_deletion_cascade for what cascades vs. what's
/// preserved with the reference nulled out). Ordinary admin/dept_admin have
/// no route to this screen at all (not just hidden — see app_router.dart).
class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});
  @override State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

// TickerProviderStateMixin, not Single: the tab set depends on who is looking,
// and the controller is rebuilt once that resolves. Two controllers exist for
// the frame between the swap and the old one's disposal, which Single forbids.
class _ManageUsersScreenState extends State<ManageUsersScreen>
    with TickerProviderStateMixin, UserAdminActions<ManageUsersScreen> {
  late TabController _tab;
  List<Map<String, dynamic>> _crRequests = [];
  String? _error;
  String? _crError;

  /// Per-role counts for the role cards and the "Total Users" tile — one
  /// small, unfiltered call to the same facet RPC the old drill-down used,
  /// now asked once for the landing screen rather than re-asked per filter.
  Map<String, dynamic> _facets = {};

  /// The approval queue, loaded by its own filtered query rather than by
  /// scanning a full download for is_verified == false.
  List<Map<String, dynamic>> _pending = [];

  /// Signups where the emailed code did NOT settle it — expired, or all
  /// attempts burned. The code is the primary gate; this is the second path,
  /// for the person it failed. Before this existed those signups sat in a
  /// service-role-only table where no admin could see them and the applicant
  /// had no way forward at all.
  List<Map<String, dynamic>> _stuck = [];

  /// Photos submitted via `my_submit_avatar()` and awaiting an admin's
  /// approve/reject — the same population and grant as Pending/Code-Failed
  /// (`can_browse_users()`), so no new permission was introduced for this.
  List<Map<String, dynamic>> _pendingAvatars = [];

  RealtimeChannel? _sub;
  RealtimeChannel? _crSub;
  final _refresh = RealtimeRefresh();
  final _crRefresh = RealtimeRefresh();

  /// True for a super_admin, false for a delegate who reached this screen via
  /// `permissions:delegate`.
  ///
  /// A delegate is here for ONE job — distributing work they already hold — so
  /// role changes, approvals and deletion are not theirs to make. Assumed FALSE
  /// until proven otherwise: the screen must not flash the destructive controls
  /// for the frame before the role resolves.
  bool _isSuperAdmin = false;

  /// The four jobs that live on this screen, each with its own grant.
  ///
  /// WHY FOUR FLAGS AND NOT ONE. This screen used to answer a single question —
  /// "are you super_admin?" — and show or hide everything on that. That is
  /// what made the authority model unusable: the only way to let someone
  /// approve a CR request was to make them super_admin, which also handed them
  /// account deletion. Each capability is now separate, so a course teacher can
  /// be given exactly "decide CR requests for my section" and nothing else,
  /// and the screen shows them exactly that.
  ///
  /// All default FALSE and resolve async. The screen must never flash a
  /// destructive control for the frame before the answer arrives.
  bool _canApproveUsers = false;   // users:approve   — the signup queue
  bool _canApproveCr = false;      // cr:approve      — the CR queue

  /// Every DESTINATION the landing screen offers, in display order — one per
  /// `profiles.role`, plus the one synthetic value `UserDirectoryScreen` has
  /// always understood: 'management' (a grant, not a stored role). "All" is
  /// not a card here — it's what the "Total Users" tile opens.
  static const _roles = ['management', 'student', 'teacher', 'admin', 'dept_admin', 'staff', 'exam_controller', 'super_admin'];

  /// Cards this viewer gets. The Management destination is super_admin's
  /// alone: a manager cannot read who else holds permissions:delegate, so
  /// for them it would always open empty.
  List<String> get _roleCards =>
      _roles.where((r) => r != 'management' || _isSuperAdmin).toList();

  Future<void> _loadViewerRole() async {
    final role = await RoleSession.ensureLoaded();
    final grants = await PermissionSession.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _isSuperAdmin = role == 'super_admin';
      // A super_admin holds everything without needing a row for it.
      _canApproveUsers = _isSuperAdmin || grants.contains('users:approve');
      _canApproveCr    = _isSuperAdmin || grants.contains('cr:approve');
      // THE TABS ARE THE VIEWER'S JOBS, NOT THE SCREEN'S FEATURES.
      //
      // Before, a delegate saw the Pending and CR queues and got a permission
      // error from every button in them — offering a door the database slams.
      // Now each queue appears only for the person who can act on it, so a
      // teacher holding cr:approve opens this screen and sees the CR queue and
      // nothing else.
      _setTabCount(_visibleTabs.length);
    });
  }

  /// Which tabs this viewer gets, in a fixed order. Read by the tab bar, the
  /// TabBarView and _setTabCount, so the three cannot disagree — a mismatch
  /// between controller length and child count is a crash, not a glitch.
  List<String> get _visibleTabs => [
        if (_canApproveUsers) 'pending',
        // Shown only when there is something in it. The code settles almost
        // every signup, so an always-present "Verification issues" tab that is
        // empty 99% of the time trains people to ignore it.
        if (_canApproveUsers && _stuck.isNotEmpty) 'stuck',
        if (_canApproveUsers && _pendingAvatars.isNotEmpty) 'avatars',
        if (_canApproveCr) 'cr',
        'users', // everyone who can open this screen at all gets the directory
      ];

  void _setTabCount(int length) {
    if (_tab.length == length) return;
    final old = _tab;
    _tab = TabController(length: length, vsync: this);
    // Disposed after this frame: the running build still holds the old one.
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
  }

  @override
  void initState() {
    super.initState();
    // Starts at 1 — this landing screen's own role-grid tab, present for
    // every viewer — and grows once the viewer's other queues resolve. Same
    // reasoning as _isSuperAdmin defaulting false: never flash controls that
    // may not be theirs.
    _tab = TabController(length: 1, vsync: this);
    _loadViewerRole().then((_) {
      _loadPending();
      _loadStuck();
      _loadPendingAvatars();
    });
    _loadRoleCounts();
    loadGrants();
    _loadCrRequests();
    // Debounced: `profiles` changes on every login and every profile edit
    // anywhere in the app, and each event used to trigger a full re-download of
    // all profiles (15 columns). Approving several signups, or any bulk write,
    // turned N row changes into N full-table fetches — N round trips on a phone
    // connection. The burst now collapses into one.
    _sub = SupabaseConfig.client.channel(screenChannel('manage_users', this))
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'profiles',
            callback: (_) => _refresh.schedule(_refreshAll))
        .subscribe();
    _crSub = SupabaseConfig.client.channel(screenChannel('manage_cr_requests', this))
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'cr_requests',
            callback: (_) => _crRefresh.schedule(_loadCrRequests))
        .subscribe();
  }

  @override
  void dispose() {
    _tab.dispose();
    _sub?.unsubscribe();
    _crSub?.unsubscribe();
    // Cancel any queued refetch, or it fires against an unmounted widget.
    _refresh.dispose();
    _crRefresh.dispose();
    super.dispose();
  }

  /// Per-role counts for the role cards, and the university-wide total for
  /// the "Total Users" tile. One small, unfiltered call — the per-role
  /// directory screens ask their own, narrower facets once opened.
  Future<void> _loadRoleCounts() async {
    try {
      final res = await SupabaseConfig.client.rpc('admin_user_facets', params: {
        'p_role': null, 'p_batch': null, 'p_section': null,
        'p_department_id': null, 'p_semester': null,
        'p_verified': null, 'p_q': null,
      });
      if (mounted && res is Map) setState(() => _facets = Map<String, dynamic>.from(res));
    } catch (_) {
      // Counts decorate the cards; losing them must not block the cards
      // themselves from being reachable.
    }
  }

  int get _totalUsers => (_facets['total'] as num?)?.toInt() ?? 0;

  /// One role's count, straight from the facet RPC's `roles` array.
  int _roleCount(String role) {
    final roles = (_facets['roles'] as List?) ?? const [];
    for (final r in roles) {
      if ('${(r as Map)['value']}' == role) return (r['count'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  /// The approval queue. Its own query, so it stays correct no matter how far
  /// the directory has been paged or filtered.
  Future<void> _loadPending() async {
    if (!_canApproveUsers) return;
    try {
      final res = await SupabaseConfig.client.rpc('admin_search_users', params: {
        'p_verified': false,
        'p_limit': 100,
      }) as List;
      if (mounted) setState(() => _pending = res.cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _loadStuck() async {
    if (!_canApproveUsers) return;
    try {
      final res = await SupabaseConfig.client.rpc('admin_list_stuck_registrations') as List;
      if (mounted) {
        setState(() {
          _stuck = res.cast<Map<String, dynamic>>();
          // The tab only exists while the queue is non-empty, so the controller
          // has to be resized with it — a controller length that disagrees with
          // the child count is a crash, not a glitch.
          _setTabCount(_visibleTabs.length);
        });
      }
    } catch (_) {
      // A fallback queue that fails to load must not blank the screens that
      // did load. Surfaced by its own empty/error state instead.
    }
  }

  /// Completes a signup the code could not. Goes through the edge function
  /// because creating the auth user needs the admin API, and because the
  /// staged password is encrypted with a key only the function holds.
  Future<void> _approveStuck(Map<String, dynamic> row) async {
    final ok = await confirmAction(
      'Approve ${row['full_name'] ?? row['email']}?',
      'This creates the account WITHOUT the email code being matched, on your '
          'judgement that ${row['email']} really belongs to them. It is recorded '
          'against your name.',
      'Approve manually',
    );
    if (!ok) return;
    try {
      final res = await SupabaseConfig.client.functions
          .invoke('register-admin-approve', body: {'registrationId': row['id']});
      final data = res.data;
      if (data is Map && data['error'] is String) throw Exception(data['error']);
      AppHaptics.success();
      await Future.wait([_loadStuck(), _refreshAll()]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _rejectStuck(Map<String, dynamic> row) async {
    final ok = await confirmAction(
      'Decline ${row['full_name'] ?? row['email']}?',
      'No account is created. The applicant can register again from scratch.',
      'Decline',
    );
    if (!ok) return;
    try {
      await SupabaseConfig.client.rpc('admin_reject_stuck_registration',
          params: {'p_id': row['id'], 'p_reason': null});
      await _loadStuck();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _loadPendingAvatars() async {
    if (!_canApproveUsers) return;
    try {
      final res = await SupabaseConfig.client.rpc('admin_list_pending_avatars') as List;
      if (mounted) {
        setState(() {
          _pendingAvatars = res.cast<Map<String, dynamic>>();
          _setTabCount(_visibleTabs.length);
        });
      }
    } catch (_) {
      // Same reasoning as _loadStuck: a fallback queue failing to load must
      // not blank the screens that did load.
    }
  }

  Future<void> _approveAvatar(Map<String, dynamic> row) async {
    try {
      await SupabaseConfig.client.rpc('admin_approve_avatar', params: {'p_user_id': row['id']});
      await NotificationService.sendToUsers(
        userIds: [row['id']],
        title: 'Photo approved',
        message: 'Your profile photo is now live.',
        category: 'general',
      );
      AppHaptics.success();
      await _loadPendingAvatars();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _rejectAvatar(Map<String, dynamic> row) async {
    final reasonCtrl = TextEditingController();
    await showGlassModal(context,
        builder: (sheetCtx) => SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Reject photo', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 16),
              AfosTextField(hint: 'Reason (optional)', controller: reasonCtrl, maxLines: 2),
              const SizedBox(height: 20),
              AfosButton(label: 'Confirm Rejection', onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(sheetCtx);
                try {
                  await SupabaseConfig.client.rpc('admin_reject_avatar', params: {
                    'p_user_id': row['id'],
                    'p_reason': reasonCtrl.text.trim(),
                  });
                  await NotificationService.sendToUsers(
                    userIds: [row['id']],
                    title: 'Photo rejected',
                    message: reasonCtrl.text.trim().isNotEmpty
                        ? 'Your photo was not approved: ${reasonCtrl.text.trim()}'
                        : 'Your photo was not approved. Please upload another.',
                    category: 'general',
                  );
                  await _loadPendingAvatars();
                } catch (e) {
                  messenger.showSnackBar(
                      SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                }
              }),
            ])));
  }

  Future<void> _refreshAll() async {
    await Future.wait([_loadRoleCounts(), _loadPending(), _loadPendingAvatars()]);
  }

  Future<void> _loadCrRequests() async {
    try {
      final res = await SupabaseConfig.client.from('cr_requests')
          .select('*, profiles!student_id(full_name, university_id, avatar_url), departments!department_id(name)')
          .eq('status', 'pending').order('created_at', ascending: false) as List;
      if (mounted) setState(() { _crRequests = res.cast(); _crError = null; });
    } catch (e) {
      if (mounted) setState(() => _crError = friendlyError(e));
    }
  }

  Future<void> _approveCr(Map<String, dynamic> req) async {
    try {
      // ONE TRANSACTION, NOT TWO CLIENT WRITES.
      //
      // This used to be an UPDATE on `students` followed by an UPDATE on
      // `cr_requests`. If the second failed, a CR existed whose request was
      // still sitting in the queue. Nothing demoted the outgoing CR either, so
      // a section accumulated them — and with the one-CR-per-section unique
      // index now in place, the first write would simply start failing with a
      // constraint name. approve_cr_request does the whole thing server-side:
      // demote the previous CR, promote this one, stamp the review, and answer
      // everyone else waiting on the same section.
      await SupabaseConfig.client
          .rpc('approve_cr_request', params: {'p_request_id': req['id']});
      await NotificationService.sendToUsers(
        userIds: [req['student_id']],
        title: 'CR request approved',
        message: 'You are now the Class Representative for your section.',
        category: 'general',
      );
      AppHaptics.success();
      // Same reasoning as _approve: don't leave the reviewed request sitting in
      // the pending list until a realtime event happens to arrive.
      await _loadCrRequests();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _rejectCr(Map<String, dynamic> req) async {
    final reasonCtrl = TextEditingController();
    await showGlassModal(context,
        builder: (sheetCtx) => SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Reject CR Request', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 16),
              AfosTextField(hint: 'Reason (optional)', controller: reasonCtrl, maxLines: 2),
              const SizedBox(height: 20),
              AfosButton(label: 'Confirm Rejection', onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(sheetCtx);
                try {
                  // Via the RPC for the same reason as approval: the write
                  // policy on cr_requests is super_admin-only, so a cr:approve
                  // holder can decide a request only through a function that
                  // checks the grant. A direct UPDATE would silently affect
                  // zero rows for them — RLS filters rather than errors.
                  await SupabaseConfig.client.rpc('reject_cr_request', params: {
                    'p_request_id': req['id'],
                    'p_reason': reasonCtrl.text.trim(),
                  });
                  await NotificationService.sendToUsers(
                    userIds: [req['student_id']],
                    title: 'CR request declined',
                    message: reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : 'Your CR request was not approved.',
                    category: 'general',
                  );
                  await _loadCrRequests();
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                }
              }),
            ])));
  }

  /// The approval queue, grouped by role, in the order the roles are listed on
  /// this screen so the queue and the directory agree about what comes first.
  /// A LinkedHashMap — insertion order is the display order.
  Map<String, List<Map<String, dynamic>>> get _pendingByRole {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final r in _roles) {
      if (r == 'management') continue;
      final people = _pending.where((u) => '${u['role']}' == r).toList();
      if (people.isNotEmpty) out[r] = people;
    }
    // Anyone whose role is not in the chip list still has to be approvable —
    // a signup nobody can see is the failure mode this screen exists to
    // prevent.
    final seen = out.values.expand((l) => l).map((u) => u['id']).toSet();
    final rest = _pending.where((u) => !seen.contains(u['id'])).toList();
    if (rest.isNotEmpty) out['other'] = rest;
    return out;
  }

  Future<void> _approve(Map<String, dynamic> user) async {
    try {
      // Via the RPC for the same reason as _setRole: a users:approve holder is
      // not matched by admin_manage_all_profiles, so a direct UPDATE would
      // affect zero rows and look like a dead button.
      await SupabaseConfig.client.rpc('set_user_verified', params: {
        'p_user_id': user['id'], 'p_verified': true,
      });
      // Reflect it locally straight away instead of waiting for the realtime
      // round-trip to come back and call _refreshAll(). The subscription is
      // still what keeps OTHER admins' screens in sync, but making the
      // acting admin's own queue depend on a WAL round-trip is what made an
      // approval look like it hadn't registered -- the row sat in "Pending"
      // until the event arrived. The reload below still runs, so this is a
      // head start, not a substitute for truth.
      if (mounted) {
        setState(() {
          _pending.removeWhere((u) => u['id'] == user['id']);
        });
      }
      // pending_approval_screen.dart only reflects this live via realtime
      // while the app is actually open — a push is the only way someone
      // who's closed the app finds out their account is now active.
      await NotificationService.sendToUsers(
        userIds: [user['id'] as String],
        title: 'Account approved',
        message: 'Your AFOS account is approved. You can sign in now.',
        category: 'general',
      );
      // Approving an account lets someone into the app. Irreversible in
      // practice, and the admin is usually working through a queue — the
      // confirmation needs to land in the hand, not just in a list that
      // re-sorts.
      AppHaptics.success();
      await _refreshAll();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Manage Users'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 4),
          child: RepaintBoundary(
            child: GlassCard(
              borderRadius: 16,
              glowColor: AppColors.holoviolet,
              padding: const EdgeInsets.symmetric(vertical: 12),
              // Counts of queues a delegate cannot work are noise to them; the
              // one number they need is how many people hold delegated areas.
              // "Total Users" is real navigation now, not a dead number — it
              // pushes the same UserDirectoryScreen every role card does,
              // with no role filter.
              child: Row(children: _isSuperAdmin
                  ? [
                      Expanded(child: _StatTile(label: 'Pending', value: _pending.length)),
                      _StatDivider(),
                      Expanded(child: _StatTile(label: 'CR Requests', value: _crRequests.length)),
                      _StatDivider(),
                      Expanded(child: _StatTile(
                          label: 'Total Users', value: _totalUsers,
                          onTap: () => context.push('/admin/users/all'))),
                    ]
                  : [
                      // No "Managers" count here. A manager cannot READ who
                      // else holds permissions:delegate — that is deliberate,
                      // so the tier cannot be enumerated from inside it — and
                      // a tile reading 0 would be a confident lie rather than
                      // an absence. What they can see is their own remit:
                      // how many people they have PERSONALLY handed an area
                      // to, straight from the grants RLS already scoped to
                      // them — never a count of some other page's rows.
                      Expanded(child: _StatTile(
                          label: 'In your areas',
                          value: grantsByUser.entries
                              .where((e) => e.value.any((id) => id != delegatePermId))
                              .length)),
                      _StatDivider(),
                      Expanded(child: _StatTile(
                          label: 'Total Users', value: _totalUsers,
                          onTap: () => context.push('/admin/users/all'))),
                    ]),
            ),
          ),
        ),
        // One tab needs no tab bar to switch between.
        if (_visibleTabs.length > 1)
          AnimatedBuilder(
            animation: _tab,
            builder: (ctx, _) => GlassTabBar(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              currentIndex: _tab.index,
              onChanged: (i) => _tab.animateTo(i),
              tabs: [
                for (final t in _visibleTabs)
                  switch (t) {
                    'pending' => GlassTab('Pending (${_pending.length})', icon: Icons.how_to_reg_rounded),
                    'stuck' => GlassTab('Code Failed (${_stuck.length})', icon: Icons.mark_email_unread_rounded),
                    'avatars' => GlassTab('Photos (${_pendingAvatars.length})', icon: Icons.photo_camera_outlined),
                    'cr' => GlassTab('CR Requests (${_crRequests.length})', icon: Icons.badge_rounded),
                    _ => const GlassTab('Users', icon: Icons.people_alt_rounded),
                  },
              ],
            ),
          ),
        Expanded(child: TabBarView(controller: _tab, children: [
                if (_canApproveUsers) ...[
                _error != null
                    ? ErrorView(message: _error!, onRetry: _loadPending)
                    : _pending.isEmpty
                    ? const EmptyState(icon: Icons.how_to_reg_outlined, title: 'No pending approvals',
                        subtitle: 'New signups will show up here')
                    // Grouped by role, same headings as the directory. The
                    // queue is already loaded in full (it is a queue, and it
                    // is meant to stay short), so this groups in memory rather
                    // than asking the server -- unlike the directory, where
                    // the whole point is NOT to download everyone.
                    //
                    // Approve / Reject / Delete are untouched: each still
                    // follows its own grant, and Reject still deletes the
                    // account outright (auth row, storage, every owned row,
                    // via the delete-user edge function) which is why it stays
                    // super_admin's even though approving does not.
                    : ListView(
                        padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)),
                        children: [
                          for (final entry in _pendingByRole.entries) ...[
                            GroupSectionHeader(
                                label: roleLabel(entry.key), total: entry.value.length),
                            for (final u in entry.value)
                              UserCard(key: ValueKey(u['id']), user: u, pending: true,
                                  onApprove: () => _approve(u),
                                  onReject: _isSuperAdmin ? () => rejectAndDelete(u, onDone: _refreshAll) : null,
                                  onDelete: _isSuperAdmin ? () => confirmDelete(u, onDone: _refreshAll) : null),
                            const SizedBox(height: 24),
                          ],
                        ],
                      ),
                ],
                // Order here MUST match _visibleTabs exactly.
                if (_canApproveUsers && _stuck.isNotEmpty) ...[
                AdaptiveList(
                    padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)),
                    itemCount: _stuck.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0) {
                        return SurfaceCard(
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Icon(Icons.info_outline, color: AppColors.amber, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'These people asked for an account but the emailed code never '
                                'settled it — it expired, or they used up every attempt. Nobody '
                                'here has proved they own the address, so approving one is your '
                                'judgement, recorded against your name.',
                                style: AppTextStyles.bodyMedium
                                    .copyWith(color: AppColors.textSecondaryOf(ctx)),
                              ),
                            ),
                          ]),
                        );
                      }
                      final r = _stuck[i - 1];
                      return SurfaceCard(
                        key: ValueKey(r['id']),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${r['full_name'] ?? 'Unnamed'}',
                              style: AppTextStyles.titleMedium
                                  .copyWith(color: AppColors.textPrimaryOf(ctx))),
                          const SizedBox(height: 4),
                          Text('${r['email']}',
                              style: AppTextStyles.bodyMedium
                                  .copyWith(color: AppColors.textSecondaryOf(ctx))),
                          const SizedBox(height: 8),
                          Wrap(spacing: 8, runSpacing: 8, children: [
                            GlassChip(label: roleLabel('${r['account_type']}'), selected: false,
                                color: AppColors.holoviolet, onTap: () {}),
                            if (r['university_id'] != null)
                              GlassChip(label: 'ID ${r['university_id']}', selected: false,
                                  color: AppColors.holoBlue, onTap: () {}),
                            GlassChip(
                                label: '${r['attempts']}/${r['max_attempts']} attempts',
                                selected: false, color: AppColors.amber, onTap: () {}),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                            '${r['review_reason'] ?? 'Code not matched'} · asked ${AppFormatters.relativeTime(DateTime.parse('${r['created_at']}'))}',
                            style: AppTextStyles.labelSmall
                                .copyWith(color: AppColors.textSecondaryOf(ctx)),
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: AfosButton(
                                label: 'Approve manually', onTap: () => _approveStuck(r))),
                            const SizedBox(width: 10),
                            Expanded(child: AfosButton(
                                label: 'Decline', outlined: true, onTap: () => _rejectStuck(r))),
                          ]),
                        ]),
                      );
                    }),
                ],
                if (_canApproveUsers && _pendingAvatars.isNotEmpty) ...[
                AdaptiveList(
                    padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)),
                    itemCount: _pendingAvatars.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0) {
                        return SurfaceCard(
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Icon(Icons.info_outline, color: AppColors.amber, size: 18),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Every profile photo is checked before it goes live. Reject '
                                'anything that is not a real, formal picture of the person.',
                                style: AppTextStyles.bodyMedium
                                    .copyWith(color: AppColors.textSecondaryOf(ctx)),
                              ),
                            ),
                          ]),
                        );
                      }
                      final r = _pendingAvatars[i - 1];
                      return SurfaceCard(
                        key: ValueKey(r['id']),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            CircleAvatar(radius: 24, backgroundColor: AppColors.surfaceOf(ctx),
                                backgroundImage: (r['avatar_pending_url'] as String?)?.isNotEmpty == true
                                    ? CachedNetworkImageProvider(r['avatar_pending_url'], maxWidth: 256, maxHeight: 256)
                                    : null),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${r['full_name'] ?? 'Unnamed'}',
                                  style: AppTextStyles.titleMedium
                                      .copyWith(color: AppColors.textPrimaryOf(ctx))),
                              Text(roleLabel('${r['role']}'),
                                  style: AppTextStyles.bodyMedium
                                      .copyWith(color: AppColors.textSecondaryOf(ctx))),
                            ])),
                          ]),
                          const SizedBox(height: 6),
                          Text(
                            r['avatar_submitted_at'] != null
                                ? 'submitted ${AppFormatters.relativeTime(DateTime.parse('${r['avatar_submitted_at']}'))}'
                                : 'submitted time unknown',
                            style: AppTextStyles.labelSmall
                                .copyWith(color: AppColors.textSecondaryOf(ctx)),
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(child: AfosButton(
                                label: 'Approve', onTap: () => _approveAvatar(r))),
                            const SizedBox(width: 10),
                            Expanded(child: AfosButton(
                                label: 'Reject', outlined: true, onTap: () => _rejectAvatar(r))),
                          ]),
                        ]),
                      );
                    }),
                ],
                if (_canApproveCr) ...[
                _crError != null
                    ? ErrorView(message: _crError!, onRetry: _loadCrRequests)
                    : _crRequests.isEmpty
                    ? const EmptyState(icon: Icons.badge_outlined, title: 'No CR requests',
                        subtitle: 'Student requests to become Class Representative will show up here')
                    : AdaptiveList(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: _crRequests.length,
                        itemBuilder: (ctx, i) {
                          final r = _crRequests[i];
                          final student = r['profiles'] as Map<String, dynamic>? ?? {};
                          final dept = r['departments'] as Map<String, dynamic>? ?? {};
                          return SurfaceCard(
                              key: ValueKey(r['id']),
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(student['full_name'] ?? 'Unknown', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                                Text('${student['university_id'] ?? ''} · ${dept['name'] ?? ''} · Batch ${r['batch_label']} · Section ${r['section']}',
                                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
                                const SizedBox(height: 10),
                                Row(children: [
                                  Expanded(child: OutlinedButton(onPressed: () => _rejectCr(r),
                                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
                                      child: const Text('Reject'))),
                                  const SizedBox(width: 8),
                                  Expanded(child: ElevatedButton(onPressed: () => _approveCr(r),
                                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white),
                                      child: const Text('Approve'))),
                                ]),
                              ]));
                        }),
                ],
                // THE ROLE PICKER. Was a single scrolling column of a search
                // box, role chips and drill-down chips stacked above a list —
                // crowded enough on a phone that only a sliver was left for
                // actual people. Tapping a role now pushes a REAL page
                // (UserDirectoryScreen) with its own always-visible search box
                // in a fixed slot, instead of filtering a shared list in
                // place.
                AdaptiveList(
                  padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)),
                  itemCount: _roleCards.length,
                  itemBuilder: (ctx, i) {
                    final r = _roleCards[i];
                    final count = r == 'management'
                        ? grantsByUser.values
                            .where((g) => delegatePermId != null && g.contains(delegatePermId))
                            .length
                        : _roleCount(r);
                    return SurfaceCard(
                      margin: const EdgeInsets.only(bottom: 10),
                      onTap: () => context.push('/admin/users/$r'),
                      child: Row(children: [
                        Icon(r == 'management' ? Icons.supervisor_account_rounded : Icons.badge_outlined,
                            color: UserCard.roleColors[r] ?? AppColors.holoviolet, size: 22),
                        const SizedBox(width: 14),
                        Expanded(child: Text(r == 'management' ? 'Management' : roleLabel(r),
                            style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(ctx)))),
                        Text('$count', style: AppTextStyles.titleMedium.copyWith(
                            color: AppColors.textSecondaryOf(ctx),
                            fontFeatures: const [FontFeature.tabularFigures()])),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right_rounded, color: AppColors.textSecondaryOf(ctx), size: 20),
                      ]),
                    );
                  },
                ),
              ])),
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label; final int value;
  final VoidCallback? onTap;
  const _StatTile({required this.label, required this.value, this.onTap});
  @override
  Widget build(BuildContext context) {
    final content = Column(children: [
        Text('$value', style: AppTextStyles.displayMedium.copyWith(
            color: AppColors.holoviolet, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondaryOf(context))),
      ]);
    if (onTap == null) return content;
    return InkWell(borderRadius: AppDepth.radius(0), onTap: onTap, child: content);
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 0.5, height: 32, color: AppColors.borderOf(context));
}
