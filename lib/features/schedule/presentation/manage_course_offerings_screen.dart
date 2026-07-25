import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_chip.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/info_card.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/course_offering_repository.dart';
import 'course_group_screen.dart';
import 'widgets/offering_card.dart';
import '../../../core/layout/nav_insets.dart';

/// Teacher-facing: declare course offerings (admin-approved before they go
/// live on the schedule), review student join requests, open a section's
/// group, and archive a course at the end of the term.
class ManageCourseOfferingsScreen extends StatefulWidget {
  const ManageCourseOfferingsScreen({super.key});
  @override
  State<ManageCourseOfferingsScreen> createState() => _ManageCourseOfferingsScreenState();
}

class _ManageCourseOfferingsScreenState extends State<ManageCourseOfferingsScreen>
    with SingleTickerProviderStateMixin {
  final _repo = CourseOfferingRepository();
  late final TabController _tab = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _offerings = [], _joinRequests = [];
  String _myDepartment = '';
  Map<String, dynamic>? _term;
  bool _loading = true;
  String? _error;

  /// Per-row so responding to one request doesn't freeze every other button.
  final Set<String> _busyIds = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = SupabaseConfig.uid;
      final results = await Future.wait([
        SupabaseConfig.client.from('profiles').select('department').eq('id', uid ?? '').maybeSingle() as Future,
        _repo.fetchMyOfferings(),
        _repo.fetchOfferingJoinRequests(),
        _repo.fetchActiveTerm(),
      ]);
      if (mounted) {
        setState(() {
          _myDepartment = (results[0] as Map?)?['department'] as String? ?? '';
          _offerings = results[1] as List<Map<String, dynamic>>;
          _joinRequests = results[2] as List<Map<String, dynamic>>;
          _term = results[3] as Map<String, dynamic>?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _guard(String id, Future<void> Function() action) async {
    setState(() => _busyIds.add(id));
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busyIds.remove(id));
  }

  Future<void> _withdraw(String offeringId) => _guard(offeringId, () => _repo.withdrawOffering(offeringId));

  Future<void> _archive(Map<String, dynamic> offering) async {
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('End this course?'),
        content: Text(
            '${course['code'] ?? 'This course'} (Section ${offering['section']}) will be removed from '
            'the routine and from every enrolled student\'s schedule.\n\n'
            'Enrolments are kept as the record of who took it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('End course', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _guard(offering['id'] as String, () => _repo.archiveOffering(offering['id'] as String));
  }

  Future<void> _respondToJoin(Map<String, dynamic> request, bool approve) => _guard(
        request['id'] as String,
        () => approve
            ? _repo.approveJoin(request['id'] as String)
            : _repo.rejectJoin(request['id'] as String),
      );

  void _openGroup(Map<String, dynamic> offering) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CourseGroupScreen(offering: offering)));
  }

  void _showCreateSheet(BuildContext context) {
    showGlassSheet(context,
        child: _CreateOfferingForm(
          repo: _repo,
          myDepartment: _myDepartment,
          onCreated: () { Navigator.pop(context); _load(); },
        ));
  }

  @override
  Widget build(BuildContext context) {
    final pending = _joinRequests.where((r) => r['status'] == 'pending').length;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'My Course Offerings'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSheet(context),
        backgroundColor: AppColors.blue,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New Offering', style: TextStyle(color: Colors.white)),
      ),
      body: Column(children: [
        FeatureHeader(
          title: 'Course Offerings',
          subtitle: _loading
              ? 'Loading…'
              : '${_offerings.length} offerings · $pending join requests'
                  '${_term == null ? '' : ' · ${_term!['name']}'}',
          icon: AppIcons.schedule,
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.blueLight, AppColors.blue]),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.06, curve: Curves.easeOutCubic),
        AnimatedBuilder(
          animation: _tab,
          builder: (ctx, _) => GlassTabBar(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            currentIndex: _tab.index,
            onChanged: (i) => setState(() => _tab.animateTo(i)),
            tabs: [
              const GlassTab('My Offerings', icon: Icons.menu_book_rounded),
              // The count was already computed but never surfaced — a teacher
              // had no way to know a request was waiting without opening the tab.
              GlassTab(pending > 0 ? 'Join Requests ($pending)' : 'Join Requests',
                  icon: Icons.how_to_reg_rounded),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : TabBarView(controller: _tab, children: [
                  RefreshIndicator(onRefresh: _load, child: _offeringsTab()),
                  RefreshIndicator(onRefresh: _load, child: _joinRequestsTab()),
                ]),
        ),
      ]),
    );
  }

  Widget _offeringsTab() {
    if (_loading) return const OfferingCardSkeleton();
    if (_offerings.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 40),
        EmptyState(
            icon: Icons.menu_book_outlined,
            title: 'No offerings yet',
            subtitle: 'Tap "New Offering" to declare a course you teach'),
      ]);
    }
    return ListView.builder(
      padding: NavInsets.content(context, top: 0, fab: true),
      itemCount: _offerings.length,
      itemBuilder: (ctx, i) {
        final o = _offerings[i];
        final id = o['id'] as String;
        final status = o['status'] as String? ?? 'pending';
        final reason = o['rejection_reason'] as String?;
        final busy = _busyIds.contains(id);
        return OfferingCard(
          offering: o,
          index: i,
          onTap: status == 'approved' ? () => _openGroup(o) : null,
          footer: status == 'rejected' && (reason?.isNotEmpty ?? false)
              ? Text('Reason: $reason',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.red))
              : null,
          // Wrap, not Row: the approved variant (status pill + Group + archive)
          // is 0.9px too wide for the card on a 320dp phone, which clipped the
          // archive button. Wrap reflows instead of overflowing, and lays out
          // identically wherever there is room.
          trailing: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PillBadge(label: status.toUpperCase(), color: offeringStatusColor(status)),
              if (status == 'pending')
                TextButton(
                  onPressed: busy ? null : () => _withdraw(id),
                  child: const Text('Withdraw', style: TextStyle(fontSize: 12, color: AppColors.red)),
                ),
              if (status == 'approved') ...[
                TextButton.icon(
                  onPressed: () => _openGroup(o),
                  icon: const Icon(Icons.forum_outlined, size: 15),
                  label: const Text('Group', style: TextStyle(fontSize: 12)),
                ),
                IconButton(
                  tooltip: 'End course (archive)',
                  onPressed: busy ? null : () => _archive(o),
                  icon: const Icon(Icons.archive_outlined, size: 18, color: AppColors.red),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _joinRequestsTab() {
    if (_loading) return const OfferingCardSkeleton();
    if (_joinRequests.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 40),
        EmptyState(
            icon: Icons.how_to_reg_outlined,
            title: 'No join requests yet',
            subtitle: 'Students requesting to join your offerings show up here'),
      ]);
    }
    return ListView.builder(
      padding: NavInsets.content(context, top: 0, fab: true),
      itemCount: _joinRequests.length,
      itemBuilder: (ctx, i) {
        final r = _joinRequests[i];
        final id = r['id'] as String;
        final student = r['profiles'] as Map<String, dynamic>? ?? const {};
        final offering = r['course_offerings'] as Map<String, dynamic>? ?? const {};
        final course = offering['courses'] as Map<String, dynamic>? ?? const {};
        final status = r['status'] as String? ?? 'pending';
        final busy = _busyIds.contains(id);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InfoCard(
            accent: offeringStatusColor(status),
            stripe: true,
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(student['full_name'] as String? ?? 'Student',
                      style: AppTextStyles.titleMedium
                          .copyWith(color: AppColors.textPrimaryOf(ctx)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                PillBadge(label: status.toUpperCase(), color: offeringStatusColor(status)),
              ]),
              const SizedBox(height: 4),
              Text('wants to join ${course['code'] ?? ''} · Section ${offering['section'] ?? ''}',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondaryOf(ctx))),
              if ((student['batch'] as String?)?.isNotEmpty == true)
                Text('Their batch/section: ${student['batch']}/${student['section'] ?? ''}',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.textSecondaryOf(ctx))),
              if (status == 'pending') ...[
                const SizedBox(height: 12),
                // Paired Outlined/Filled buttons, matching the admin queue's
                // treatment of the same decision — these were two 12px
                // TextButtons, visually far weaker than the choice deserved.
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton(
                    onPressed: busy ? null : () => _respondToJoin(r, false),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                    child: const Text('Decline'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: busy ? null : () => _respondToJoin(r, true),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                    child: busy
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Accept'),
                  ),
                ]),
              ],
            ]),
          ),
        ).animate(delay: Duration(milliseconds: i * 55)).fadeIn().slideY(begin: 0.05);
      },
    );
  }
}

// ---------------------------------------------------------------- create form

class _CreateOfferingForm extends StatefulWidget {
  final CourseOfferingRepository repo;
  final String myDepartment;
  final VoidCallback onCreated;
  const _CreateOfferingForm({
    required this.repo,
    required this.myDepartment,
    required this.onCreated,
  });
  @override
  State<_CreateOfferingForm> createState() => _CreateOfferingFormState();
}

class _CreateOfferingFormState extends State<_CreateOfferingForm> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _creditsCtrl = TextEditingController(text: '3');
  final _sectionCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();
  final _semesterCtrl = TextEditingController();
  final _outlineCtrl = TextEditingController();
  String _courseType = 'theory';
  final List<OfferingMeeting> _meetings = [];
  List<Map<String, dynamic>> _suggestions = [];
  bool _saving = false;

  /// Search state. [_searchedFor] is the query the current [_suggestions]
  /// belong to — non-null means a search actually completed, which is what
  /// separates "no matches, this will be a new course" from "haven't looked
  /// yet". Without it an empty result was indistinguishable from idle.
  bool _searching = false;
  String? _searchedFor;
  int _searchSeq = 0;

  /// Owned here rather than left to AfosTextField's internal node, so the code
  /// field can be focused on open — the sheet used to appear with nothing
  /// focused and no keyboard, which read as "search doesn't work".
  final _codeFocus = FocusNode();
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _codeFocus.dispose();
    _codeCtrl.dispose(); _titleCtrl.dispose(); _creditsCtrl.dispose();
    _sectionCtrl.dispose(); _batchCtrl.dispose(); _semesterCtrl.dispose();
    _outlineCtrl.dispose();
    super.dispose();
  }

  /// Debounced at 320ms, matching global_search_screen. Previously this fired
  /// a network round-trip on EVERY keystroke and rebuilt the whole form with
  /// the result, so the suggestion chips flickered in and out while typing.
  ///
  /// [_searchSeq] guards against a slow earlier request landing after a newer
  /// one and overwriting it — debouncing alone doesn't prevent that, because
  /// two searches that each survive the debounce still race on the network,
  /// and the loser was silently winning whenever it was slower.
  ///
  /// The throw was also unhandled: `searchCourses` on a dropped connection
  /// produced an unhandled async error and left the spinner up forever.
  void _searchCourses(String q) {
    _searchDebounce?.cancel();
    final query = q.trim();
    if (query.length < 2) {
      if (_suggestions.isNotEmpty || _searching || _searchedFor != null) {
        setState(() {
          _suggestions = [];
          _searching = false;
          _searchedFor = null;
        });
      }
      return;
    }
    if (!_searching) setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 320), () async {
      final seq = ++_searchSeq;
      try {
        final res = await widget.repo.searchCourses(query);
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          _suggestions = res;
          _searching = false;
          _searchedFor = query;
        });
      } catch (_) {
        if (mounted && seq == _searchSeq) setState(() => _searching = false);
      }
    });
  }

  void _pickSuggestion(Map<String, dynamic> c) {
    // Cancel any in-flight search: without this a request already on the wire
    // lands a moment later and re-opens the suggestion list over the fields
    // the teacher just had filled in for them.
    _searchDebounce?.cancel();
    _searchSeq++;
    setState(() {
      _codeCtrl.text = c['code'] as String? ?? '';
      _titleCtrl.text = c['title'] as String? ?? '';
      _creditsCtrl.text = '${c['credit_hours'] ?? 3}';
      _courseType = c['course_type'] as String? ?? 'theory';
      _suggestions = [];
      _searching = false;
      _searchedFor = null;
    });
    FocusScope.of(context).unfocus();
  }

  Future<void> _addMeeting() async {
    // showGlassModal (not showGlassSheet): _MeetingEditor supplies its own
    // padding and keyboard lift, and this variant deliberately doesn't
    // double them.
    final m = await showGlassModal<OfferingMeeting>(
      context,
      builder: (_) => _MeetingEditor(defaultType: _courseType),
    );
    if (m == null) return;
    // Catching the clash here rather than at the DB's unique constraint means
    // the teacher sees which meeting conflicts, not a raw 23505.
    final clash = _meetings.where((e) => e.overlaps(m)).isNotEmpty;
    if (clash) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('That overlaps a meeting you already added'),
            backgroundColor: AppColors.amber));
      }
      return;
    }
    setState(() => _meetings.add(m));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_meetings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Add at least one class meeting'), backgroundColor: AppColors.amber));
      return;
    }
    // An empty department is silently fatal further downstream: it is not
    // NULL, so approve_course_offering's `department IS NULL` guard lets it
    // through, and the offering is published with department '' — which no
    // student's department-filtered browse query can ever match. The offering
    // would look approved to everyone and be visible to nobody.
    if (widget.myDepartment.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Your profile has no department set — add it in Profile before '
              'creating an offering, or students will never see this course.'),
          backgroundColor: AppColors.red));
      return;
    }
    setState(() => _saving = true);
    try {
      final courseId = await widget.repo.resolveOrCreateCourse(
        code: _codeCtrl.text.trim().toUpperCase(),
        title: _titleCtrl.text.trim(),
        creditHours: int.tryParse(_creditsCtrl.text.trim()) ?? 3,
        courseType: _courseType,
        departmentCode: widget.myDepartment,
      );
      await widget.repo.createOffering(
        courseId: courseId,
        section: _sectionCtrl.text.trim(),
        department: widget.myDepartment,
        batch: _batchCtrl.text.trim(),
        semester: int.parse(_semesterCtrl.text.trim()),
        meetings: _meetings,
        outlineText: _outlineCtrl.text,
      );
      widget.onCreated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Submitted for admin approval ✓'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  String? _required(String? v, String label) =>
      (v == null || v.trim().isEmpty) ? '$label is required' : null;

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New Course Offering',
                  style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
              const SizedBox(height: 4),
              Text('Sent to admin for approval before it appears on the schedule',
                  style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
              const SizedBox(height: 10),

              // The department is taken from the teacher's own profile and was
              // applied invisibly — there was no way to tell what an offering
              // would be filed under, and no warning at all when the profile
              // had none, which produces a course no student can ever see.
              _DepartmentNotice(department: widget.myDepartment),
              const SizedBox(height: 14),

              AfosTextField(
                hint: 'Course code (e.g. CSE431)',
                controller: _codeCtrl,
                focusNode: _codeFocus,
                autofocus: true,
                onChanged: _searchCourses,
                // resolveOrCreateCourse() inserts this verbatim into
                // courses.code, which carries a format CHECK.
                validator: AppValidators.courseCode,
              ),
              // Was a Wrap of ActionChips at a hardcoded fontSize 11 carrying
              // "CODE · Full Course Title" — on a phone one chip wrapped to
              // three lines and several were unreadable, and there was no way
              // to tell whether the search had run, was running, or had found
              // nothing. The last case matters most: no match means
              // resolveOrCreateCourse will CREATE the course, which the
              // teacher should know before submitting.
              if (_searching)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    const SizedBox(
                        width: 13, height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Text('Searching…',
                        style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
                  ]),
                )
              else if (_suggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    children: [
                      for (final c in _suggestions)
                        _CourseSuggestionRow(course: c, onTap: () => _pickSuggestion(c)),
                    ],
                  ),
                )
              else if (_searchedFor != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    const Icon(Icons.add_circle_outline_rounded,
                        size: 14, color: AppColors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No existing course matches "$_searchedFor" — it will be '
                        'created from the title and credits below.',
                        style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 12),
              AfosTextField(
                  hint: 'Course title',
                  controller: _titleCtrl,
                  validator: (v) => _required(v, 'Course title')),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: AfosTextField(
                    hint: 'Credit hours',
                    controller: _creditsCtrl,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      return (n == null || n < 1 || n > 6) ? '1–6' : null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Row(children: [
                    Expanded(
                      child: GlassChip(
                        label: 'Theory',
                        selected: _courseType == 'theory',
                        expand: true,
                        onTap: () => setState(() => _courseType = 'theory'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: GlassChip(
                        label: 'Lab',
                        selected: _courseType == 'lab',
                        expand: true,
                        color: AppColors.purple,
                        onTap: () => setState(() => _courseType = 'lab'),
                      ),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: AfosTextField(
                        hint: 'Batch (e.g. 63)',
                        controller: _batchCtrl,
                        validator: AppValidators.batch)),
                const SizedBox(width: 10),
                Expanded(
                    child: AfosTextField(
                        hint: 'Section (e.g. A)',
                        controller: _sectionCtrl,
                        validator: AppValidators.section)),
              ]),
              const SizedBox(height: 12),
              AfosTextField(
                hint: 'Semester (1-12)',
                controller: _semesterCtrl,
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  return (n == null || n < 1 || n > 12) ? 'Must be 1–12' : null;
                },
              ),
              const SizedBox(height: 12),
              AfosTextField(
                  hint: 'Course outline (optional)', controller: _outlineCtrl, maxLines: 3),

              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: Text('Class meetings',
                      style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
                ),
                TextButton.icon(
                  onPressed: _addMeeting,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                ),
              ]),
              Text(
                'One per session. A course meeting twice a week is two meetings; '
                'a lab split into J1/J2 is one per subgroup.',
                style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
              ),
              const SizedBox(height: 8),
              if (_meetings.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
                    border: Border.all(color: AppColors.amber.withValues(alpha: 0.25), width: 0.5),
                  ),
                  child: Text('No meetings added yet — tap "Add".',
                      style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                )
              else
                Column(
                  children: [
                    for (var i = 0; i < _meetings.length; i++)
                      _MeetingRow(
                        meeting: _meetings[i],
                        onRemove: () => setState(() => _meetings.removeAt(i)),
                      ),
                  ],
                ),

              const SizedBox(height: 20),
              AfosButton(label: 'Submit for Approval', loading: _saving, onTap: _submit),
            ]),
      ),
    );
  }
}

/// One course-search result. Full-width and tappable rather than a chip, so
/// the code stays scannable and a long title can ellipsize instead of
/// reflowing the whole list. Credits and type are shown because picking a
/// suggestion overwrites both fields — previously that happened invisibly.
class _CourseSuggestionRow extends StatelessWidget {
  final Map<String, dynamic> course;
  final VoidCallback onTap;
  const _CourseSuggestionRow({required this.course, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isLab = (course['course_type'] as String?) == 'lab';
    final accent = isLab ? AppColors.purple : AppColors.blue;
    final credits = course['credit_hours'];

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
            border: Border.all(color: accent.withValues(alpha: 0.22), width: 0.5),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course['code'] as String? ?? '—',
                    style: AppTextStyles.titleMedium.copyWith(color: accent)),
                Text(course['title'] as String? ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.textSecondaryOf(context))),
              ]),
            ),
            const SizedBox(width: 8),
            if (credits != null)
              Text('$credits cr',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textSecondaryOf(context))),
            if (isLab) ...[
              const SizedBox(width: 6),
              const PillBadge(label: 'LAB', color: AppColors.purple),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Shows which department the offering will be filed under, or warns when the
/// teacher's profile has none. Missing is the interesting case: an offering
/// created with department '' is approvable but invisible to every student.
class _DepartmentNotice extends StatelessWidget {
  final String department;
  const _DepartmentNotice({required this.department});

  @override
  Widget build(BuildContext context) {
    final missing = department.trim().isEmpty;
    final color = missing ? AppColors.red : AppColors.blue;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(children: [
        Icon(missing ? Icons.error_outline_rounded : Icons.apartment_rounded,
            size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            missing
                ? 'No department on your profile — set it before submitting, or no student will see this course.'
                : 'Filed under $department · visible to that department only',
            style: AppTextStyles.labelSmall.copyWith(
                color: missing ? color : AppColors.textSecondaryOf(context)),
          ),
        ),
      ]),
    );
  }
}

class _MeetingRow extends StatelessWidget {
  final OfferingMeeting meeting;
  final VoidCallback onRemove;
  const _MeetingRow({required this.meeting, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isLab = meeting.classType == 'lab';
    final accent = isLab ? AppColors.purple : AppColors.blue;
    final where = [meeting.building, meeting.roomNumber]
        .where((s) => s.trim().isNotEmpty).join(' ');
    final day = meeting.dayOfWeek >= 0 && meeting.dayOfWeek < 7
        ? kDayLabels[meeting.dayOfWeek] : '—';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        border: Border.all(color: accent.withValues(alpha: 0.22), width: 0.5),
      ),
      child: Row(children: [
        Icon(isLab ? Icons.science_outlined : Icons.schedule_rounded, size: 16, color: accent),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 12-hour, matching the picker that produced it. The editor shows
            // "8:00 AM" via TimeOfDay.format but this row rendered the stored
            // raw "08:00", so a meeting displayed differently from the time
            // the teacher had just chosen.
            Text('$day ${AppFormatters.timeRange12(meeting.startTime, meeting.endTime)}'
                '${meeting.labSubgroup > 0 ? ' · J${meeting.labSubgroup}' : ''}',
                style: AppTextStyles.titleMedium.copyWith(color: accent)),
            if (where.isNotEmpty)
              Text(where,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textSecondaryOf(context))),
          ]),
        ),
        IconButton(
          onPressed: onRemove,
          icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.red),
          visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }
}

/// Compact editor for a single meeting; returns it via [Navigator.pop].
class _MeetingEditor extends StatefulWidget {
  final String defaultType;
  const _MeetingEditor({required this.defaultType});
  @override
  State<_MeetingEditor> createState() => _MeetingEditorState();
}

class _MeetingEditorState extends State<_MeetingEditor> {
  final _roomCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  int _day = 2; // Mon
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 9, minute: 30);
  late String _type = widget.defaultType;
  int _subgroup = 0;

  @override
  void dispose() {
    _roomCtrl.dispose();
    _buildingCtrl.dispose();
    super.dispose();
  }

  String _fmt(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;

  /// [start] + [mins], clamped to the same day rather than wrapping past
  /// midnight — a 6pm start with a 3h lab must not become 9pm "yesterday",
  /// which is what modulo arithmetic would produce and _done() would then
  /// reject as "end before start".
  TimeOfDay _plus(TimeOfDay start, int mins) {
    final total = (_minutes(start) + mins).clamp(0, 23 * 60 + 59);
    return TimeOfDay(hour: total ~/ 60, minute: total % 60);
  }

  Future<void> _pick(bool isStart) async {
    final picked = await showTimePicker(context: context, initialTime: isStart ? _start : _end);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = picked;
        // Keep end after start automatically rather than rejecting later.
        if (_minutes(_end) <= _minutes(_start)) {
          _end = TimeOfDay(hour: (picked.hour + 1) % 24, minute: picked.minute);
        }
      } else {
        _end = picked;
      }
    });
  }

  void _done() {
    if (_minutes(_end) <= _minutes(_start)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('End time must be after start time'), backgroundColor: AppColors.amber));
      return;
    }
    Navigator.pop(
      context,
      OfferingMeeting(
        dayOfWeek: _day,
        startTime: _fmt(_start),
        endTime: _fmt(_end),
        roomNumber: _roomCtrl.text,
        building: _buildingCtrl.text,
        classType: _type,
        labSubgroup: _type == 'lab' ? _subgroup : 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add a meeting',
                style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
            const SizedBox(height: 14),
            Text('Day', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6, runSpacing: 6,
              children: [
                for (var i = 0; i < kDayLabels.length; i++)
                  GlassChip(
                    label: kDayLabels[i],
                    selected: _day == i,
                    onTap: () => setState(() => _day = i),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => _pick(true),
                      child: Text('Start ${_start.format(context)}'))),
              const SizedBox(width: 10),
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => _pick(false),
                      child: Text('End ${_end.format(context)}'))),
            ]),

            // Every meeting used to cost two full time-picker dialogs even
            // for the handful of lengths DIU actually timetables. These set
            // the end from the start in one tap; the pickers remain for
            // anything irregular.
            const SizedBox(height: 8),
            Row(children: [
              Text('Duration',
                  style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final mins in const [60, 90, 120, 180])
                      GlassChip(
                        label: mins % 60 == 0 ? '${mins ~/ 60}h' : '${mins ~/ 60}h${mins % 60}',
                        selected: _minutes(_end) - _minutes(_start) == mins,
                        onTap: () => setState(() => _end = _plus(_start, mins)),
                      ),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: GlassChip(
                    label: 'Theory',
                    selected: _type == 'theory',
                    expand: true,
                    onTap: () => setState(() { _type = 'theory'; _subgroup = 0; })),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassChip(
                    label: 'Lab',
                    selected: _type == 'lab',
                    expand: true,
                    color: AppColors.purple,
                    onTap: () => setState(() => _type = 'lab')),
              ),
            ]),
            if (_type == 'lab') ...[
              const SizedBox(height: 14),
              Text('Lab subgroup', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
              const SizedBox(height: 6),
              Row(children: [
                for (final s in const [0, 1, 2]) ...[
                  Expanded(
                    child: GlassChip(
                      label: s == 0 ? 'Whole class' : 'J$s',
                      selected: _subgroup == s,
                      expand: true,
                      color: AppColors.purple,
                      onTap: () => setState(() => _subgroup = s),
                    ),
                  ),
                  if (s != 2) const SizedBox(width: 6),
                ],
              ]),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: AfosTextField(hint: 'Building', controller: _buildingCtrl)),
              const SizedBox(width: 10),
              Expanded(child: AfosTextField(hint: 'Room number', controller: _roomCtrl)),
            ]),
            const SizedBox(height: 20),
            AfosButton(label: 'Add meeting', onTap: _done),
          ]),
    );
  }
}
