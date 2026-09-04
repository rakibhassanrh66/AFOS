import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/auth/permission_session.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/services/realtime_channel.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/role_labels.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/glass_chip.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../web/presentation/widgets/adaptive_list.dart';
import 'widgets/user_admin_actions_mixin.dart';
import 'widgets/user_card.dart';
import 'widgets/user_group_tree.dart';

/// One role's own place, per the owner's request: tapping a role on the
/// Manage Users landing screen pushes a REAL page for that role, rather than
/// filtering a shared list in place. Reached via `/admin/users/:role`.
///
/// The crowding this replaces: the old single screen stacked a search box,
/// role chips and drill-down chips all above the list in one scrolling
/// column, which is what read as "the search and role picker eat the whole
/// screen, only a sliver is left for the list" on a phone. The search box
/// here has its own fixed slot and never shares scroll space with the list
/// below it — that placement is the literal fix.
///
/// [role] is one of the `profiles.role` values, or the two synthetic values
/// this directory has always understood: 'management' (a grant,
/// `permissions:delegate`, not a stored role) and 'all' (no role filter —
/// where the landing screen's "Total Users" tile now goes).
class UserDirectoryScreen extends StatefulWidget {
  final String role;
  const UserDirectoryScreen({super.key, required this.role});

  @override
  State<UserDirectoryScreen> createState() => _UserDirectoryScreenState();
}

class _UserDirectoryScreenState extends State<UserDirectoryScreen>
    with UserAdminActions<UserDirectoryScreen> {
  bool _isSuperAdmin = false;
  bool _canAssignRoles = false;
  bool _canDelegate = false;

  bool get _isManagement => widget.role == 'management';
  bool get _isAll => widget.role == 'all';
  String? get _serverRole => (_isAll || _isManagement) ? null : widget.role;

  String _search = '';
  Timer? _searchDebounce;
  final _searchCtrl = TextEditingController();

  String? _fBatch, _fSection, _fDepartmentId;
  int? _fSemester;

  Map<String, dynamic> _facets = {};

  List<UserGroup> _groups = [];
  bool _groupsLoading = false;
  String? _groupsError;

  bool get _grouped => !_isManagement && !_isAll && _search.trim().isEmpty;

  List<Map<String, dynamic>> _users = [];
  String? _cursorCreatedAt, _cursorId;
  bool _hasMore = true, _loadingMore = false;
  bool _loading = true, _firstLoad = true;
  String? _error;
  final _listScroll = ScrollController();

  RealtimeChannel? _sub;
  final _refresh = RealtimeRefresh();

  Map<String, dynamic> get _filterArgs => {
        'p_role': _serverRole,
        'p_batch': _fBatch,
        'p_section': _fSection,
        'p_department_id': _fDepartmentId,
        'p_semester': _fSemester,
        'p_q': _search.trim().isEmpty ? null : _search.trim(),
      };

  @override
  void initState() {
    super.initState();
    _loadViewerRole();
    loadGrants();
    if (_isManagement) {
      _loadManagement();
    } else {
      _load();
      _loadFacets();
      _loadGroups();
    }
    _listScroll.addListener(() {
      if (!_hasMore || _loadingMore || _loading || _isManagement) return;
      if (_listScroll.position.pixels >= _listScroll.position.maxScrollExtent - 400) {
        _loadingMore = true;
        _load(reset: false);
      }
    });
    // Same debounced-burst-collapse as the landing screen's realtime sub:
    // `profiles` changes on every login and every profile edit anywhere in
    // the app.
    _sub = SupabaseConfig.client.channel(screenChannel('user_directory_${widget.role}', this))
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public', table: 'profiles',
            callback: (_) => _refresh.schedule(_refreshAll))
        .subscribe();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _listScroll.dispose();
    _sub?.unsubscribe();
    _refresh.dispose();
    super.dispose();
  }

  Future<void> _loadViewerRole() async {
    final role = await RoleSession.ensureLoaded();
    final grants = await PermissionSession.ensureLoaded();
    if (!mounted) return;
    setState(() {
      _isSuperAdmin = role == 'super_admin';
      _canAssignRoles = _isSuperAdmin || grants.contains('roles:assign');
      _canDelegate = _isSuperAdmin || grants.contains('permissions:delegate');
    });
  }

  Future<void> _refreshAll() async {
    if (_isManagement) {
      await _loadManagement();
      return;
    }
    await Future.wait([_load(), _loadFacets(), _loadGroups()]);
  }

  void _onFilterChanged() {
    _load();
    _loadFacets();
    _loadGroups();
  }

  void _onSearchChanged(String v) {
    _search = v;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _onFilterChanged);
  }

  /// The group headings and their counts for the current filters.
  Future<void> _loadGroups() async {
    if (!_grouped) {
      if (mounted) setState(() { _groups = []; _groupsError = null; });
      return;
    }
    if (mounted) setState(() { _groupsLoading = true; _groupsError = null; });
    try {
      final res = await SupabaseConfig.client.rpc('admin_user_groups', params: {
        'p_role': widget.role,
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
      if (mounted) {
        setState(() { _groupsError = friendlyError(e); _groupsLoading = false; });
      }
    }
  }

  /// The rows inside one opened group. Uses the same keys the group was
  /// counted with, so the count and the rows describe one population.
  Future<List<Map<String, dynamic>>> _rowsForGroup(UserGroup g) async {
    final params = <String, dynamic>{
      'p_role': widget.role,
      'p_department_id': _fDepartmentId,
      'p_q': _search.trim().isEmpty ? null : _search.trim(),
      'p_limit': 200,
    };
    if (widget.role == 'student') {
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
      if (widget.role == 'staff') params['p_staff_category'] = g.l1Key;
      if (widget.role == 'teacher' && g.l1Key != 'unset') {
        params['p_department_id'] = g.l1Key;
      }
    }
    final res = await SupabaseConfig.client.rpc('admin_search_users', params: params) as List;
    return res.cast<Map<String, dynamic>>();
  }

  /// One page of this role's directory. [reset] restarts from the newest row.
  Future<void> _load({bool reset = true}) async {
    if (reset) {
      _cursorCreatedAt = null;
      _cursorId = null;
      _hasMore = true;
      if (mounted) setState(() => _loading = true);
    }
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
      if (mounted) {
        setState(() { _error = friendlyError(e); _loading = false; _loadingMore = false; _firstLoad = false; });
      }
    }
  }

  /// The Management tier cuts across roles and lives in `user_permissions`,
  /// not `profiles.role` — resolved from the grants map already loaded for
  /// the badges. Bounded by the number of grant holders (tens), never by the
  /// size of the university.
  Future<void> _loadManagement() async {
    try {
      final ids = grantsByUser.entries
          .where((e) => delegatePermId != null && e.value.contains(delegatePermId))
          .map((e) => e.key).toList();
      if (ids.isEmpty) {
        if (mounted) setState(() { _users = []; _hasMore = false; _error = null; _loading = false; _firstLoad = false; });
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
          _firstLoad = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; _firstLoad = false; });
    }
  }

  Future<void> _loadFacets() async {
    if (_isManagement) return;
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

  List<Map<String, dynamic>> _facetList(String key) =>
      ((_facets[key] as List?) ?? const []).cast<Map<String, dynamic>>();

  // ONE row, one per filter DIMENSION, not one per VALUE. The previous fix
  // (each level scrolling sideways) stopped "many batches" from wrapping
  // across the screen, but a role with 4 dimensions (batch/section/semester/
  // department) still stacked 4 of those rows above the list — on a phone
  // that read as "half the screen is still filters". A chip now shows only
  // the CURRENT selection ("Batch: 68" or just "Batch" when unset) and opens
  // a picker sheet for the rest, so the fixed area is one ~44px row no matter
  // how many dimensions or values exist.
  Future<void> _pickFacet({
    required String title,
    required List<Map<String, dynamic>> values,
    required String? selected,
    required void Function(String?) onPick,
    String Function(Map<String, dynamic>)? labelOf,
  }) async {
    await showGlassSheet<void>(
      context,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 4),
          child: Text(title,
              style: AppTextStyles.titleLarge.copyWith(
                  color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700)),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              _FacetOption(
                label: 'All',
                selected: selected == null,
                onTap: () { Navigator.pop(context); onPick(null); },
              ),
              for (final v in values)
                _FacetOption(
                  label: '${labelOf?.call(v) ?? v['value']} (${v['count']})',
                  selected: selected == '${v['value']}',
                  onTap: () {
                    Navigator.pop(context);
                    onPick(selected == '${v['value']}' ? null : '${v['value']}');
                  },
                ),
            ],
          ),
        ),
      ]),
    );
  }

  /// The label to show ON the chip for whichever value is currently picked —
  /// resolved from the facet list so a department shows its name, not its id.
  String? _facetDisplay(List<Map<String, dynamic>> values, String? selected,
      {String Function(Map<String, dynamic>)? labelOf}) {
    if (selected == null) return null;
    for (final v in values) {
      if ('${v['value']}' == selected) return labelOf?.call(v) ?? '${v['value']}';
    }
    return selected;
  }

  Widget _filterBar(BuildContext context) {
    final entries = <(String label, String? display, VoidCallback onTap)>[];

    if (!_isManagement && widget.role == 'student') {
      final batches = _facetList('batches');
      if (batches.isNotEmpty) {
        entries.add((
          'Batch',
          _facetDisplay(batches, _fBatch),
          () => _pickFacet(
              title: 'Batch', values: batches, selected: _fBatch,
              onPick: (v) {
                setState(() { _fBatch = v; _fSection = null; });
                _onFilterChanged();
              }),
        ));
      }
      if (_fBatch != null) {
        final sections = _facetList('sections');
        if (sections.isNotEmpty) {
          entries.add((
            'Section',
            _facetDisplay(sections, _fSection),
            () => _pickFacet(
                title: 'Section', values: sections, selected: _fSection,
                onPick: (v) { setState(() => _fSection = v); _onFilterChanged(); }),
          ));
        }
      }
      final semesters = _facetList('semesters');
      if (semesters.isNotEmpty) {
        entries.add((
          'Semester',
          _facetDisplay(semesters, _fSemester?.toString()),
          () => _pickFacet(
              title: 'Semester', values: semesters, selected: _fSemester?.toString(),
              onPick: (v) {
                setState(() => _fSemester = v == null ? null : int.tryParse(v));
                _onFilterChanged();
              }),
        ));
      }
    }
    if (!_isManagement && !_isAll) {
      final depts = _facetList('departments');
      if (depts.isNotEmpty) {
        String labelOf(Map<String, dynamic> m) => '${m['label'] ?? m['value']}';
        entries.add((
          'Department',
          _facetDisplay(depts, _fDepartmentId, labelOf: labelOf),
          () => _pickFacet(
              title: 'Department', values: depts, selected: _fDepartmentId, labelOf: labelOf,
              onPick: (v) { setState(() => _fDepartmentId = v); _onFilterChanged(); }),
        ));
      }
    }

    if (entries.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 0, 8),
      child: SizedBox(
        // Was a bare `height: 44`. GlassChip measures 35.0px at 1.0x and
        // 45.0px at 2.0x, so these filter chips overflowed by 1.0px at the
        // largest accessibility scale — small, but it is a real clip and the
        // strip is how an admin narrows a user list.
        height: AppSpace.chipStrip(context, 44),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsetsDirectional.only(end: 16),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final e = entries[i];
            return Center(
              child: GlassChip(
                icon: Icons.tune_rounded,
                label: e.$2 == null ? e.$1 : '${e.$1}: ${e.$2}',
                selected: e.$2 != null,
                color: AppColors.holoBlue,
                onTap: e.$3,
              ),
            );
          },
        ),
      ),
    );
  }

  String get _title => switch (widget.role) {
        'management' => 'Management',
        'all' => 'All Users',
        _ => roleLabel(widget.role),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: _title),
      body: Column(children: [
        // THE EXPRESS LANE, in its own fixed slot — never sharing scroll
        // space with the list below it, which is the fix for the crowding
        // this screen replaces. An admin who knows the ID types it and lands
        // on the record without touching a single facet.
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
          child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              style: TextStyle(color: AppColors.textPrimaryOf(context)),
              decoration: InputDecoration(
                  hintText: 'Search by ID, email or name — fastest way in',
                  prefixIcon: const Icon(Icons.search),
                  filled: true, fillColor: AppColors.glassFill(context),
                  border: OutlineInputBorder(borderRadius: AppDepth.radius(1), borderSide: BorderSide.none))),
        ),
        _filterBar(context),
        const SizedBox(height: 8),
        Expanded(
          child: _loading && _firstLoad
              ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _grouped
              // BROWSING: sections, in the shape the people are actually
              // organised in. Rows load per group, so opening one intake
              // never downloads the rest of the university.
              ? (_groupsError != null
                  ? ErrorView(message: _groupsError!, onRetry: _loadGroups)
                  : _groupsLoading
                  ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
                  : _groups.isEmpty
                  ? const EmptyState(
                      icon: Icons.people_outline,
                      title: 'No one in this group',
                      subtitle: 'Try a different filter, or search by ID/name')
                  : UserGroupTree(
                      groups: _groups,
                      rowsFor: _rowsForGroup,
                      padding: EdgeInsetsDirectional.fromSTEB(16, 8, 16, 16 + NavInsets.of(context)),
                      itemBuilder: (u) => UserCard(
                          key: ValueKey(u['id']), user: u, pending: false,
                          isManager: isManager(u),
                          areaCount: areaCount(u),
                          onDelete: _isSuperAdmin ? () => confirmDelete(u, onDone: _refreshAll) : null,
                          onChangeRole: _canAssignRoles
                              ? () => setRole(u, isSuperAdmin: _isSuperAdmin, onDone: _refreshAll)
                              : null,
                          onToggleManager: _isSuperAdmin
                              ? () => toggleManager(u, isSuperAdmin: _isSuperAdmin)
                              : null,
                          onManagePermissions: _canDelegate
                              ? () => managePermissions(u, isSuperAdmin: _isSuperAdmin, onDone: _refreshAll)
                              : null),
                    ))
              : _users.isEmpty
              ? EmptyState(
                  icon: Icons.people_outline,
                  title: _isManagement ? 'No managers yet' : 'No users found',
                  subtitle: _isManagement
                      ? 'Appoint one from a role directory\'s user detail sheet'
                      : 'Try a different search or filter')
              : AdaptiveList(
                  controller: _listScroll,
                  padding: EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16 + NavInsets.of(context)),
                  itemCount: _users.length,
                  prototypeItem: UserCard(user: _users.first, pending: false,
                      isManager: isManager(_users.first),
                      areaCount: areaCount(_users.first),
                      onDelete: _isSuperAdmin ? () => confirmDelete(_users.first, onDone: _refreshAll) : null,
                      onChangeRole: _canAssignRoles
                          ? () => setRole(_users.first, isSuperAdmin: _isSuperAdmin, onDone: _refreshAll)
                          : null,
                      onToggleManager: _isSuperAdmin
                          ? () => toggleManager(_users.first, isSuperAdmin: _isSuperAdmin)
                          : null,
                      onManagePermissions: _canDelegate
                          ? () => managePermissions(_users.first, isSuperAdmin: _isSuperAdmin, onDone: _refreshAll)
                          : null),
                  itemBuilder: (ctx, i) => UserCard(key: ValueKey(_users[i]['id']), user: _users[i], pending: false,
                      isManager: isManager(_users[i]),
                      areaCount: areaCount(_users[i]),
                      onDelete: _isSuperAdmin ? () => confirmDelete(_users[i], onDone: _refreshAll) : null,
                      onChangeRole: _canAssignRoles
                          ? () => setRole(_users[i], isSuperAdmin: _isSuperAdmin, onDone: _refreshAll)
                          : null,
                      onToggleManager: _isSuperAdmin
                          ? () => toggleManager(_users[i], isSuperAdmin: _isSuperAdmin)
                          : null,
                      onManagePermissions: _canDelegate
                          ? () => managePermissions(_users[i], isSuperAdmin: _isSuperAdmin, onDone: _refreshAll)
                          : null),
                ),
        ),
      ]),
    );
  }
}

/// One row inside a facet picker sheet.
class _FacetOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FacetOption({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppDepth.radius(1),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(children: [
          Icon(
            selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
            size: 20,
            color: selected ? AppColors.holoBlue : AppColors.textSecondaryOf(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimaryOf(context),
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          ),
        ]),
      ),
    );
  }
}
