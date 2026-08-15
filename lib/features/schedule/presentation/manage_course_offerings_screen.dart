import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/button_styles.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../config/theme/motion.dart';
import '../../../core/haptics/app_haptics.dart';
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
import '../../../shared/widgets/pill_badge.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/course_offering_repository.dart';
import '../data/repositories/teaching_assignment_repository.dart';
import 'course_group_screen.dart';
import 'join_requests_screen.dart';
import 'widgets/offering_card.dart';
import '../../../core/layout/nav_insets.dart';

String _normKey(Object? v) => (v as String? ?? '').trim().toUpperCase();

/// Whether a pending join request comes from a student already in the batch
/// and section of the offering they applied to — the same comparison the
/// card's notice shows the teacher.
///
/// Top-level and public rather than a private method on the State, because it
/// decides who the bulk admit lets in WITHOUT individual review. That makes it
/// the one piece of this screen that must be pinned by a test.
///
/// Deliberately conservative: a student with no batch or section recorded is
/// NOT a match, so an incomplete profile is always reviewed by hand instead of
/// being swept in by an empty-string comparison.
bool joinRequestMatchesSection(Map<String, dynamic> request) {
  if (request['status'] != 'pending') return false;
  final s = request['profiles'] as Map<String, dynamic>? ?? const {};
  final o = request['course_offerings'] as Map<String, dynamic>? ?? const {};
  final sb = _normKey(s['batch']), ss = _normKey(s['section']);
  if (sb.isEmpty || ss.isEmpty) return false;
  return sb == _normKey(o['batch']) && ss == _normKey(o['section']);
}

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

  /// Ended offerings. Loaded and SHOWN, where before fetchMyArchivedOfferings()
  /// existed but no screen called it -- so ending a course made it vanish with
  /// no trace and no way back, and the only symptom was a teacher seeing none
  /// of their own courses anywhere in the app.
  List<Map<String, dynamic>> _archived = [];
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
        _repo.fetchMyArchivedOfferings(),
      ]);
      if (mounted) {
        setState(() {
          _myDepartment = (results[0] as Map?)?['department'] as String? ?? '';
          _offerings = results[1] as List<Map<String, dynamic>>;
          _joinRequests = results[2] as List<Map<String, dynamic>>;
          _term = results[3] as Map<String, dynamic>?;
          _archived = results[4] as List<Map<String, dynamic>>;
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

  Future<void> _restore(Map<String, dynamic> offering) async {
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Bring this course back?'),
        content: Text(
            '${course['code'] ?? 'This course'} (Section ${offering['section']}) '
            'will reappear in your class lists for Results, Attendance and '
            'Assignments, and students will be able to find it again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    await _guard(offering['id'] as String,
        () => _repo.restoreOffering(offering['id'] as String));
  }

  /// Destroys an ended offering for good.
  ///
  /// Deliberately two taps away from anything: only an ALREADY ended course
  /// offers it, and the sheet spells out the enrolment count before the button
  /// says Delete. The RPC refuses outright once any mark or attendance record
  /// exists, so the failure a teacher is most likely to hit is a refusal, not a
  /// loss — which is why the error goes to a SnackBar and the row stays put.
  Future<void> _deleteForever(Map<String, dynamic> offering) async {
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final label = '${course['code'] ?? 'This course'} · Section ${offering['section'] ?? ''}';
    final enrolled = CourseOfferingRepository.enrolmentCountOf(offering);
    final id = offering['id'] as String;

    final ok = await showGlassModal<bool>(context,
        builder: (sheetCtx) => Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Delete $label?',
                        style: AppTextStyles.headlineLarge
                            .copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
                    const SizedBox(height: 6),
                    Text(
                        enrolled == 0
                            ? 'This cannot be undone. Ending a course keeps it and lets '
                                'you restore it; deleting removes it for good.'
                            : 'This cannot be undone, and it drops '
                                '$enrolled ${enrolled == 1 ? 'person' : 'people'} from the '
                                'class. They are told the course was removed.',
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
                    const SizedBox(height: 10),
                    Text(
                        'If any marks or attendance have been recorded, this will be '
                        'refused — that history cannot be rebuilt.',
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                          child: TextButton(
                              onPressed: () => Navigator.pop(sheetCtx, false),
                              child: const Text('Keep it'))),
                      const SizedBox(width: 8),
                      Expanded(
                          child: FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                              onPressed: () => Navigator.pop(sheetCtx, true),
                              child: const Text('Delete forever', maxLines: 1))),
                    ]),
                  ]),
            ));
    if (ok != true || !mounted) return;

    // Deliberately NOT optimistic. Removing the row before the round trip would
    // be more responsive and wrong: _guard only reloads on success, so a refusal
    // — which is the likely outcome here, the RPC rejects anything with marks or
    // attendance — would leave the row gone from the list while it still exists
    // in the database, showing the teacher a delete that did not happen. The row
    // spins via _busyIds instead, and the list updates when the answer is real.
    await _guard(id, () async {
      final dropped = await _repo.deleteOffering(id, courseLabel: label);
      if (!mounted) return;
      // Destructive, and it may have dropped enrolled students with it.
      AppHaptics.warning();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(dropped == 0
            ? '$label deleted'
            : '$label deleted · ${dropped == 1 ? '1 person' : '$dropped people'} dropped'),
        backgroundColor: AppColors.green,
      ));
    });
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
        ).animate().fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
            .slideY(begin: -0.06, curve: AppMotion.standard),
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
    if (_offerings.isEmpty && _archived.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 40),
        EmptyState(
            icon: Icons.menu_book_outlined,
            title: 'No offerings yet',
            subtitle: 'Tap "New Offering" to declare a course you teach'),
      ]);
    }
    // The ended courses are appended after the live ones. Showing them at all
    // is the point: an archived offering is filtered out of every other list in
    // the app, so if this screen hides it too there is nowhere left that
    // explains where the course went.
    return ListView.builder(
      padding: NavInsets.content(context, top: 0, fab: true),
      itemCount: _offerings.length + (_archived.isEmpty ? 0 : _archived.length + 1),
      itemBuilder: (ctx, rawIndex) {
        if (rawIndex >= _offerings.length) {
          final ai = rawIndex - _offerings.length;
          if (ai == 0) return EndedHeader(count: _archived.length);
          final a = _archived[ai - 1];
          return EndedOfferingRow(
            offering: a,
            busy: _busyIds.contains(a['id']),
            onRestore: () => _restore(a),
            onDelete: () => _deleteForever(a),
          );
        }
        final i = rawIndex;
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
              // Uncapped: this Wrap is OfferingCard's `trailing`, which gets a
              // full-width line of its own, so there is nothing beside the
              // badge to starve — and the default cap hid half its label at a
              // 2.0x text scale.
              PillBadge(
                  label: status.toUpperCase(),
                  color: offeringStatusColor(status),
                  maxWidth: double.infinity),
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

  void _openGroup(Map<String, dynamic> offering) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => CourseGroupScreen(offering: offering)));
  }

  /// Deliberately NOT the list any more.
  ///
  /// This tab rendered blank while its own title showed a live count, and the
  /// data was proven correct every time it was probed. Three theories for the
  /// blank render were each disproved because the sibling tab used the same
  /// widget, blur and animation and worked fine. Rather than keep guessing at
  /// an unreproducible fault inside a TabBarView, the list moved to
  /// [JoinRequestsScreen] -- a plain Scaffold with a plain ListView and no
  /// PageView in the way -- and this hands off to it.
  Widget _joinRequestsTab() {
    if (_loading) return const OfferingCardSkeleton();
    final pending = _joinRequests.where((r) => r['status'] == 'pending').length;
    return ListView(
      padding: NavInsets.content(context, fab: true),
      children: [
        const SizedBox(height: 20),
        Icon(Icons.how_to_reg_rounded,
            size: 40, color: AppColors.green.withValues(alpha: 0.8)),
        const SizedBox(height: 12),
        Text(
          pending == 0
              ? 'No students are waiting'
              : '$pending student${pending == 1 ? '' : 's'} waiting for your decision',
          textAlign: TextAlign.center,
          style: AppTextStyles.titleMedium
              .copyWith(color: AppColors.textPrimaryOf(context)),
        ),
        const SizedBox(height: 6),
        Text(
          'Review who is asking, check their batch and section, then accept or decline.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.textSecondaryOf(context)),
        ),
        const SizedBox(height: 18),
        Center(
          child: FilledButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const JoinRequestsScreen()));
              _load();
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.green),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: Text(pending == 0 ? 'Open join requests' : 'Review $pending request${pending == 1 ? '' : 's'}'),
          ),
        ),
      ],
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
  List<Map<String, dynamic>> _suggestions = [];
  bool _saving = false;

  /// Teaching allocated to this teacher by their department's module leader
  /// and not yet turned into an offering. Picking one fills the form in, which
  /// is the whole point of the allocation existing — the teacher previously
  /// typed the course code, batch and section from memory.
  final _assignmentRepo = TeachingAssignmentRepository();
  List<Map<String, dynamic>> _assignments = [];
  Map<String, dynamic>? _fromAssignment;

  /// Search state. [_searchedFor] is the query the current [_suggestions]
  /// belong to; it is what lets the in-flight guard in [_searchCourses] tell a
  /// completed search from an idle field. It no longer drives any "no match"
  /// message — an unmatched code is perfectly valid and simply gets created.
  bool _searching = false;
  String? _searchedFor;
  int _searchSeq = 0;

  /// Owned here rather than left to AfosTextField's internal node, so the code
  /// field can be focused on open — the sheet used to appear with nothing
  /// focused and no keyboard, which read as "search doesn't work".
  final _codeFocus = FocusNode();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadAssignments();
  }

  Future<void> _loadAssignments() async {
    try {
      final rows = await _assignmentRepo.fetchMyAssignments(readyToOfferOnly: true);
      if (mounted) setState(() => _assignments = rows);
    } catch (_) {
      // Silent: allocations are a shortcut, not a requirement. A teacher whose
      // department has not appointed a module leader yet must still be able to
      // fill the form in by hand.
    }
  }

  /// Fills the form from an allocation. The fields stay editable — a module
  /// leader can mistype a section, and blocking the teacher from fixing it
  /// would just push them back to creating the offering from scratch.
  void _applyAssignment(Map<String, dynamic> a) {
    setState(() {
      _fromAssignment = a;
      _codeCtrl.text = a['course_code'] as String? ?? '';
      final title = a['course_title'] as String? ?? '';
      if (title.isNotEmpty) _titleCtrl.text = title;
      _courseType = a['course_type'] as String? ?? 'theory';
      _batchCtrl.text = a['batch'] as String? ?? '';
      _sectionCtrl.text = a['section'] as String? ?? '';
      _semesterCtrl.text = (a['semester'] as num?)?.toString() ?? '';
      _suggestions = [];
      _searchedFor = null;
    });
    FocusScope.of(context).unfocus();
  }

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
    // NOT a motion token. This is how long to wait for typing to stop before
    // spending a network request; borrowing a rung would couple search latency
    // to animation feel, so retuning `base` would silently change how often the
    // app queries Supabase. Same call as the transport search in batch 2.
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

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
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
      final offeringId = await widget.repo.createOffering(
        courseId: courseId,
        section: _sectionCtrl.text.trim(),
        department: widget.myDepartment,
        batch: _batchCtrl.text.trim(),
        semester: int.parse(_semesterCtrl.text.trim()),
        outlineText: _outlineCtrl.text,
      );
      // Stamps the allocation so the module leader can see it has been acted
      // on. Best-effort inside the repository — the offering is the thing that
      // matters and must not fail because the bookkeeping did.
      final from = _fromAssignment;
      if (from != null) {
        await _assignmentRepo.markClaimed(
            assignmentId: from['id'] as String, offeringId: offeringId);
      }
      widget.onCreated();
      if (mounted) {
        AppHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Submitted for admin approval'), backgroundColor: AppColors.green));
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

              // Anything the module leader allocated and the teacher has not
              // yet opened an offering for. Absent entirely when there is
              // nothing outstanding, so a department without a module leader
              // sees the plain form exactly as before.
              if (_assignments.isNotEmpty) ...[
                Text('Allocated to you',
                    style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
                const SizedBox(height: 6),
                Text('Tap one to fill this form in. You can still edit anything after.',
                    style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
                const SizedBox(height: 8),
                for (final a in _assignments)
                  _AssignmentChoice(
                    assignment: a,
                    selected: _fromAssignment?['id'] == a['id'],
                    onTap: () => _applyAssignment(a),
                  ),
                const SizedBox(height: 16),
              ],

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
              // Suggestions are a CONVENIENCE ONLY — tapping one just fills in
              // the title/credits. Any code is accepted whether or not it
              // matches something already on file; resolveOrCreateCourse
              // creates it on the fly. There used to be a "no existing course
              // matches X" notice on the empty result, which read as though
              // the code were being checked against the routine and had
              // failed. Codes are routinely new or merged, so that notice was
              // wrong to show and is deliberately gone — do not add it back.
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
              // Meetings used to be declared here, one row per session, and at
              // least one was required before the form would submit. They are
              // gone on purpose: the class itself IS the meeting, so there is
              // nothing separate to schedule. Kept as a visible note so a
              // teacher looking for the old "Add" button knows it was removed
              // deliberately rather than hunting for it.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
                  border: Border.all(color: AppColors.blue.withValues(alpha: 0.25), width: 0.5),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.groups_2_outlined, size: 18, color: AppColors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Course meetings are held in class, just before the '
                      'session starts — no separate meeting time to set up.',
                      style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
                    ),
                  ),
                ]),
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

/// Separates live offerings from ended ones, and says plainly what ending a
/// course did — the consequence is invisible everywhere else.
///
/// Public so `course_offering_layout_test` can drive the real widget. A test
/// that re-declares a private row is a copy, and a copy is exactly how the
/// unbounded `Text` in [EndedOfferingRow] below survived review.
class EndedHeader extends StatelessWidget {
  final int count;
  const EndedHeader({super.key, required this.count});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.archive_outlined,
                size: 16, color: AppColors.textSecondaryOf(context)),
            const SizedBox(width: 6),
            Text('Ended ($count)',
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.textPrimaryOf(context))),
          ]),
          const SizedBox(height: 4),
          Text(
              'These are hidden from your class lists, from Attendance and '
              'Results, and from students. Restore one to bring it back.',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondaryOf(context))),
        ]),
      );
}

/// An ended offering: the way back, and the way out.
class EndedOfferingRow extends StatelessWidget {
  final Map<String, dynamic> offering;
  final bool busy;
  final VoidCallback onRestore;

  /// Absent on a row that must not offer deletion. Nothing does today, but the
  /// action destroys student records, so it is opt-in rather than assumed.
  final VoidCallback? onDelete;

  const EndedOfferingRow({
    super.key,
    required this.offering,
    required this.busy,
    required this.onRestore,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final endedAt = DateTime.tryParse(offering['archived_at'] as String? ?? '');
    final enrolled = CourseOfferingRepository.enrolmentCountOf(offering);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        border: Border.all(color: AppColors.borderOf(context), width: 0.5),
      ),
      // Text above, actions below — NOT text beside button.
      //
      // Sharing a Row with the buttons is what starved this text in the first
      // place: a Row lays its non-flex children out first at their full
      // intrinsic width and hands the Expanded whatever is left, which at a
      // large text scale was barely one glyph. An uncapped Text answers a
      // ~1-glyph box by wrapping ONE LETTER PER LINE — a 1178px column of
      // characters under the "Ended" header, overflowing the card by 689px.
      // Giving the text the card's full width removes the competition
      // altogether; the maxLines below stay as a second line of defence, and
      // course_offering_layout_test holds both.
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${course['code'] ?? ''} — ${course['title'] ?? ''}',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium
                .copyWith(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 2),
        Text(
            'Batch ${offering['batch'] ?? ''} · Section ${offering['section'] ?? ''}'
            '${endedAt == null ? '' : ' · ended ${AppFormatters.dateTime(endedAt)}'}',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context))),
        if (enrolled > 0)
          Text('$enrolled ${enrolled == 1 ? 'student' : 'students'} enrolled',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 10),
        // Wrap so the pair drops to a second line instead of clipping, and
        // rowAction so neither button claims the full width on its own.
        Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
          if (onDelete != null)
            TextButton.icon(
              onPressed: busy ? null : onDelete,
              style: TextButton.styleFrom(foregroundColor: AppColors.red),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Delete', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          OutlinedButton(
            onPressed: busy ? null : onRestore,
            style: rowAction(),
            child: busy
                ? const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Restore', maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
      ]),
    );
  }
}

/// One outstanding teaching allocation, offered as a starting point for the
/// New Course Offering form.
class _AssignmentChoice extends StatelessWidget {
  final Map<String, dynamic> assignment;
  final bool selected;
  final VoidCallback onTap;
  const _AssignmentChoice({
    required this.assignment,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isLab = assignment['course_type'] == 'lab';
    final color = selected ? AppColors.green : AppColors.blue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: selected ? 0.14 : 0.06),
            borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
            border: Border.all(
                color: color.withValues(alpha: selected ? 0.5 : 0.22), width: 0.8),
          ),
          child: Row(children: [
            Icon(selected ? Icons.check_circle_rounded : Icons.assignment_outlined,
                size: 17, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${assignment['course_code']} · ${isLab ? 'Lab' : 'Theory'}',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.w600)),
                Text(
                    'Batch ${assignment['batch']} · Section ${assignment['section']}'
                    ' · Semester ${assignment['semester']}',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.textSecondaryOf(context))),
                if ((assignment['note'] as String?)?.isNotEmpty == true)
                  Text(assignment['note'] as String,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondaryOf(context))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
