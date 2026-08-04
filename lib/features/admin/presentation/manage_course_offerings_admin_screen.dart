import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/button_styles.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../schedule/data/repositories/course_offering_repository.dart';
import '../../schedule/presentation/widgets/offering_card.dart';
import '../../../core/layout/nav_insets.dart';

/// Admin-facing approval queue for teacher-declared course offerings.
/// Approving publishes one `schedule_slots` row per declared meeting, so it
/// immediately shows up in every student/teacher schedule view.
///
/// The Reviewed tab exists because approving used to be a one-way door: the
/// card left the pending queue behind a snackbar and there was no record an
/// admin could look at afterwards, so nobody could see who had decided what,
/// or notice a wrong call. `reviewed_by`/`reviewed_at` were written all along
/// and simply never read back.
class ManageCourseOfferingsAdminScreen extends StatefulWidget {
  const ManageCourseOfferingsAdminScreen({super.key});
  @override
  State<ManageCourseOfferingsAdminScreen> createState() =>
      _ManageCourseOfferingsAdminScreenState();
}

class _ManageCourseOfferingsAdminScreenState extends State<ManageCourseOfferingsAdminScreen>
    with SingleTickerProviderStateMixin {
  final _repo = CourseOfferingRepository();
  late final TabController _tab = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _pending = [];
  List<Map<String, dynamic>> _reviewed = [];
  bool _loading = true;
  String? _error;

  /// Per-row: the old single `_busy` flag disabled every card's buttons while
  /// any one of them was in flight.
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

  /// Set once, on the first load: the screen opens on whichever tab has
  /// something in it.
  ///
  /// Pending is the right default when there IS a queue, but it is empty most
  /// of the time — every offering on this project is already decided — so the
  /// screen opened on "Nothing to review" while four offerings sat one
  /// unmarked tap away on Reviewed. An admin looking for a course they had
  /// approved saw a blank page and concluded the screen was broken.
  bool _landed = false;

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _repo.fetchPendingOfferings(),
        _repo.fetchReviewedOfferings(),
      ]);
      if (mounted) {
        setState(() {
          _pending = results[0];
          _reviewed = results[1];
          if (!_landed) {
            _landed = true;
            // Only ever on the first load: doing this on every refresh would
            // yank the tab out from under an admin who had just deliberately
            // switched away from an empty queue.
            if (_pending.isEmpty && _reviewed.isNotEmpty) _tab.index = 1;
          }
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Takes back an approval. This is the counterpart to [_approve] and did not
  /// exist: approving published schedule_slots and notified a whole
  /// batch+section, and the only way back was to ask the teacher to archive
  /// their own course — a different action that reads to them as their fault.
  Future<void> _revoke(Map<String, dynamic> offering) async {
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final label = '${course['code'] ?? 'this course'} · Section ${offering['section'] ?? ''}';
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
                      Text('Withdraw approval for $label?',
                          style: AppTextStyles.headlineLarge
                              .copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
                      const SizedBox(height: 6),
                      Text(
                          'It comes off the routine for the teacher and for every '
                          'student already enrolled, and all of them are told. '
                          'Enrolments are kept, so approving it again restores them.',
                          style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textSecondaryOf(sheetCtx))),
                      const SizedBox(height: 14),
                      AfosTextField(
                          hint: 'Reason (optional)', controller: reasonCtrl, maxLines: 2),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                            child: TextButton(
                                onPressed: () => Navigator.pop(sheetCtx, false),
                                child: const Text('Leave it live'))),
                        Expanded(
                            child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                                onPressed: () => Navigator.pop(sheetCtx, true),
                                child: const Text('Withdraw'))),
                      ]),
                    ]),
              ));
      if (ok != true) return;
      await _act(offering['id'] as String, () async {
        final dropped = await _repo.revokeOffering(
            offeringId: offering['id'] as String,
            reason: reasonCtrl.text.trim(),
            teacherId: offering['teacher_id'] as String?,
            courseLabel: label);
        return 'Approval withdrawn — $dropped '
            '${dropped == 1 ? 'class' : 'classes'} removed from the routine';
      });
    } finally {
      reasonCtrl.dispose();
    }
  }

  /// Puts a declined offering back in the queue, because a decline was
  /// previously as final as an approval — the teacher's only route back was to
  /// submit the whole thing again from scratch.
  Future<void> _reopen(Map<String, dynamic> offering) {
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final label = '${course['code'] ?? 'this course'} · Section ${offering['section'] ?? ''}';
    return _act(offering['id'] as String, () async {
      await _repo.reopenOffering(offering['id'] as String,
          teacherId: offering['teacher_id'] as String?, courseLabel: label);
      return 'Back in the pending queue — the teacher has been told';
    });
  }

  /// Shared busy/refresh/report wrapper for the reviewed-tab actions.
  Future<void> _act(String id, Future<String> Function() action) async {
    setState(() => _busyIds.add(id));
    try {
      final message = await action();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busyIds.remove(id));
  }

  Future<void> _approve(Map<String, dynamic> offering) async {
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final meetings = (offering['course_offering_meetings'] as List?)?.length ?? 0;
    final label = '${course['code'] ?? 'this course'} · Section ${offering['section'] ?? ''}';

    // Approving publishes to every affected student's routine and fires a
    // batch-wide notification, so it gets a confirmation — it previously had
    // none while the less consequential Decline did.
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Approve this offering?'),
        content: Text('$label will go live on the routine as $meetings '
            '${meetings == 1 ? 'class' : 'classes'} per week, and everyone in '
            'Batch ${offering['batch']} Section ${offering['section']} will be notified.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Approve', style: TextStyle(color: AppColors.green))),
        ],
      ),
    );
    if (ok != true) return;

    final id = offering['id'] as String;
    setState(() => _busyIds.add(id));
    try {
      final created = await _repo.approveOffering(offering);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Approved — $created ${created == 1 ? 'class' : 'classes'} added to the routine ✓'),
            backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busyIds.remove(id));
  }

  Future<void> _reject(Map<String, dynamic> offering) async {
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final label = '${course['code'] ?? ''} · Section ${offering['section'] ?? ''}';
    final reasonCtrl = TextEditingController();
    try {
      final confirmed = await showGlassModal<bool>(context,
          builder: (sheetCtx) => Padding(
                padding: EdgeInsets.fromLTRB(
                    24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Decline $label?',
                          style: AppTextStyles.headlineLarge
                              .copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
                      const SizedBox(height: 12),
                      AfosTextField(
                          hint: 'Reason (optional)', controller: reasonCtrl, maxLines: 2),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                            child: TextButton(
                                onPressed: () => Navigator.pop(sheetCtx, false),
                                child: const Text('Cancel'))),
                        Expanded(
                            child: FilledButton(
                                style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                                onPressed: () => Navigator.pop(sheetCtx, true),
                                child: const Text('Decline'))),
                      ]),
                    ]),
              ));
      if (confirmed != true) return;

      final id = offering['id'] as String;
      setState(() => _busyIds.add(id));
      try {
        await _repo.rejectOffering(
          offeringId: id,
          teacherId: offering['teacher_id'] as String,
          courseLabel: label,
          reason: reasonCtrl.text.trim(),
        );
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
        }
      }
      if (mounted) setState(() => _busyIds.remove(id));
    } finally {
      // Was leaked: the controller is created per invocation and was never
      // disposed, so every Decline tap held one for the life of the screen.
      reasonCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Course Offerings'),
      body: Column(children: [
        FeatureHeader(
          title: 'Course Offerings',
          subtitle: _loading
              ? 'Loading…'
              : '${_pending.length} awaiting review · ${_reviewed.length} decided',
          icon: AppIcons.schedule,
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.amber, AppColors.orange]),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.06, curve: Curves.easeOutCubic),
        AnimatedBuilder(
          animation: _tab,
          builder: (ctx, _) => GlassTabBar(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            currentIndex: _tab.index,
            onChanged: (i) => setState(() => _tab.animateTo(i)),
            tabs: [
              GlassTab(_pending.isEmpty ? 'Pending' : 'Pending (${_pending.length})',
                  icon: Icons.inbox_rounded),
              const GlassTab('Reviewed', icon: Icons.history_rounded),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : TabBarView(controller: _tab, children: [
                  RefreshIndicator(onRefresh: _load, child: _body(context)),
                  RefreshIndicator(onRefresh: _load, child: _reviewedTab(context)),
                ]),
        ),
      ]),
    );
  }

  /// The decision record — and, since 20260727094328, the place decisions can
  /// be unmade.
  ///
  /// This was read-only on the grounds that undoing an approval would have to
  /// unpick the generated schedule_slots rows and every student's pins. That
  /// work is real, so it lives in `revoke_course_offering()` where it belongs
  /// rather than being a reason to leave a wrong approval standing forever.
  Widget _reviewedTab(BuildContext context) {
    if (_loading) return const OfferingCardSkeleton();
    if (_reviewed.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 40),
        EmptyState(
            icon: Icons.history_rounded,
            title: 'Nothing reviewed yet',
            subtitle: 'Offerings you approve or decline will be listed here with who decided and when'),
      ]);
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + NavInsets.of(context)),
      itemCount: _reviewed.length,
      itemBuilder: (ctx, i) {
        final o = _reviewed[i];
        final status = o['status'] as String? ?? '';
        final approved = status == 'approved';
        final reviewer = o['reviewer'] as Map<String, dynamic>?;
        final reviewedAtRaw = o['reviewed_at'] as String?;
        final reviewedAt = reviewedAtRaw == null ? null : DateTime.tryParse(reviewedAtRaw);
        final reason = (o['rejection_reason'] as String?)?.trim() ?? '';

        // "Unknown" rather than blank: reviewed_by is ON DELETE SET NULL, so
        // a decision made by a since-deleted admin legitimately has no name.
        final who = reviewer?['full_name'] as String? ?? 'Unknown admin';
        final when = reviewedAt == null ? '' : ' · ${AppFormatters.dateTime(reviewedAt.toLocal())}';

        final busy = _busyIds.contains(o['id'] as String);
        return OfferingCard(
          offering: o,
          index: i,
          // Wrap, not Row: a status pill plus an action button is wider than
          // the card allows on a 320dp phone, and a Row answers that by
          // clipping the button off the edge.
          trailing: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              PillBadge(
                label: approved ? 'APPROVED' : 'DECLINED',
                color: approved ? AppColors.green : AppColors.red,
              ),
              if (approved)
                OutlinedButton(
                  onPressed: busy ? null : () => _revoke(o),
                  style: rowAction(OutlinedButton.styleFrom(foregroundColor: AppColors.red)),
                  child: busy
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Withdraw', maxLines: 1),
                )
              else
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _reopen(o),
                  style: rowAction(),
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: busy
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Reopen', maxLines: 1),
                ),
            ],
          ),
          footer: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(approved ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
                  size: 13, color: AppColors.textSecondaryOf(ctx)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${approved ? 'Approved' : 'Declined'} by $who$when',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.textSecondaryOf(ctx)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            if (!approved && reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Reason: $reason',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.red),
                  maxLines: 3, overflow: TextOverflow.ellipsis),
            ],
          ]),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const OfferingCardSkeleton();
    if (_pending.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 40),
        EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Nothing to review',
            subtitle: 'Course offerings teachers submit will appear here'),
      ]);
    }
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + NavInsets.of(context)),
      itemCount: _pending.length,
      itemBuilder: (ctx, i) {
        final o = _pending[i];
        final busy = _busyIds.contains(o['id'] as String);
        return OfferingCard(
          offering: o,
          index: i,
          // Wrap, not Row: side by side these two buttons need ~301px but the
          // card only offers 297 on a 360dp phone, so the Approve button was
          // clipped off the card's right edge — the super-admin could see the
          // pending offering and had no way to act on it. Wrap drops them onto
          // a second line when they don't fit and is identical when they do.
          trailing: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: busy ? null : () => _reject(o),
                style: rowAction(OutlinedButton.styleFrom(foregroundColor: AppColors.red)),
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: busy ? null : () => _approve(o),
                style: rowAction(FilledButton.styleFrom(backgroundColor: AppColors.green)),
                child: busy
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Approve'),
              ),
            ],
          ),
        );
      },
    );
  }
}
