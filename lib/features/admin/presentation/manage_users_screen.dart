import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';

import '../../../core/services/realtime_channel.dart';
import '../../../core/layout/nav_insets.dart';
import '../../web/presentation/widgets/adaptive_list.dart';
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
class _ManageUsersScreenState extends State<ManageUsersScreen> with TickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _crRequests = [];
  bool _loading = true;
  String? _error;
  String? _crError;
  String _search = '';
  String _roleFilter = 'all';

  // ---------------------------------------------------------------------
  // SERVER-SIDE SEGMENTATION.
  //
  // This screen used to `select(...)` every profile with no .limit() and then
  // filter and search CLIENT-SIDE in Dart. At 12 users that is invisible; at
  // 25,000 it downloads the whole user table on every open and again on every
  // realtime profiles change, and the search box can only find people already
  // downloaded. Both jobs now happen in Postgres (admin_search_users /
  // admin_user_facets, db/proposed/004) and this screen holds one page.
  // ---------------------------------------------------------------------

  /// Counts per facet value at the current drill level, straight from the
  /// database. Drives the chips AND the header tiles, so the numbers describe
  /// the whole university rather than whatever happened to be downloaded.
  Map<String, dynamic> _facets = {};

  /// Drill-down state. null means "not filtered by this".
  String? _fBatch;
  String? _fSection;
  String? _fDepartmentId;
  int? _fSemester;

  /// The grouped directory: a place per kind of person, each grouped the way
  /// that kind is actually organised (students by intake term then batch,
  /// teachers by department then join year, staff by sector then join year).
  ///
  /// Counts come from `admin_user_groups()` and the rows for an opened group
  /// come from `admin_search_users()` with the SAME keys, so a header can
  /// never claim a number the rows below it disagree with.
  ///
  /// Grouping is for BROWSING. While a search is active the flat, paged result
  /// list is shown instead — someone typing an ID wants the person, not the
  /// section of the university they happen to sit in.
  List<UserGroup> _groups = [];
  bool _groupsLoading = false;
  String? _groupsError;

  bool get _grouped =>
      _search.trim().isEmpty && _roleFilter != 'all' && _roleFilter != 'management';

  // Keyset cursor. OFFSET re-walks every skipped row, so page 40 costs forty
  // times page 1; (created_at, id) costs the same on every page.
  String? _cursorCreatedAt;
  String? _cursorId;
  bool _hasMore = true;
  bool _loadingMore = false;

  /// The approval queue, loaded by its own filtered query rather than by
  /// scanning a full download for is_verified == false.
  List<Map<String, dynamic>> _pending = [];

  /// Signups where the emailed code did NOT settle it — expired, or all
  /// attempts burned. The code is the primary gate; this is the second path,
  /// for the person it failed. Before this existed those signups sat in a
  /// service-role-only table where no admin could see them and the applicant
  /// had no way forward at all.
  List<Map<String, dynamic>> _stuck = [];

  Timer? _searchDebounce;

  /// The search box needs a controller of its own. Without one it kept its
  /// text in its own element state, and the debounced reload below sets
  /// `_loading = true`, which replaces the WHOLE TabBarView -- search box
  /// included -- with a shimmer. The field was therefore destroyed and rebuilt
  /// on every keystroke, so the list filtered correctly while the box you
  /// typed into rendered empty. Seen in a browser; no test caught it because
  /// nothing throws and the query itself was always right.
  final _searchCtrl = TextEditingController();

  /// True until the first page has landed. The full-screen skeleton belongs to
  /// that first load only -- flashing it on every keystroke is what tore the
  /// search box out of the tree.
  bool _firstLoad = true;
  final _listScroll = ScrollController();

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
  bool _canAssignRoles = false;    // roles:assign    — change someone's role
  bool _canDelegate = false;       // permissions:delegate — hand out work

  /// Who holds which delegated areas, keyed by user id.
  ///
  /// WHY THIS IS LOADED FOR THE WHOLE LIST AND NOT PER CARD. Management was
  /// invisible: a user's card showed role, department and join date, so the
  /// only way to learn that someone could hand out work was to open their
  /// permission sheet, one user at a time. There was no answer to "who are my
  /// managers" short of checking all of them. One query for every row is the
  /// difference between a list you can read and a list you have to interrogate.
  ///
  /// RLS decides what lands here, and correctly returns different things to
  /// different viewers: a super_admin sees every grant; a manager sees only
  /// grants for areas they themselves hold (see the
  /// delegate_read_what_they_may_delegate policy). Both are exactly the set
  /// that viewer is allowed to act on, so the badges never promise a control
  /// the database will refuse.
  Map<String, Set<String>> _grantsByUser = {};

  /// permission id of `permissions:delegate` — the one grant that means
  /// "this person may distribute work to others". Null until the catalogue
  /// loads, and every manager check below is false while it is.
  String? _delegatePermId;

  static const _roles = ['all', 'management', 'student', 'teacher', 'admin', 'dept_admin', 'staff', 'exam_controller', 'super_admin'];

  bool _isManager(Map<String, dynamic> user) =>
      _delegatePermId != null &&
      (_grantsByUser[user['id']]?.contains(_delegatePermId) ?? false);

  /// Areas a user can act in, NOT counting `permissions:delegate` itself.
  /// Being allowed to hand out work is not itself a job, and counting it as
  /// one makes a manager with nothing to distribute look equipped.
  int _areaCount(Map<String, dynamic> user) {
    final g = _grantsByUser[user['id']];
    if (g == null) return 0;
    return g.where((id) => id != _delegatePermId).length;
  }

  Future<void> _loadViewerRole() async {
    final role = await RoleSession.ensureLoaded();
    final grants = await PermissionSession.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _isSuperAdmin = role == 'super_admin';
      // A super_admin holds everything without needing a row for it.
      _canApproveUsers = _isSuperAdmin || grants.contains('users:approve');
      _canApproveCr    = _isSuperAdmin || grants.contains('cr:approve');
      _canAssignRoles  = _isSuperAdmin || grants.contains('roles:assign');
      _canDelegate     = _isSuperAdmin || grants.contains('permissions:delegate');
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

  Future<void> _loadGrants() async {
    try {
      final delegateRow = await SupabaseConfig.client
          .from('permissions').select('id')
          .eq('resource', 'permissions').eq('action', 'delegate').maybeSingle();
      final rows = await SupabaseConfig.client
          .from('user_permissions').select('user_id, permission_id') as List;
      final map = <String, Set<String>>{};
      for (final r in rows.cast<Map<String, dynamic>>()) {
        (map[r['user_id'] as String] ??= <String>{}).add(r['permission_id'] as String);
      }
      if (mounted) {
        setState(() {
          _grantsByUser = map;
          _delegatePermId = delegateRow?['id'] as String?;
        });
      }
    } catch (_) {
      // Deliberately silent, and deliberately not surfaced as _error. These
      // are badges on a list that is otherwise fine; failing to decorate a row
      // is not a reason to replace the whole user list with an error state.
    }
  }

  @override
  void initState() {
    super.initState();
    // Starts at 1 — the All Users tab everyone here gets — and grows to 3 once
    // the viewer proves to be super_admin. Same reasoning as _isSuperAdmin
    // defaulting false: never flash controls that may not be theirs.
    _tab = TabController(length: 1, vsync: this);
    _loadViewerRole().then((_) {
      _loadPending();
      _loadStuck();
    });
    _load();
    _loadFacets();
    _loadGroups();
    _loadGrants();
    _loadCrRequests();
    // Next page when the list nears its end. AdaptiveList is bounded now, so
    // "everyone in the university" is never a single scroll view.
    _listScroll.addListener(() {
      if (!_hasMore || _loadingMore || _loading) return;
      if (_listScroll.position.pixels >= _listScroll.position.maxScrollExtent - 400) {
        _loadingMore = true;
        _load(reset: false);
      }
    });
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
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _listScroll.dispose();
    _sub?.unsubscribe();
    _crSub?.unsubscribe();
    // Cancel any queued refetch, or it fires against an unmounted widget.
    _refresh.dispose();
    _crRefresh.dispose();
    super.dispose();
  }

  /// The filter set the RPCs take. One place, so the facet counts and the row
  /// query can never describe different populations.
  Map<String, dynamic> get _filterArgs => {
        // 'management' is a GRANT, not a profiles.role, so it cannot be a
        // server-side role filter — it is handled by _loadManagement().
        'p_role': (_roleFilter == 'all' || _roleFilter == 'management') ? null : _roleFilter,
        'p_batch': _fBatch,
        'p_section': _fSection,
        'p_department_id': _fDepartmentId,
        'p_semester': _fSemester,
        'p_q': _search.trim().isEmpty ? null : _search.trim(),
      };

  /// The group headings and their counts for the current role and filters.
  /// Cheap enough to reload with the facets: one grouped aggregate, no rows.
  Future<void> _loadGroups() async {
    if (!_grouped) {
      if (mounted) setState(() { _groups = []; _groupsError = null; });
      return;
    }
    if (mounted) setState(() { _groupsLoading = true; _groupsError = null; });
    try {
      final res = await SupabaseConfig.client.rpc('admin_user_groups', params: {
        'p_role': _roleFilter,
        'p_q': _search.trim().isEmpty ? null : _search.trim(),
        'p_verified': null,
        'p_department_id': _fDepartmentId,
      });
      if (!mounted) return;
      setState(() {
        _groups = ((res as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(UserGroup.fromJson)
            .toList();
        _groupsLoading = false;
      });
    } catch (e) {
      // Same rule as the row list: a failed fetch must not render as "no
      // groups", which reads as "nobody works here".
      if (mounted) {
        setState(() { _groupsError = friendlyError(e); _groupsLoading = false; });
      }
    }
  }

  /// The rows inside one opened group. Uses the same keys the group was
  /// counted with, so the count and the rows describe one population.
  Future<List<Map<String, dynamic>>> _rowsForGroup(UserGroup g) async {
    final params = <String, dynamic>{
      'p_role': _roleFilter,
      'p_department_id': _fDepartmentId,
      'p_q': _search.trim().isEmpty ? null : _search.trim(),
      'p_limit': 200,
    };
    if (_roleFilter == 'student') {
      // l1key is "<year>|<season>", or the literal 'unset' for the people who
      // have not given an intake term yet -- a real group somebody has to work
      // through, not an absence of filter.
      if (g.l1Key == 'unset') {
        params['p_admission_year'] = 'unset';
        params['p_admission_season'] = 'unset';
      } else {
        final parts = g.l1Key.split('|');
        params['p_admission_year'] = parts.first;
        params['p_admission_season'] = parts.length > 1 ? parts[1] : null;
      }
      if (g.l2Key != 'unset') params['p_batch'] = g.l2Key;
    } else {
      params['p_joined_year'] = g.l2Key;
      if (_roleFilter == 'staff') params['p_staff_category'] = g.l1Key;
      if (_roleFilter == 'teacher' && g.l1Key != 'unset') {
        params['p_department_id'] = g.l1Key;
      }
    }
    final res = await SupabaseConfig.client
        .rpc('admin_search_users', params: params) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// One page of the directory. [reset] restarts from the newest row and
  /// clears the accumulated list; otherwise this appends the next page.
  Future<void> _load({bool reset = true}) async {
    if (reset) {
      _cursorCreatedAt = null;
      _cursorId = null;
      _hasMore = true;
      if (mounted) setState(() => _loading = true);
    }
    if (_roleFilter == 'management') return _loadManagement();

    try {
      final res = await SupabaseConfig.client.rpc('admin_search_users', params: {
        ..._filterArgs,
        'p_verified': null,
        'p_limit': 50,
        'p_cursor_created_at': _cursorCreatedAt,
        'p_cursor_id': _cursorId,
      }) as List;
      final page = res.cast<Map<String, dynamic>>();
      if (!mounted) return;
      setState(() {
        _users = reset ? page : [..._users, ...page];
        _hasMore = page.length == 50;
        if (page.isNotEmpty) {
          _cursorCreatedAt = page.last['created_at'] as String?;
          _cursorId = page.last['id'] as String?;
        }
        _error = null;
        _loading = false;
        _loadingMore = false;
        _firstLoad = false;
      });
    } catch (e) {
      // A silent failure here rendered as "No pending approvals"/"No users
      // found" — the approval queue looking empty is exactly the wrong
      // thing to fake when the load actually failed.
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; _loadingMore = false; _firstLoad = false; });
    }
  }

  /// The Management tier cuts across roles and lives in user_permissions, not
  /// profiles.role, so it is resolved from the grants map already loaded for
  /// the badges. Bounded by the number of grant holders (tens), never by the
  /// size of the university.
  Future<void> _loadManagement() async {
    try {
      final ids = _grantsByUser.entries
          .where((e) => _delegatePermId != null && e.value.contains(_delegatePermId))
          .map((e) => e.key).toList();
      if (ids.isEmpty) {
        if (mounted) setState(() { _users = []; _hasMore = false; _error = null; _loading = false; });
        return;
      }
      final res = await SupabaseConfig.client.from('profiles')
          .select('id, full_name, email, phone, role, university_id, department, batch, section, '
              'teacher_initial, gender, emergency_contact, avatar_url, is_verified, created_at')
          .inFilter('id', ids)
          .order('created_at', ascending: false) as List;
      if (mounted) {
        setState(() {
          _users = res.cast();
          _hasMore = false;
          _error = null;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  /// Facet counts for the current drill level.
  Future<void> _loadFacets() async {
    try {
      final res = await SupabaseConfig.client.rpc('admin_user_facets', params: {
        ..._filterArgs,
        'p_verified': null,
      });
      if (mounted && res is Map) setState(() => _facets = Map<String, dynamic>.from(res));
    } catch (_) {
      // Facets decorate the screen; losing them must not replace a working
      // list with an error state.
    }
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
    final ok = await _confirmAction(
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
    final ok = await _confirmAction(
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

  Future<void> _refreshAll() async {
    await Future.wait([_load(), _loadFacets(), _loadPending()]);
  }

  void _onFilterChanged() {
    _load();
    _loadFacets();
    _loadGroups();
  }

  /// Reads one facet array out of the server's counts. Returns
  /// `[{value, count, label?}, …]` — the shape admin_user_facets emits.
  List<Map<String, dynamic>> _facetList(String key) =>
      ((_facets[key] as List?) ?? const []).cast<Map<String, dynamic>>();

  int get _totalUsers => (_facets['total'] as num?)?.toInt() ?? _users.length;

  /// One drill level: a labelled row of chips with live counts. Renders
  /// nothing at all when the level has no values, so the bar only ever shows
  /// levels that can actually narrow the set.
  Widget _drillLevel({
    required String title,
    required List<Map<String, dynamic>> values,
    required String? selected,
    required void Function(String?) onPick,
    String Function(Map<String, dynamic>)? labelOf,
  }) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textSecondaryOf(context), letterSpacing: 1.1)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in values)
            GlassChip(
              label: '${labelOf?.call(v) ?? v['value']} (${v['count']})',
              selected: selected == '${v['value']}',
              color: AppColors.holoBlue,
              // Tapping the selected chip clears that level — the way back up
              // the tree without hunting for a separate "clear" affordance.
              onTap: () => onPick(selected == '${v['value']}' ? null : '${v['value']}'),
            ),
        ]),
      ]),
    );
  }

  void _onSearchChanged(String v) {
    _search = v;
    _searchDebounce?.cancel();
    // Debounced because every keystroke is now a round trip, not a filter over
    // a local list. 300ms is below the threshold where typing feels laggy and
    // well above per-character chatter.
    _searchDebounce = Timer(const Duration(milliseconds: 300), _onFilterChanged);
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

  // _pending and _filtered used to be getters computed over a full download of
  // every profile. Both are now server-side: _pending is its own filtered
  // query (_loadPending) and the directory is one keyset page at a time
  // (_load), so `_users` IS the filtered result rather than a superset to sift.
  List<Map<String, dynamic>> get _filtered => _users;

  /// The approval queue, grouped by role, in the order the roles are listed on
  /// this screen so the queue and the directory agree about what comes first.
  /// A LinkedHashMap — insertion order is the display order.
  Map<String, List<Map<String, dynamic>>> get _pendingByRole {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final r in _roles) {
      if (r == 'all' || r == 'management') continue;
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
      // round-trip to come back and call _load(). The subscription is still the
      // thing that keeps OTHER admins' screens in sync, but making the acting
      // admin's own list depend on a WAL round-trip is what made an approval
      // look like it hadn't registered -- the row sat in "Pending" until the
      // event arrived, or until the screen was left and reopened. The reload
      // below still runs, so this is a head start, not a substitute for truth.
      if (mounted) {
        setState(() {
          final idx = _users.indexWhere((u) => u['id'] == user['id']);
          if (idx >= 0) _users[idx] = {..._users[idx], 'is_verified': true};
          // The queue is its own server-side query now, so the approved row
          // has to leave it here too — otherwise it sits in Pending until the
          // refetch lands, which is the exact lag this head start exists to
          // avoid.
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

  Future<bool> _confirmAction(String title, String message, String confirmLabel) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
              backgroundColor: AppColors.surfaceOf(dCtx),
              title: Text(title, style: TextStyle(color: AppColors.textPrimaryOf(dCtx))),
              content: Text(message, style: TextStyle(color: AppColors.textSecondaryOf(dCtx))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dCtx, true), child: Text(confirmLabel, style: const TextStyle(color: AppColors.red))),
              ],
            ));
    return confirm == true;
  }

  Future<void> _rejectAndDelete(Map<String, dynamic> user) async {
    final confirm = await _confirmAction('Reject ${user['full_name']}?',
        'This permanently deletes the account so they can sign up again with the correct role.',
        'Reject & Delete');
    if (!confirm) return;
    await _deleteUser(user);
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    try {
      final res = await SupabaseConfig.client.functions.invoke('delete-user', body: {'targetUserId': user['id']});
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      if (mounted) {
        // Destructive and unrecoverable — the heaviest verb in the vocabulary.
        AppHaptics.warning();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user['full_name']} deleted'), backgroundColor: AppColors.green));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> user) async {
    if (user['id'] == SupabaseConfig.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot delete your own account'), backgroundColor: AppColors.red));
      return;
    }
    final confirm = await _confirmAction('Delete ${user['full_name']} entirely?',
        'This removes the account and every row/photo/post tied to it, everywhere. This cannot be undone.',
        'Delete Everything');
    if (confirm) await _deleteUser(user);
  }

  // Roles a super-admin can assign. `all` is only a filter, not a role.
  static const _assignableRoles = ['student', 'teacher', 'staff', 'admin', 'dept_admin', 'exam_controller', 'super_admin'];

  /// What a `roles:assign` holder may set, as opposed to a super_admin.
  ///
  /// This list is a MIRROR, not the rule. The rule is the `c_assignable` array
  /// in `protect_profile_privileged_columns`, which refuses anything else no
  /// matter what the client sends. Duplicating it here is what stops the
  /// picker offering "Super Admin" to someone who would then get a trigger
  /// exception quoting a Postgres array — the same reason the permission
  /// catalogue is filtered for a delegate.
  ///
  /// These four are exactly the roles that confer no authority over other
  /// people. Handing out admin, dept_admin or super_admin stays the
  /// super_admin's own decision.
  static const _delegateAssignableRoles = ['student', 'teacher', 'staff', 'exam_controller'];

  Future<String?> _pickRole(String current) => showGlassModal<String>(context,
      builder: (sheetCtx) => SafeArea(child: SingleChildScrollView(
        // Sheet content — GlassSheet's SafeArea already applies the nav inset.
        padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Assign a role', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
          const SizedBox(height: 4),
          Text(
              _isSuperAdmin
                  ? 'Takes effect immediately — access is enforced by the database (RLS).'
                  : 'Takes effect immediately, enforced by the database. Admin '
                    'and Super Admin are not on this list: those roles carry '
                    'authority over other people, so only a super-admin can '
                    'assign them.',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
          const SizedBox(height: 12),
          ...(_isSuperAdmin ? _assignableRoles : _delegateAssignableRoles).map((r) {
            final sel = r == current;
            final c = _UserCard._roleColors[r] ?? AppColors.textSecondary;
            return ListTile(
              dense: true,
              leading: Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: c, size: 20),
              title: Text(roleLabel(r), style: TextStyle(color: AppColors.textPrimaryOf(sheetCtx),
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
              trailing: sel ? Text('current', style: TextStyle(color: AppColors.textSecondaryOf(sheetCtx), fontSize: 11)) : null,
              onTap: () => Navigator.pop(sheetCtx, r),
            );
          }),
        ]),
      )));

  /// Super-admin changes another user's role. `profiles.role` (text) is the
  /// authorization source of truth (`get_my_profile_role()`); `role_id` is kept
  /// in sync from the `roles` table so the permission joins stay consistent.
  /// The existing RLS policy (`admin_manage_all_profiles`) + privileged-column
  /// trigger already permit a super-admin to write another user's role.
  Future<void> _setRole(Map<String, dynamic> user) async {
    if (user['id'] == SupabaseConfig.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You can't change your own role"), backgroundColor: AppColors.red));
      return;
    }
    final current = user['role'] as String? ?? 'student';
    // Taking authority away is as consequential as granting it: without this,
    // a roles:assign holder could demote an admin to student and then promote
    // them back to anything on their own list. The trigger refuses it too —
    // this is so the refusal arrives as a sentence rather than a Postgres
    // exception after the picker has already been used.
    if (!_isSuperAdmin && !_delegateAssignableRoles.contains(current)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Only a super-admin can change the role of a '
              '${roleLabel(current)}.'),
          backgroundColor: AppColors.amber));
      return;
    }
    final picked = await _pickRole(current);
    if (picked == null || picked == current || !mounted) return;
    final confirm = await _confirmAction('Change role?',
        'Set ${user['full_name'] ?? 'this user'}\'s role to "$picked"? Their access changes immediately.',
        'Change role');
    if (!confirm) return;
    try {
      // Through the RPC, not a direct UPDATE. `admin_manage_all_profiles` is
      // admin/super_admin only, so for a roles:assign holder a direct write
      // affected ZERO ROWS — silently, because RLS filters rather than errors,
      // which reads as "I pressed the button and nothing happened".
      //
      // The RPC grants reach, not permission: it checks the grant, and
      // protect_profile_privileged_columns still enforces the ceiling, the
      // self-edit ban and the "you cannot change an admin's role" rule. It
      // also keeps role_id in sync with role, which the old two-field update
      // did by hand and could get half-right.
      await SupabaseConfig.client.rpc('set_user_role', params: {
        'p_user_id': user['id'],
        'p_role': picked,
      });
      await NotificationService.sendToUsers(
        userIds: [user['id'] as String],
        title: 'Your role was updated',
        message: 'A super-admin set your AFOS account role to "$picked".',
        category: 'general',
      );
      if (mounted) {
        // Granting or removing privilege. Same weight as a delete: the admin
        // must feel that this landed.
        AppHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${user['full_name'] ?? 'User'} is now "$picked"'), backgroundColor: AppColors.green));
      }
      _load();

      // STAFF STARTS WITH NOTHING, AND NOBODY WAS TOLD.
      //
      // `staff` is the one role whose menu is built ENTIRELY from delegated
      // grants (slide_menu.dart's `staffMenuRoutes`), so setting someone to
      // staff and stopping there gives them home/transport/lost & found and no
      // job. That is exactly what happened: `user_permissions` held ZERO rows
      // app-wide while a staff member was waiting to upload routines, because
      // "set the role" and "grant the areas" are two unrelated buttons and only
      // the first looks like the whole task.
      //
      // So the moment a role becomes staff, say so and offer the second step
      // rather than leaving it to be discovered.
      if (mounted && picked == 'staff') {
        await _promptToAssignAreas(user);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  /// Offered immediately after a user is made `staff`.
  ///
  /// Not a snackbar: this is a step the admin has to take, and a message that
  /// disappears after four seconds is how the step got skipped in the first
  /// place. Declining is allowed — some staff genuinely need no admin area —
  /// but it has to be a decision rather than an omission.
  Future<void> _promptToAssignAreas(Map<String, dynamic> user) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(ctx),
        title: Text('Assign their work areas',
            style: TextStyle(color: AppColors.textPrimaryOf(ctx))),
        content: Text(
          'Staff accounts start with no admin tools at all. '
          '${user['full_name'] ?? 'This user'} cannot upload routines, manage '
          'a hall or publish notices until you grant those areas — the role on '
          'its own does nothing.',
          style: TextStyle(color: AppColors.textSecondaryOf(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('They need none',
                style: TextStyle(color: AppColors.textSecondaryOf(ctx))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.holoviolet),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Assign areas'),
          ),
        ],
      ),
    );
    if (go == true && mounted) await _managePermissions(user);
  }

  /// Promote someone into — or out of — the management tier, in one action.
  ///
  /// WHAT WAS WRONG. The tier existed in the database the moment
  /// `permissions:delegate` was added, but there was no way to *appoint*
  /// anyone: a super-admin had to open a 26-row checkbox list and know that
  /// the row reading "Permissions: delegate" was the one that means "this
  /// person can now hand out work to others". It sat between "Notice: publish"
  /// and "Routine: upload" looking like just another area. Appointing a
  /// manager is a decision about authority, not a checkbox, so it gets its own
  /// action that says what it does.
  ///
  /// It also does the second half nobody remembered: a manager may only pass
  /// on areas they themselves hold, so a manager with zero areas can
  /// distribute NOTHING. Promoting without granting areas produces a manager
  /// who opens the sheet to an empty list — the same dead end that made staff
  /// accounts useless. So the area picker follows immediately.
  Future<void> _toggleManager(Map<String, dynamic> user) async {
    final permId = _delegatePermId;
    if (permId == null) return;
    final name = user['full_name'] ?? 'This user';
    final isManager = _isManager(user);

    if (user['id'] == SupabaseConfig.uid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("You can't change your own management access"),
          backgroundColor: AppColors.red));
      return;
    }

    final areas = _areaCount(user);
    final ok = await _confirmAction(
      isManager ? 'Remove management access?' : 'Make $name a manager?',
      isManager
          ? '$name will keep their own work areas but can no longer give any '
            'of them to anyone else. Areas they already handed out stay in '
            'place — this stops them distributing more, it does not undo what '
            'they did.'
          : '$name will be able to give their own work areas to other people, '
            'and to take them back. They can never grant an area they do not '
            'hold themselves, so they cannot promote anyone above their own '
            'level — including themselves.'
            '${areas == 0 ? '\n\nThey hold no areas yet, so they would have '
                'nothing to give. Assign areas on the next screen.' : ''}',
      isManager ? 'Remove access' : 'Make manager',
    );
    if (!ok) return;

    try {
      if (isManager) {
        await SupabaseConfig.client.from('user_permissions').delete()
            .eq('user_id', user['id']).eq('permission_id', permId);
      } else {
        await SupabaseConfig.client.from('user_permissions').insert({
          'user_id': user['id'], 'permission_id': permId,
          'granted_by': SupabaseConfig.uid,
        });
      }
      await NotificationService.sendToUsers(
        userIds: [user['id'] as String],
        title: isManager ? 'Management access removed' : 'You are now a manager',
        message: isManager
            ? 'You can no longer assign your work areas to other people.'
            : 'You can now assign your own work areas to other people from '
              'Assign Work Areas.',
        category: 'general',
      );
      await _loadGrants();
      if (!mounted) return;
      AppHaptics.success();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isManager
              ? '$name is no longer a manager'
              : '$name can now distribute their work areas'),
          backgroundColor: isManager ? AppColors.amber : AppColors.green));

      // Straight into the areas, because a manager holding nothing is a
      // manager who can do nothing.
      if (!isManager && _areaCount(user) == 0) await _managePermissions(user);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  /// Grants ONE specific admin area to a user without changing their role —
  /// "distribute admin work" (e.g. a student handles transport uploads
  /// without becoming a full `admin`). Writes to `user_permissions`, which
  /// `caller_can(resource, action)` already reads from at the RLS layer
  /// (transport_routes, schedule_slots, exam_room_allocations, notices,
  /// halls, hall_applications, sos_alerts, books, borrowed_books,
  /// conference_room_requests) and PermissionSession reads client-side for
  /// the matching /admin/* router guards — a grant made here takes effect
  /// immediately end to end, not just as a UI checkbox.
  Future<void> _managePermissions(Map<String, dynamic> user) async {
    List<Map<String, dynamic>> catalog;
    Set<String> granted;
    try {
      final catalogRes = await SupabaseConfig.client
          .from('permissions').select('id, resource, action, scope')
          .order('resource').order('action') as List;
      catalog = catalogRes.cast<Map<String, dynamic>>();
      final grantedRes = await SupabaseConfig.client
          .from('user_permissions').select('permission_id')
          .eq('user_id', user['id']) as List;
      granted = grantedRes.map((r) => r['permission_id'] as String).toSet();

      // A DELEGATE MAY ONLY PASS ON WHAT THEY THEMSELVES HOLD.
      //
      // The database enforces this — `delegate_grant_only_what_they_hold`
      // refuses anything else — but a checkbox the server will reject is a
      // trap: the admin ticks it, saves, and gets a permission error with no
      // explanation of which box caused it. So the catalogue a non-super_admin
      // sees is narrowed to their own grants, and the rule is visible in the
      // UI rather than only discoverable by hitting it.
      if (!_isSuperAdmin) {
        final mineRes = await SupabaseConfig.client
            .from('user_permissions').select('permission_id')
            .eq('user_id', SupabaseConfig.uid!) as List;
        final mine = mineRes.map((r) => r['permission_id'] as String).toSet();
        catalog = catalog.where((p) =>
            mine.contains(p['id']) &&
            // ...except the one permission a manager holds but may not pass
            // on. Appointing managers is super_admin's, so the manager tier
            // cannot widen itself: otherwise one manager could clone their
            // own authority to anyone, and the only trace would be an audit
            // row nobody was watching. The database refuses this too — the
            // checkbox is removed so it never looks available.
            !(p['resource'] == 'permissions' && p['action'] == 'delegate')
        ).toList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
      return;
    }
    if (!mounted) return;
    final selected = Set<String>.of(granted);
    final saved = await showGlassModal<bool>(context,
        builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheetState) => SafeArea(
            child: SingleChildScrollView(
                // No NavInsets here: this is sheet content, and GlassSheet's
                // own SafeArea already consumes the shell's nav inset. Adding
                // it again stacked a second ~107px of dead space inside the
                // sheet.
                padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 24),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Permissions for ${user['full_name'] ?? 'this user'}',
                      style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
                  const SizedBox(height: 4),
                  Text('Delegates ONE specific admin area without changing their role — '
                      'e.g. grant "transport: upload" so they can update bus routes without being made an admin. '
                      'Takes effect immediately, enforced by the database.',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
                  const SizedBox(height: 12),
                  for (final p in catalog)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.holoviolet,
                      value: selected.contains(p['id']),
                      onChanged: (v) => setSheetState(() {
                        if (v == true) {
                          selected.add(p['id'] as String);
                        } else {
                          selected.remove(p['id']);
                        }
                      }),
                      title: Text('${_titleCase(p['resource'] as String)}: ${p['action']}',
                          style: TextStyle(color: AppColors.textPrimaryOf(sheetCtx), fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text('scope: ${p['scope']}',
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.holoviolet),
                      onPressed: () => Navigator.pop(sheetCtx, true),
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Save permissions'))),
                ])))));
    if (saved != true || !mounted) return;

    final toGrant = selected.difference(granted);
    final toRevoke = granted.difference(selected);
    if (toGrant.isEmpty && toRevoke.isEmpty) return;
    try {
      if (toGrant.isNotEmpty) {
        await SupabaseConfig.client.from('user_permissions').insert([
          for (final id in toGrant) {'user_id': user['id'], 'permission_id': id, 'granted_by': SupabaseConfig.uid},
        ]);
      }
      if (toRevoke.isNotEmpty) {
        await SupabaseConfig.client.from('user_permissions').delete()
            .eq('user_id', user['id']).inFilter('permission_id', toRevoke.toList());
      }
      await NotificationService.sendToUsers(
        userIds: [user['id'] as String],
        title: 'Your permissions were updated',
        // Not "a super-admin" any more — a manager can be the one doing this,
        // and telling the recipient it was a super-admin when it was their
        // department's manager is a small untruth the app has no reason to tell.
        message: 'Your work areas in AFOS were changed. Open the menu to see '
            'what you can now access.',
        category: 'general',
      );
      // The badges on the list are now stale by exactly this change.
      await _loadGrants();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Permissions updated for ${user['full_name'] ?? 'user'}'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

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
              child: Row(children: _isSuperAdmin
                  ? [
                      Expanded(child: _StatTile(label: 'Pending', value: _pending.length)),
                      _StatDivider(),
                      Expanded(child: _StatTile(label: 'CR Requests', value: _crRequests.length)),
                      _StatDivider(),
                      // The DATABASE's count, not `_users.length`. Those were
                      // the same number only while the screen downloaded every
                      // profile; now the list holds one page, so counting it
                      // would report "50 users" for a university of 25,000.
                      Expanded(child: _StatTile(label: 'Total Users', value: _totalUsers)),
                    ]
                  : [
                      // No "Managers" count here. A manager cannot READ who
                      // else holds permissions:delegate — that is deliberate,
                      // so the tier cannot be enumerated from inside it — and
                      // a tile reading 0 would be a confident lie rather than
                      // an absence. What they can see is their own remit.
                      Expanded(child: _StatTile(
                          label: 'In your areas',
                          value: _users.where((u) => _areaCount(u) > 0).length)),
                      _StatDivider(),
                      Expanded(child: _StatTile(label: 'Total Users', value: _users.length)),
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
                    'cr' => GlassTab('CR Requests (${_crRequests.length})', icon: Icons.badge_rounded),
                    _ => const GlassTab('All Users', icon: Icons.people_alt_rounded),
                  },
              ],
            ),
          ),
        Expanded(child: _loading && _firstLoad
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
            : TabBarView(controller: _tab, children: [
                if (_canApproveUsers) ...[
                _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
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
                              _UserCard(key: ValueKey(u['id']), user: u, pending: true,
                                  onApprove: () => _approve(u),
                                  onReject: _isSuperAdmin ? () => _rejectAndDelete(u) : null,
                                  onDelete: _isSuperAdmin ? () => _confirmDelete(u) : null),
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
                Column(children: [
                  // THE EXPRESS LANE, kept first and always visible. An admin
                  // who knows the ID types it and lands on the record without
                  // touching a single facet — the 90% case. It is now a
                  // SERVER-side search (indexed, prefix-matched on ID/email,
                  // trigram on name), so it finds people who were never
                  // downloaded; the old one could only search the local list.
                  Padding(padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8), child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      style: TextStyle(color: AppColors.textPrimaryOf(context)),
                      decoration: InputDecoration(
                          hintText: 'Search by ID, email or name — fastest way in',
                          prefixIcon: const Icon(Icons.search),
                          filled: true, fillColor: AppColors.glassFill(context),
                          border: OutlineInputBorder(borderRadius: AppDepth.radius(1), borderSide: BorderSide.none)))),

                  // DRILL-DOWN, not one flat list of everybody.
                  //
                  // Each level shows only the values that exist beneath the
                  // level above it, with counts from the database rather than
                  // from whatever happened to be downloaded. Role first,
                  // because it decides which levels below even apply:
                  // students segment by batch/section/semester, teachers and
                  // staff by department and designation.
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('ROLE', style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textSecondaryOf(context), letterSpacing: 1.1)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, runSpacing: 8,
                        // The Management filter is super_admin's: a manager
                        // cannot read who else holds permissions:delegate, so
                        // for them the filter would always come back empty.
                        children: _roles
                            .where((r) => r != 'management' || _isSuperAdmin)
                            .map((r) {
                          final counts = {
                            for (final e in _facetList('roles')) '${e['value']}': e['count'],
                          };
                          // 'management' is not in the roles table, so roleLabel
                          // would render the raw key. It is a grant, shown here
                          // because "who can hand out work" is a question this
                          // list previously could not answer at all.
                          final label = switch (r) {
                            'all' => 'All ($_totalUsers)',
                            'management' => 'Management (${_grantsByUser.values.where((g) => _delegatePermId != null && g.contains(_delegatePermId)).length})',
                            _ => '${roleLabel(r)} (${counts[r] ?? 0})',
                          };
                          return GlassChip(
                            label: label,
                            selected: r == _roleFilter,
                            color: AppColors.holoviolet,
                            onTap: () {
                              setState(() {
                                _roleFilter = r;
                                // Levels below role are meaningless once role
                                // changes — a section of teachers is not a
                                // thing — so the whole path resets.
                                _fBatch = null; _fSection = null;
                                _fSemester = null; _fDepartmentId = null;
                              });
                              _onFilterChanged();
                            });
                        }).toList()),
                    ]),
                  ),

                  if (_roleFilter == 'student') ...[
                    _drillLevel(
                      title: 'Batch',
                      values: _facetList('batches'),
                      selected: _fBatch,
                      onPick: (v) {
                        setState(() { _fBatch = v; _fSection = null; });
                        _onFilterChanged();
                      },
                    ),
                    // Section only once a batch is chosen: "section A" across
                    // every batch in the university is not a group anyone
                    // manages.
                    if (_fBatch != null)
                      _drillLevel(
                        title: 'Section',
                        values: _facetList('sections'),
                        selected: _fSection,
                        onPick: (v) { setState(() => _fSection = v); _onFilterChanged(); },
                      ),
                    _drillLevel(
                      title: 'Semester',
                      values: _facetList('semesters'),
                      selected: _fSemester?.toString(),
                      onPick: (v) {
                        setState(() => _fSemester = v == null ? null : int.tryParse(v));
                        _onFilterChanged();
                      },
                    ),
                  ],

                  if (_roleFilter != 'all' && _roleFilter != 'management')
                    _drillLevel(
                      title: 'Department',
                      values: _facetList('departments'),
                      selected: _fDepartmentId,
                      labelOf: (m) => '${m['label'] ?? m['value']}',
                      onPick: (v) {
                        setState(() => _fDepartmentId = v);
                        _onFilterChanged();
                      },
                    ),

                  const SizedBox(height: 8),
                  Expanded(child: _error != null
                      ? ErrorView(message: _error!, onRetry: _load)
                      : _grouped
                      // BROWSING: sections, in the shape the people are
                      // actually organised in. Rows load per group, so opening
                      // one intake never downloads the rest of the university.
                      ? (_groupsError != null
                          ? ErrorView(message: _groupsError!, onRetry: _loadGroups)
                          : _groupsLoading
                          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
                          : _groups.isEmpty
                          ? const EmptyState(
                              icon: Icons.people_outline,
                              title: 'No one in this group',
                              subtitle: 'Try a different role or clear the filters')
                          : UserGroupTree(
                              groups: _groups,
                              rowsFor: _rowsForGroup,
                              padding: EdgeInsetsDirectional.fromSTEB(
                                  16, 16, 16, 16 + NavInsets.of(context)),
                              itemBuilder: (u) => _UserCard(
                                  key: ValueKey(u['id']), user: u, pending: false,
                                  isManager: _isManager(u),
                                  areaCount: _areaCount(u),
                                  onDelete: _isSuperAdmin ? () => _confirmDelete(u) : null,
                                  onChangeRole: _canAssignRoles ? () => _setRole(u) : null,
                                  onToggleManager: _isSuperAdmin ? () => _toggleManager(u) : null,
                                  onManagePermissions: _canDelegate ? () => _managePermissions(u) : null),
                            ))
                      : _filtered.isEmpty
                      ? const EmptyState(icon: Icons.people_outline, title: 'No users found', subtitle: 'Try a different search or filter')
                      : AdaptiveList(
                          // Paging is driven off this controller (see
                          // initState): the list is now one 50-row page that
                          // extends as you reach the end, instead of every
                          // profile in the university held in memory at once.
                          controller: _listScroll,
                          padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: _filtered.length,
                          // This tab's _UserCard is always pending:false (no
                          // conditional Approve/Reject row like the Pending
                          // tab above), so every row shares one fixed
                          // template — guarded by the _filtered.isEmpty
                          // ternary above, so .first is safe.
                          // A delegate gets the permission sheet and nothing
                          // else. Changing a role or deleting an account stays
                          // super_admin's, and the database refuses both for a
                          // delegate independently of this.
                          // Appointing a manager is super_admin's alone. A
                          // manager handing out management would let the tier
                          // grow itself sideways with no one able to see it
                          // happen; the database refuses it independently
                          // (delegate_grant_only_what_they_hold requires the
                          // delegate to hold permissions:delegate, and the
                          // super_admin path is what the UI must not imply).
                          // EACH CONTROL FOLLOWS ITS OWN GRANT.
                          //
                          // Deleting an account is the single most destructive
                          // thing in the app and stays super_admin's, with no
                          // permission for it in the catalogue at all.
                          // Appointing a manager is super_admin's too, so the
                          // tier cannot recruit itself sideways. Role changes
                          // follow roles:assign, bounded by a ceiling in the
                          // trigger. Distributing work follows
                          // permissions:delegate.
                          prototypeItem: _UserCard(user: _filtered.first, pending: false,
                              isManager: _isManager(_filtered.first),
                              areaCount: _areaCount(_filtered.first),
                              onDelete: _isSuperAdmin ? () => _confirmDelete(_filtered.first) : null,
                              onChangeRole: _canAssignRoles ? () => _setRole(_filtered.first) : null,
                              onToggleManager: _isSuperAdmin ? () => _toggleManager(_filtered.first) : null,
                              onManagePermissions: _canDelegate ? () => _managePermissions(_filtered.first) : null),
                          itemBuilder: (ctx, i) => _UserCard(key: ValueKey(_filtered[i]['id']), user: _filtered[i], pending: false,
                              isManager: _isManager(_filtered[i]),
                              areaCount: _areaCount(_filtered[i]),
                              onDelete: _isSuperAdmin ? () => _confirmDelete(_filtered[i]) : null,
                              onChangeRole: _canAssignRoles ? () => _setRole(_filtered[i]) : null,
                              onToggleManager: _isSuperAdmin ? () => _toggleManager(_filtered[i]) : null,
                              onManagePermissions: _canDelegate ? () => _managePermissions(_filtered[i]) : null))),
                ]),
              ])),
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

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
      width: 0.5, height: 32, color: AppColors.borderOf(context));
}

class _UserCard extends StatelessWidget {
  final Map<String, dynamic> user; final bool pending;
  final VoidCallback? onApprove, onReject, onDelete, onChangeRole, onManagePermissions, onToggleManager;

  /// Holds `permissions:delegate` — may hand their own areas to others.
  final bool isManager;

  /// Delegated areas held, excluding `permissions:delegate` itself.
  final int areaCount;

  const _UserCard({super.key, required this.user, required this.pending, this.onApprove, this.onReject, this.onDelete, this.onChangeRole, this.onManagePermissions, this.onToggleManager, this.isManager = false, this.areaCount = 0});

  static const _roleColors = {
    'super_admin': AppColors.holoviolet, 'admin': AppColors.holoBlue, 'dept_admin': AppColors.holoTeal,
    'teacher': AppColors.gold, 'staff': AppColors.amber, 'exam_controller': AppColors.orange, 'student': AppColors.textSecondary,
  };

  void _showDetails(BuildContext context) {
    final role = user['role'] as String? ?? 'student';
    final color = _roleColors[role] ?? AppColors.textSecondary;
    final createdAt = user['created_at'] != null ? DateTime.tryParse(user['created_at'] as String) : null;
    String fmt(String? v) => (v == null || v.trim().isEmpty) ? 'Not provided' : v;
    final rows = <MapEntry<String, String>>[
      MapEntry('Full name', fmt(user['full_name'] as String?)),
      MapEntry('Email', fmt(user['email'] as String?)),
      MapEntry('Phone', fmt(user['phone'] as String?)),
      MapEntry('Role', roleLabel(role)),
      MapEntry('University ID', fmt(user['university_id'] as String?)),
      MapEntry('Department', fmt(user['department'] as String?)),
      if (role == 'student') MapEntry('Batch', fmt(user['batch'] as String?)),
      if (role == 'student') MapEntry('Section', fmt(user['section'] as String?)),
      if (role == 'teacher') MapEntry('Teacher initial', fmt(user['teacher_initial'] as String?)),
      MapEntry('Gender', fmt(user['gender'] as String?)),
      MapEntry('Emergency contact', fmt(user['emergency_contact'] as String?)),
      MapEntry('Joined', createdAt != null ? AppFormatters.relativeTime(createdAt) : 'Join date unavailable'),
      MapEntry('Approved', user['is_verified'] == true ? 'Yes' : 'Pending approval'),
    ];
    showGlassModal(context,
        builder: (sheetCtx) => SafeArea(
            child: SingleChildScrollView(
                // Sheet content — GlassSheet's SafeArea already applies it.
                padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 24),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 24, backgroundColor: color.withValues(alpha: 0.15),
                        backgroundImage: (user['avatar_url'] as String?)?.isNotEmpty == true ? CachedNetworkImageProvider(user['avatar_url'], maxWidth: 128, maxHeight: 128) : null,
                        child: (user['avatar_url'] as String?)?.isNotEmpty != true
                            ? Text(((user['full_name'] as String?)?.isNotEmpty == true ? (user['full_name'] as String)[0] : '?').toUpperCase(),
                                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18))
                            : null),
                    const SizedBox(width: 14),
                    Expanded(child: Text(fmt(user['full_name'] as String?),
                        style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx)))),
                  ]),
                  const SizedBox(height: 20),
                  ...rows.map((r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 130, child: Text(r.key,
                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(sheetCtx)))),
                        Expanded(child: Text(r.value,
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimaryOf(sheetCtx)))),
                      ]))),
                  if (onChangeRole != null) ...[
                    const SizedBox(height: 18),
                    SizedBox(width: double.infinity, child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.holoviolet),
                        onPressed: () { Navigator.pop(sheetCtx); onChangeRole!(); },
                        icon: const Icon(Icons.manage_accounts_rounded, size: 18),
                        label: const Text('Change role'))),
                  ],
                  if (onManagePermissions != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.holoviolet,
                            side: const BorderSide(color: AppColors.holoviolet)),
                        onPressed: () { Navigator.pop(sheetCtx); onManagePermissions!(); },
                        icon: const Icon(Icons.rule_rounded, size: 18),
                        label: Text(areaCount == 0
                            ? 'Assign work areas'
                            : 'Work areas ($areaCount assigned)'))),
                  ],
                  if (onToggleManager != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: isManager ? AppColors.amber : AppColors.holoTeal,
                            side: BorderSide(color: isManager ? AppColors.amber : AppColors.holoTeal)),
                        onPressed: () { Navigator.pop(sheetCtx); onToggleManager!(); },
                        icon: Icon(isManager
                            ? Icons.person_remove_alt_1_rounded
                            : Icons.supervisor_account_rounded, size: 18),
                        label: Text(isManager
                            ? 'Remove management access'
                            : 'Make a manager'))),
                    const SizedBox(height: 6),
                    Text(
                      isManager
                          ? 'They can pass their own work areas to other people. '
                            'They can never grant an area they do not hold.'
                          : 'A manager can hand their own work areas to other '
                            'people, and take them back — without becoming an admin.',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondaryOf(sheetCtx)),
                    ),
                  ],
                ]))));
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final role = user['role'] as String? ?? 'student';
    final color = _roleColors[role] ?? AppColors.textSecondary;
    final createdAt = user['created_at'] != null ? DateTime.tryParse(user['created_at']) : null;
    return GestureDetector(
      onTap: () => _showDetails(context),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(1),
          border: Border.all(color: pending ? AppColors.gold.withValues(alpha: 0.4) : AppColors.borderOf(context), width: pending ? 1 : 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 20, backgroundColor: color.withValues(alpha: 0.15),
              backgroundImage: (user['avatar_url'] as String?)?.isNotEmpty == true ? CachedNetworkImageProvider(user['avatar_url'], maxWidth: 128, maxHeight: 128) : null,
              child: (user['avatar_url'] as String?)?.isNotEmpty != true
                  ? Text(((user['full_name'] as String?)?.isNotEmpty == true ? (user['full_name'] as String)[0] : '?').toUpperCase(),
                      style: TextStyle(color: color, fontWeight: FontWeight.bold))
                  : null),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user['full_name'] ?? 'Unknown', style: AppTextStyles.titleMedium.copyWith(color: textPrimary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(user['email'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (onDelete != null && !pending)
            IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.red, size: 20), onPressed: onDelete),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppDepth.radius(0)),
              child: Text(roleLabel(role), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700))),
          // AUTHORITY THAT DOES NOT COME FROM THE ROLE.
          //
          // These two facts decide what this person can actually do, and
          // neither is visible in `role`: a `student` holding four areas has
          // more reach than a `staff` holding none. Without them the list
          // answers "what were they signed up as", not "what can they do".
          if (isManager) ...[
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.holoviolet.withValues(alpha: 0.14),
                    borderRadius: AppDepth.radius(0)),
                child: const Text('Manager',
                    style: TextStyle(color: AppColors.holoviolet, fontSize: 11, fontWeight: FontWeight.w700))),
          ],
          if (areaCount > 0) ...[
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.holoTeal.withValues(alpha: 0.14),
                    borderRadius: AppDepth.radius(0)),
                child: Text(areaCount == 1 ? '1 area' : '$areaCount areas',
                    style: const TextStyle(color: AppColors.holoTeal, fontSize: 11, fontWeight: FontWeight.w700))),
          ] else if (isManager) ...[
            // A manager with nothing to give. Worth calling out: they will
            // open the sheet to an empty list and conclude the app is broken.
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.14),
                    borderRadius: AppDepth.radius(0)),
                child: const Text('no areas',
                    style: TextStyle(color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w700))),
          ],
          const SizedBox(width: 8),
          // Expanded, not Flexible-beside-a-Spacer. `Spacer` is an `Expanded`
          // with flex 1 and `Flexible` defaults to flex 1, so the two split the
          // free space 50/50: the department could only use HALF of what was
          // left before ellipsising, with an identical gap sitting next to it.
          // On a narrow phone that rendered a real department as "C…" beside
          // blank space. The Spacer is only needed when there is no department
          // to push "Joined" to the right.
          if ((user['department'] as String?)?.isNotEmpty == true)
            Expanded(child: Text(user['department'], style: TextStyle(color: textSecondary, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis))
          else
            const Spacer(),
          if (createdAt != null) ...[
            const SizedBox(width: 8),
            // Flexible + ellipsis: this is unbounded text at the end of a Row,
            // so at a large text scale it overflowed the card rather than
            // shortening.
            Flexible(
              child: Text('Joined ${AppFormatters.relativeTime(createdAt)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMutedOf(context), fontSize: 10)),
            ),
          ],
        ]),
        if (pending) ...[
          const SizedBox(height: 10),
          Row(children: [
            // A disabled Reject button would still say "you could do this if
            // you tried harder". Absent is the honest rendering for a
            // users:approve holder, whose job is the approving half.
            if (onReject != null) ...[
              Expanded(child: OutlinedButton(onPressed: onReject,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
                  child: const Text('Reject'))),
              const SizedBox(width: 8),
            ],
            Expanded(child: ElevatedButton(onPressed: onApprove,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white),
                child: const Text('Approve'))),
          ]),
        ],
      ]),
    ));
  }
}
