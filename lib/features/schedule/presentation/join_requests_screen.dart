import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/user_details_sheet.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/course_offering_repository.dart';
import 'widgets/offering_card.dart' show offeringStatusColor;

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
/// being swept in by an empty-string comparison.
bool joinRequestMatchesSection(Map<String, dynamic> request) {
  if (request['status'] != 'pending') return false;
  final s = request['profiles'] as Map<String, dynamic>? ?? const {};
  final o = request['course_offerings'] as Map<String, dynamic>? ?? const {};
  final sb = _normKey(s['batch']), ss = _normKey(s['section']);
  if (sb.isEmpty || ss.isEmpty) return false;
  return sb == _normKey(o['batch']) && ss == _normKey(o['section']);
}

/// Students asking to join this teacher's courses — accept, decline, and
/// review who is actually asking.
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
///
/// It is also simply the better home for it. A teacher deciding who is in
/// their class is a task, not a sub-view of managing offerings, and as a tab
/// it was invisible from the menu and easy to never find.
class JoinRequestsScreen extends StatefulWidget {
  const JoinRequestsScreen({super.key});

  @override
  State<JoinRequestsScreen> createState() => _JoinRequestsScreenState();
}

class _JoinRequestsScreenState extends State<JoinRequestsScreen> {
  final _repo = CourseOfferingRepository();
  List<Map<String, dynamic>> _requests = [];
  final Set<String> _busyIds = {};
  bool _loading = true, _bulkBusy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await _repo.fetchOfferingJoinRequests();
      if (mounted) setState(() => _requests = rows);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> get _pending =>
      _requests.where((r) => r['status'] == 'pending').toList();

  static String? _studentIdOf(Map<String, dynamic> r) =>
      (r['profiles'] as Map<String, dynamic>?)?['id'] as String?;

  static String? _courseCodeOf(Map<String, dynamic> r) =>
      ((r['course_offerings'] as Map?)?['courses'] as Map?)?['code'] as String?;

  Future<void> _respond(Map<String, dynamic> r, bool approve) async {
    final id = r['id'] as String;
    setState(() => _busyIds.add(id));
    try {
      if (approve) {
        await _repo.approveJoin(id,
            studentId: _studentIdOf(r), courseCode: _courseCodeOf(r));
      } else {
        await _repo.rejectJoin(id,
            studentId: _studentIdOf(r), courseCode: _courseCodeOf(r));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busyIds.remove(id));
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

    setState(() => _bulkBusy = true);
    var done = 0;
    final failures = <String>[];
    for (final r in matching) {
      try {
        await _repo.approveJoin(r['id'] as String,
            studentId: _studentIdOf(r), courseCode: _courseCodeOf(r));
        done++;
      } catch (e) {
        // Keep going: one rejection (a full section, say) must not strand the
        // rest. Failures are reported at the end rather than swallowed.
        final name = (r['profiles'] as Map?)?['full_name'] as String? ?? 'A student';
        failures.add('$name — ${friendlyError(e)}');
      }
    }
    await _load();
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failures.isEmpty
          ? 'Admitted $done student${done == 1 ? '' : 's'} ✓'
          : 'Admitted $done · ${failures.length} failed: ${failures.first}'),
      backgroundColor: failures.isEmpty ? AppColors.green : AppColors.amber,
      duration: Duration(seconds: failures.isEmpty ? 3 : 6),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending.length;
    final matching = _requests.where(joinRequestMatchesSection).length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(
          title: pending > 0 ? 'Join Requests ($pending)' : 'Join Requests'),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(children: [
                    ShimmerCard(height: 150), SizedBox(height: 12),
                    ShimmerCard(height: 150),
                  ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: NavInsets.content(context),
                    children: [
                      // Always rendered, even when the list is empty. If the
                      // count and the visible rows ever disagree again, that
                      // is now readable on the device instead of being an
                      // invisible contradiction.
                      _CountLine(total: _requests.length, pending: pending),
                      const SizedBox(height: 10),
                      if (matching >= 2) ...[
                        _BulkAdmitBar(
                            matching: matching,
                            total: pending,
                            busy: _bulkBusy,
                            onTap: _admitAllMatching),
                        const SizedBox(height: 12),
                      ],
                      if (_requests.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 30),
                          child: EmptyState(
                              icon: Icons.how_to_reg_outlined,
                              title: 'No join requests',
                              subtitle:
                                  'Students who apply to your approved offerings appear here'),
                        )
                      else
                        for (final r in _requests)
                          // Each row is isolated: in a release build a widget
                          // that throws paints as blank space, which is
                          // indistinguishable from "no data" and is exactly how
                          // a rendering fault could hide an entire list. This
                          // turns that into a visible, reportable row.
                          _SafeRow(
                            child: _JoinRequestCard(
                              request: r,
                              busy: _busyIds.contains(r['id']) || _bulkBusy,
                              onAccept: () => _respond(r, true),
                              onDecline: () => _respond(r, false),
                            ),
                          ),
                    ],
                  ),
                ),
    );
  }
}

/// States plainly how many rows were loaded, so a blank list can never again be
/// mistaken for an empty one.
class _CountLine extends StatelessWidget {
  final int total, pending;
  const _CountLine({required this.total, required this.pending});

  @override
  Widget build(BuildContext context) => Text(
        total == 0
            ? 'No requests loaded'
            : '$total request${total == 1 ? '' : 's'} loaded · $pending awaiting your decision',
        style: AppTextStyles.labelSmall
            .copyWith(color: AppColors.textSecondaryOf(context)),
      );
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
/// the decision.
///
/// A plain Container rather than the shared glass InfoCard, and no entrance
/// animation. Both were suspects while this list was rendering blank, and
/// neither is worth reintroducing for a queue of decisions — the point here is
/// that the row is visible unconditionally.
class _JoinRequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final bool busy;
  final VoidCallback onAccept, onDecline;
  const _JoinRequestCard({
    required this.request,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final student = request['profiles'] as Map<String, dynamic>? ?? const {};
    final offering = request['course_offerings'] as Map<String, dynamic>? ?? const {};
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final status = request['status'] as String? ?? 'pending';
    final accent = offeringStatusColor(status);
    final requestedAt = DateTime.tryParse(request['created_at'] as String? ?? '');

    void openDetails() => showUserDetailsSheet(context, student, extraRows: {
          'Email': student['email'] as String? ?? '',
          if ((student['semester'] as num?) != null) 'Semester': '${student['semester']}',
          if (requestedAt != null) 'Requested': AppFormatters.dateTime(requestedAt),
        });

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        border: Border.all(color: accent.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: openDetails,
            child: _StudentAvatar(
                name: student['full_name'] as String?,
                avatarUrl: student['avatar_url'] as String?),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: openDetails,
              behavior: HitTestBehavior.opaque,
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
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondaryOf(context))),
                Text('Tap for full details',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.blue.withValues(alpha: 0.85))),
              ]),
            ),
          ),
          PillBadge(label: status.toUpperCase(), color: accent),
        ]),
        const SizedBox(height: 10),
        Text('wants to join ${course['code'] ?? ''} · Section ${offering['section'] ?? ''}',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 6),
        _BatchMatchNotice(
          studentBatch: student['batch'] as String?,
          studentSection: student['section'] as String?,
          offeringBatch: offering['batch'] as String?,
          offeringSection: offering['section'] as String?,
        ),
        if (status == 'pending') ...[
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(
              onPressed: busy ? null : onDecline,
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
              child: const Text('Decline'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: busy ? null : onAccept,
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
    );
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
                style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w600)),
            Text(
                others > 0
                    ? '$others other${others == 1 ? '' : 's'} need${others == 1 ? 's' : ''} a look first'
                    : 'Everyone waiting matches',
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
              : const Text('Admit all'),
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
