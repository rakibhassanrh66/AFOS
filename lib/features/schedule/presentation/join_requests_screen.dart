import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../config/app_config.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/course_offering_repository.dart';
import 'join_request_detail_screen.dart';

String _normKey(Object? v) => (v as String? ?? '').trim().toUpperCase();

/// Whether a pending join request comes from a student already in the batch
/// and section of the offering they applied to — the same comparison the
/// card's notice shows the teacher.
///
/// Top-level and public because it decides who the bulk admit lets in WITHOUT
/// individual review, which makes it the one piece of this screen that must be
/// pinned by a test.
///
/// Deliberately conservative: a student with no batch or section recorded is
/// NOT a match, so an incomplete profile is always reviewed by hand instead of
/// being swept in by an empty-string comparison. A request against an ended
/// course is never a match either — the database refuses that approval, so
/// sweeping it into a bulk admit would guarantee a failure.
bool joinRequestMatchesSection(Map<String, dynamic> request) {
  if (request['status'] != 'pending') return false;
  final s = request['profiles'] as Map<String, dynamic>? ?? const {};
  final o = request['course_offerings'] as Map<String, dynamic>? ?? const {};
  if (o['is_archived'] == true) return false;
  final sb = _normKey(s['batch']), ss = _normKey(s['section']);
  if (sb.isEmpty || ss.isEmpty) return false;
  return sb == _normKey(o['batch']) && ss == _normKey(o['section']);
}

/// The three things a request can be, and the three jobs the teacher has.
enum _Filter { waiting, enrolled, declined }

/// Students asking to join this teacher's courses — accept, decline, review who
/// is actually asking, and undo any of it.
///
/// WHY THIS IS ITS OWN SCREEN, not a tab.
///
/// It lived as the second tab of My Course Offerings, and reproducibly showed
/// a live count in the tab title with nothing rendered underneath. The data
/// was never the problem: probed as the authenticated teacher, the rows, the
/// profile embeds and the RLS all came back correct every time. Three separate
/// theories for the blank render — the entrance animation, the card's
/// BackdropFilter, the scroll padding — were each disproved, because the tab
/// that worked used the identical widget, blur and animation.
///
/// So rather than keep guessing at an unreproducible rendering fault inside a
/// TabBarView, this removes the variable: a plain Scaffold with a plain
/// ListView, reachable by its own route, with no PageView, no TickerMode
/// subtlety and no lazily-built sibling page in the way.
class JoinRequestsScreen extends StatefulWidget {
  const JoinRequestsScreen({super.key});

  @override
  State<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends State<JoinRequestsScreen> {
  final _repo = CourseOfferingRepository();
  List<Map<String, dynamic>> _requests = [];
  final Set<String> _busyIds = {};

  /// Enrolment ids ticked for a batch decision. Only ever holds pending rows —
  /// [_visible] clears it whenever the filter moves off Waiting, so a selection
  /// can never survive into a tab where the buttons mean something else.
  final Set<String> _selected = {};

  _Filter _filter = _Filter.waiting;
  bool _loading = true, _bulkBusy = false;
  String? _error;

  /// Identity of the signed-in teacher and how many offerings they own.
  ///
  /// Fetched purely so an empty list can explain ITSELF. "No requests" has
  /// three completely different causes that look identical on screen — signed
  /// in as a teacher who owns no course, signed in as the wrong teacher, or a
  /// query that genuinely returns nothing — and without this the only way to
  /// tell them apart was for me to guess.
  String? _whoEmail;
  int _myOfferings = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // _bulkBusy is cleared here as well as at the end of _admitAllMatching.
    // It disables EVERY row's Accept and Decline, so if it ever stuck true the
    // whole screen would look present and correct while no button did anything
    // — indistinguishable from the buttons being missing, which is the exact
    // complaint this screen already has a history of. A pull-to-refresh now
    // always recovers it.
    setState(() { _loading = true; _error = null; _bulkBusy = false; });
    try {
      final rows = await _repo.fetchOfferingJoinRequests();
      final mine = await _repo.fetchMyOfferings();
      final uid = SupabaseConfig.uid;
      final me = uid == null
          ? null
          : await SupabaseConfig.client
              .from('profiles').select('email, role').eq('id', uid).maybeSingle();
      if (mounted) {
        setState(() {
          _requests = rows;
          // A decision may have removed a row entirely (remove_course_enrollment
          // deletes it), so anything selected that no longer exists is dropped
          // rather than left to act on a dead id.
          final live = rows.map((r) => r['id'] as String).toSet();
          _selected.removeWhere((id) => !live.contains(id));
          _myOfferings = mine
              .where((o) => o['status'] == 'approved' && o['is_archived'] != true)
              .length;
          _whoEmail = me == null
              ? null
              : '${me['email'] ?? 'unknown'} · ${me['role'] ?? '?'}';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  // --------------------------------------------------------------- selectors

  List<Map<String, dynamic>> get _pending =>
      _requests.where((r) => r['status'] == 'pending').toList();

  List<Map<String, dynamic>> get _visible => switch (_filter) {
        _Filter.waiting => _pending,
        _Filter.enrolled => _requests.where((r) => r['status'] == 'approved').toList(),
        _Filter.declined => _requests.where((r) => r['status'] == 'rejected').toList(),
      };

  static String? _studentIdOf(Map<String, dynamic> r) =>
      (r['profiles'] as Map<String, dynamic>?)?['id'] as String?;

  static String? _courseCodeOf(Map<String, dynamic> r) =>
      ((r['course_offerings'] as Map?)?['courses'] as Map?)?['code'] as String?;

  static bool _isArchived(Map<String, dynamic> r) =>
      (r['course_offerings'] as Map?)?['is_archived'] == true;

  // ---------------------------------------------------------------- actions

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

  Future<void> _accept(Map<String, dynamic> r) => _guard(r['id'] as String,
      () => _repo.approveJoin(r['id'] as String,
          studentId: _studentIdOf(r), courseCode: _courseCodeOf(r)));

  Future<void> _decline(Map<String, dynamic> r) => _guard(r['id'] as String,
      () => _repo.rejectJoin(r['id'] as String,
          studentId: _studentIdOf(r), courseCode: _courseCodeOf(r)));

  Future<void> _reconsider(Map<String, dynamic> r) =>
      _guard(r['id'] as String, () => _repo.reopenJoinRequest(r['id'] as String));

  /// Removing an admitted student unpins the course from their routine and
  /// deletes the enrolment, so it asks first and lets the teacher say why —
  /// the student is notified either way and "you are out of this class" with
  /// no explanation is worse than useless to them.
  Future<void> _remove(Map<String, dynamic> r) async {
    final name = (r['profiles'] as Map?)?['full_name'] as String? ?? 'This student';
    final reasonCtrl = TextEditingController();
    try {
      final ok = await showGlassModal<bool>(context,
          builder: (sheetCtx) => Padding(
                padding: EdgeInsets.fromLTRB(
                    24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Remove $name?',
                          style: AppTextStyles.headlineLarge
                              .copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
                      const SizedBox(height: 6),
                      Text(
                          '${_courseCodeOf(r) ?? 'This course'} comes off their routine '
                          'and they lose the course group. They can apply again.',
                          style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondaryOf(sheetCtx))),
                      const SizedBox(height: 14),
                      AfosTextField(
                          hint: 'Reason (optional, shown to them)',
                          controller: reasonCtrl,
                          maxLines: 2),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                            child: TextButton(
                                onPressed: () => Navigator.pop(sheetCtx, false),
                                child: const Text('Keep them'))),
                        Expanded(
                            child: FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.red),
                                onPressed: () => Navigator.pop(sheetCtx, true),
                                child: const Text('Remove'))),
                      ]),
                    ]),
              ));
      if (ok != true) return;
      await _guard(r['id'] as String,
          () => _repo.removeEnrollment(r['id'] as String, reason: reasonCtrl.text.trim()));
    } finally {
      reasonCtrl.dispose();
    }
  }

  /// Runs one decision over every ticked row, or over everyone whose batch and
  /// section already match.
  ///
  /// [rows] is captured before the loop: `_load()` runs at the end and would
  /// otherwise mutate the list being iterated. Failures are collected rather
  /// than thrown, so one rejection — a request against a course that has since
  /// ended, say — cannot strand the rest of the batch.
  Future<void> _runBatch(
      List<Map<String, dynamic>> rows, bool approve, String verb) async {
    if (rows.isEmpty) return;
    setState(() => _bulkBusy = true);
    var done = 0;
    final failures = <String>[];
    for (final r in rows) {
      try {
        if (approve) {
          await _repo.approveJoin(r['id'] as String,
              studentId: _studentIdOf(r), courseCode: _courseCodeOf(r));
        } else {
          await _repo.rejectJoin(r['id'] as String,
              studentId: _studentIdOf(r), courseCode: _courseCodeOf(r));
        }
        done++;
      } catch (e) {
        final name = (r['profiles'] as Map?)?['full_name'] as String? ?? 'A student';
        failures.add('$name — ${friendlyError(e)}');
      }
    }
    _selected.clear();
    await _load();
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failures.isEmpty
          ? '$verb $done student${done == 1 ? '' : 's'} ✓'
          : '$verb $done · ${failures.length} failed: ${failures.first}'),
      backgroundColor: failures.isEmpty ? AppColors.green : AppColors.amber,
      duration: Duration(seconds: failures.isEmpty ? 3 : 6),
    ));
  }

  /// Admits every pending requester whose batch and section match the offering.
  ///
  /// A theory section is fifty students; approving one at a time is fifty taps
  /// and fifty round-trips. Mismatches are deliberately excluded and left for
  /// individual review — a retaker or someone who moved section is a real
  /// decision, and this must never make it silently.
  Future<void> _admitAllMatching() async {
    final matching = _requests.where(joinRequestMatchesSection).toList();
    if (matching.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Admit ${matching.length} student${matching.length == 1 ? '' : 's'}?'),
        content: const Text(
            'These are the requesters already in the batch and section of the '
            'offering they applied to.\n\n'
            'Anyone whose batch or section does not match is left for you to '
            'review one by one.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Admit all')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runBatch(matching, true, 'Admitted');
  }

  Future<void> _decideSelected(bool approve) async {
    final rows = _pending.where((r) => _selected.contains(r['id'])).toList();
    if (rows.isEmpty) return;
    if (approve && rows.any(_isArchived)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('One of those is for a course that has ended — untick it first'),
          backgroundColor: AppColors.amber));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('${approve ? 'Accept' : 'Decline'} ${rows.length} '
            'selected student${rows.length == 1 ? '' : 's'}?'),
        content: Text(approve
            ? 'They are added to the class and the course lands on their routine.'
            : 'They are told the request was not accepted. You can put any of them back afterwards.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(approve ? 'Accept' : 'Decline',
                  style: TextStyle(color: approve ? AppColors.green : AppColors.red))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _runBatch(rows, approve, approve ? 'Accepted' : 'Declined');
  }

  Future<void> _openDetail(Map<String, dynamic> r) async {
    final status = r['status'] as String? ?? 'pending';
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => JoinRequestDetailScreen(
        request: r,
        onAccept: status == 'pending'
            ? () => _repo.approveJoin(r['id'] as String,
                studentId: _studentIdOf(r), courseCode: _courseCodeOf(r))
            : null,
        onDecline: status == 'pending'
            ? () => _repo.rejectJoin(r['id'] as String,
                studentId: _studentIdOf(r), courseCode: _courseCodeOf(r))
            : null,
        onRemove: status == 'approved'
            ? () => _repo.removeEnrollment(r['id'] as String)
            : null,
        onReconsider: status == 'rejected'
            ? () => _repo.reopenJoinRequest(r['id'] as String)
            : null,
      ),
    ));
    if (changed == true) await _load();
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final pending = _pending.length;
    final matching = _requests.where(joinRequestMatchesSection).length;
    final enrolled = _requests.where((r) => r['status'] == 'approved').length;
    final declined = _requests.where((r) => r['status'] == 'rejected').length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(
          title: pending > 0 ? 'Join Requests ($pending)' : 'Join Requests'),
      // The batch bar is pinned to the bottom rather than floated in the list:
      // a selection made at row 30 must stay actionable without scrolling back.
      bottomNavigationBar: _selected.isEmpty
          ? null
          : _SelectionBar(
              count: _selected.length,
              busy: _bulkBusy,
              onClear: () => setState(_selected.clear),
              onAccept: () => _decideSelected(true),
              onDecline: () => _decideSelected(false),
            ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(children: [
                    ShimmerCard(height: 150), SizedBox(height: 12),
                    ShimmerCard(height: 150),
                  ]))
              : Column(children: [
                  const SizedBox(height: 8),
                  GlassTabBar(
                    margin: const EdgeInsets.symmetric(horizontal: 12),
                    currentIndex: _Filter.values.indexOf(_filter),
                    onChanged: (i) => setState(() {
                      _filter = _Filter.values[i];
                      // A tick means "accept or decline this"; neither verb
                      // exists on the other two tabs, so carrying a selection
                      // across would leave a bar offering the wrong action.
                      _selected.clear();
                    }),
                    tabs: [
                      GlassTab(pending == 0 ? 'Waiting' : 'Waiting ($pending)',
                          icon: Icons.how_to_reg_rounded),
                      GlassTab(enrolled == 0 ? 'Enrolled' : 'Enrolled ($enrolled)',
                          icon: Icons.groups_2_outlined),
                      GlassTab(declined == 0 ? 'Declined' : 'Declined ($declined)',
                          icon: Icons.person_off_outlined),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: RefreshIndicator(onRefresh: _load, child: _list(matching)),
                  ),
                ]),
    );
  }

  Widget _list(int matching) {
    final rows = _visible;
    return ListView(
      padding: NavInsets.content(context, top: 0),
      children: [
        // Always rendered, even when the list is empty. If the count and the
        // visible rows ever disagree again, that is now readable on the device
        // instead of being an invisible contradiction.
        _CountLine(
            total: _requests.length,
            pending: _pending.length,
            who: _whoEmail,
            offerings: _myOfferings),
        const SizedBox(height: 10),
        if (_filter == _Filter.waiting && matching >= 2) ...[
          _BulkAdmitBar(
              matching: matching,
              total: _pending.length,
              busy: _bulkBusy,
              onTap: _admitAllMatching),
          const SizedBox(height: 12),
        ],
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 30),
            child: EmptyState(
              icon: switch (_filter) {
                _Filter.waiting => Icons.how_to_reg_outlined,
                _Filter.enrolled => Icons.groups_2_outlined,
                _Filter.declined => Icons.person_off_outlined,
              },
              title: switch (_filter) {
                _Filter.waiting => 'Nobody is waiting',
                _Filter.enrolled => 'Nobody enrolled yet',
                _Filter.declined => 'Nobody declined',
              },
              subtitle: switch (_filter) {
                _Filter.waiting =>
                  'Students who apply to your approved offerings appear here',
                _Filter.enrolled =>
                  'Students you accept show up here, and you can remove one if it was a mistake',
                _Filter.declined =>
                  'Requests you turn down stay here so you can put one back',
              },
            ),
          )
        else
          for (final r in rows)
            // Each row is isolated: in a release build a widget that throws
            // paints as blank space, which is indistinguishable from "no data"
            // and is exactly how a rendering fault could hide an entire list.
            // This turns that into a visible, reportable row.
            _SafeRow(
              child: _JoinRequestCard(
                request: r,
                busy: _busyIds.contains(r['id']) || _bulkBusy,
                selectable: _filter == _Filter.waiting,
                selected: _selected.contains(r['id']),
                onToggleSelected: () => setState(() {
                  final id = r['id'] as String;
                  _selected.contains(id) ? _selected.remove(id) : _selected.add(id);
                }),
                onOpen: () => _openDetail(r),
                onAccept: () => _accept(r),
                onDecline: () => _decline(r),
                onRemove: () => _remove(r),
                onReconsider: () => _reconsider(r),
              ),
            ),
      ],
    );
  }
}

/// The batch action bar. Only mounted while something is ticked.
class _SelectionBar extends StatelessWidget {
  final int count;
  final bool busy;
  final VoidCallback onClear, onAccept, onDecline;
  const _SelectionBar({
    required this.count,
    required this.busy,
    required this.onClear,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + NavInsets.of(context)),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context), width: 0.5)),
      ),
      // Wrap, not Row: three controls plus a count do not fit side by side on a
      // 320dp phone at a large text scale, and a Row answers that by clipping
      // the last one off the edge — which here would be the Accept button.
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('$count selected',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textPrimaryOf(context))),
          TextButton(onPressed: busy ? null : onClear, child: const Text('Clear')),
          OutlinedButton(
            onPressed: busy ? null : onDecline,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: busy ? null : onAccept,
            style: FilledButton.styleFrom(backgroundColor: AppColors.green),
            child: busy
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Accept'),
          ),
        ],
      ),
    );
  }
}

/// States plainly how many rows were loaded, so a blank list can never again be
/// mistaken for an empty one.
class _CountLine extends StatelessWidget {
  final int total, pending, offerings;
  final String? who;
  const _CountLine({
    required this.total,
    required this.pending,
    required this.who,
    required this.offerings,
  });

  @override
  Widget build(BuildContext context) {
    final dim = AppTextStyles.labelSmall
        .copyWith(color: AppColors.textSecondaryOf(context));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        total == 0
            ? 'No requests loaded'
            : '$total request${total == 1 ? '' : 's'} loaded · $pending awaiting your decision',
        style: dim,
      ),
      const SizedBox(height: 2),
      // Deliberately always shown, not hidden behind a debug flag. Three very
      // different causes of an empty list look identical on screen — the wrong
      // teacher is signed in, the right one owns no approved course, or the
      // query really is returning nothing — and this is the difference between
      // reading the answer off the device and me guessing at it again.
      Text(
        'v${AppConfig.appVersion} · ${who ?? 'not signed in'} · '
        '$offerings approved offering${offerings == 1 ? '' : 's'}',
        style: dim.copyWith(fontSize: 10),
      ),
      if (total == 0 && offerings == 0) ...[
        const SizedBox(height: 6),
        Text(
          'You own no approved offering, so no student can apply to you yet. '
          'That is why this is empty.',
          style: dim.copyWith(color: AppColors.amber),
        ),
      ],
    ]);
  }
}

/// Catches a build failure in one row and shows it, rather than letting the
/// framework paint empty space where a card should be.
class _SafeRow extends StatelessWidget {
  final Widget child;
  const _SafeRow({required this.child});

  @override
  Widget build(BuildContext context) {
    try {
      return child;
    } catch (e) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
          border: Border.all(color: AppColors.red.withValues(alpha: 0.4), width: 0.8),
        ),
        child: Text('This request could not be displayed: $e',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.red)),
      );
    }
  }
}

/// One join request: who is asking, whether they belong in this section, and
/// the decision — including the decisions that undo an earlier one.
///
/// A plain Container rather than the shared glass InfoCard, and no entrance
/// animation. Both were suspects while this list was rendering blank, and
/// neither is worth reintroducing for a queue of decisions — the point here is
/// that the row is visible unconditionally.
class _JoinRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final bool busy, selectable, selected;
  final VoidCallback onToggleSelected, onOpen;
  final VoidCallback onAccept, onDecline, onRemove, onReconsider;
  const _JoinRequestCard({
    required this.request,
    required this.busy,
    required this.selectable,
    required this.selected,
    required this.onToggleSelected,
    required this.onOpen,
    required this.onAccept,
    required this.onDecline,
    required this.onRemove,
    required this.onReconsider,
  });

  @override
  Widget build(BuildContext context) {
    final student = request['profiles'] as Map<String, dynamic>? ?? const {};
    final offering = request['course_offerings'] as Map<String, dynamic>? ?? const {};
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final status = request['status'] as String? ?? 'pending';
    final archived = offering['is_archived'] == true;
    final accent = selected ? AppColors.blue : _statusColor(status);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.blue.withValues(alpha: 0.08)
            : AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        border: Border.all(
            color: accent.withValues(alpha: selected ? 0.6 : 0.35),
            width: selected ? 1.2 : 0.8),
      ),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (selectable)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Checkbox(
                    value: selected,
                    onChanged: busy ? null : (_) => onToggleSelected(),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              _StudentAvatar(
                  name: student['full_name'] as String?,
                  avatarUrl: student['avatar_url'] as String?),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(student['full_name'] as String? ?? 'Student',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.titleMedium
                              .copyWith(color: AppColors.textPrimaryOf(context))),
                    ),
                    if (student['is_verified'] == true)
                      const Padding(
                        padding: EdgeInsets.only(left: 5),
                        child: Icon(Icons.verified_rounded, size: 15, color: AppColors.blue),
                      ),
                  ]),
                  if ((student['university_id'] as String?)?.isNotEmpty == true)
                    Text(student['university_id'] as String,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.textSecondaryOf(context))),
                  Text('Tap to review the full profile',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.blue.withValues(alpha: 0.85))),
                ]),
              ),
              const SizedBox(width: 8),
              PillBadge(label: status.toUpperCase(), color: _statusColor(status)),
            ]),
            const SizedBox(height: 10),
            Text(
                '${status == 'approved' ? 'enrolled in' : 'wants to join'} '
                '${course['code'] ?? ''} · Section ${offering['section'] ?? ''}',
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondaryOf(context))),
            const SizedBox(height: 6),
            _BatchMatchNotice(
              studentBatch: student['batch'] as String?,
              studentSection: student['section'] as String?,
              offeringBatch: offering['batch'] as String?,
              offeringSection: offering['section'] as String?,
            ),
            if (archived && status != 'approved') ...[
              const SizedBox(height: 6),
              Text(
                  'This course has ended — it cannot take anyone new until it is restored.',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.red)),
            ],
            const SizedBox(height: 12),
            _actions(status, archived),
          ]),
        ),
      ),
    );
  }

  static Color _statusColor(String s) => switch (s) {
        'approved' => AppColors.green,
        'rejected' => AppColors.red,
        _ => AppColors.amber,
      };

  /// Every state now has something to do. Before this, only `pending` did — an
  /// admitted student could not be removed and a declined one could not be
  /// reconsidered, so two thirds of this queue was a read-only archive.
  Widget _actions(String status, bool archived) {
    final children = switch (status) {
      'pending' => [
          OutlinedButton(
            onPressed: busy ? null : onDecline,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Decline', maxLines: 1),
          ),
          FilledButton(
            onPressed: (busy || archived) ? null : onAccept,
            style: FilledButton.styleFrom(backgroundColor: AppColors.green),
            child: busy
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Accept', maxLines: 1),
          ),
        ],
      'approved' => [
          OutlinedButton.icon(
            onPressed: busy ? null : onRemove,
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
            icon: const Icon(Icons.person_remove_outlined, size: 16),
            label: const Text('Remove', maxLines: 1),
          ),
        ],
      'rejected' => [
          OutlinedButton.icon(
            onPressed: busy ? null : onReconsider,
            icon: const Icon(Icons.undo_rounded, size: 16),
            label: const Text('Reconsider', maxLines: 1),
          ),
        ],
      _ => const <Widget>[],
    };
    if (children.isEmpty) return const SizedBox.shrink();
    // Wrap, not Row: the Decline/Accept pair needs ~301px and a 360dp card
    // offers 297, which clipped Accept off the right edge and left the teacher
    // looking at a request they could see and could not act on.
    return Wrap(
        alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: children);
  }
}

/// Offers to admit every requester whose batch and section already match.
class _BulkAdmitBar extends StatelessWidget {
  final int matching, total;
  final bool busy;
  final VoidCallback onTap;
  const _BulkAdmitBar({
    required this.matching,
    required this.total,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final others = total - matching;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        border: Border.all(color: AppColors.green.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Row(children: [
        const Icon(Icons.done_all_rounded, size: 18, color: AppColors.green),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$matching in the right batch & section',
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w600)),
            Text(
                others > 0
                    ? '$others other${others == 1 ? '' : 's'} need${others == 1 ? 's' : ''} a look first'
                    : 'Everyone waiting matches',
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondaryOf(context))),
          ]),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: busy ? null : onTap,
          style: FilledButton.styleFrom(backgroundColor: AppColors.green),
          child: busy
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Admit all', maxLines: 1),
        ),
      ]),
    );
  }
}

/// Requester's profile photo, falling back to their initial.
class _StudentAvatar extends StatelessWidget {
  final String? name;
  final String? avatarUrl;
  const _StudentAvatar({required this.name, required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    final hasUrl = url != null && url.isNotEmpty;
    final initial = (name?.trim().isNotEmpty == true ? name!.trim()[0] : '?').toUpperCase();
    return CircleAvatar(
      radius: 22,
      backgroundColor: AppColors.blue.withValues(alpha: 0.15),
      backgroundImage: hasUrl ? CachedNetworkImageProvider(url) : null,
      child: hasUrl
          ? null
          : Text(initial,
              style: const TextStyle(
                  color: AppColors.blue, fontSize: 18, fontWeight: FontWeight.w800)),
    );
  }
}

/// Answers the one question this card exists for: is this requester actually in
/// the batch and section being taught?
///
/// A mismatch is legitimate — a retaker, or someone who moved section — so this
/// informs rather than blocks, but it must be impossible to miss.
class _BatchMatchNotice extends StatelessWidget {
  final String? studentBatch, studentSection, offeringBatch, offeringSection;
  const _BatchMatchNotice({
    required this.studentBatch,
    required this.studentSection,
    required this.offeringBatch,
    required this.offeringSection,
  });

  @override
  Widget build(BuildContext context) {
    final sb = _normKey(studentBatch), ss = _normKey(studentSection);
    final ob = _normKey(offeringBatch), os = _normKey(offeringSection);

    late final Color color;
    late final IconData icon;
    late final String message;

    if (sb.isEmpty || ss.isEmpty) {
      color = AppColors.amber;
      icon = Icons.help_outline_rounded;
      message = 'This student has not set their batch or section yet.';
    } else if (sb == ob && ss == os) {
      color = AppColors.green;
      icon = Icons.check_circle_outline_rounded;
      message = 'In batch $sb, section $ss — matches this offering.';
    } else {
      color = AppColors.amber;
      icon = Icons.error_outline_rounded;
      message = 'In batch ${sb.isEmpty ? '—' : sb}, section ${ss.isEmpty ? '—' : ss}'
          ' — this offering is batch $ob, section $os.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 0.5),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, style: AppTextStyles.labelSmall.copyWith(color: color)),
        ),
      ]),
    );
  }
}
