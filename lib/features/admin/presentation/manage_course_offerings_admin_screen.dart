import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../schedule/data/repositories/course_offering_repository.dart';
import '../../schedule/presentation/widgets/offering_card.dart';
import '../../../core/layout/nav_insets.dart';

/// Admin-facing approval queue for teacher-declared course offerings.
/// Approving publishes one `schedule_slots` row per declared meeting, so it
/// immediately shows up in every student/teacher schedule view.
class ManageCourseOfferingsAdminScreen extends StatefulWidget {
  const ManageCourseOfferingsAdminScreen({super.key});
  @override
  State<ManageCourseOfferingsAdminScreen> createState() =>
      _ManageCourseOfferingsAdminScreenState();
}

class _ManageCourseOfferingsAdminScreenState extends State<ManageCourseOfferingsAdminScreen> {
  final _repo = CourseOfferingRepository();
  List<Map<String, dynamic>> _pending = [];
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

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await _repo.fetchPendingOfferings();
      if (mounted) setState(() => _pending = res);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
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
          title: 'Pending Offerings',
          subtitle: _loading ? 'Loading…' : '${_pending.length} awaiting review',
          icon: AppIcons.schedule,
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.amber, AppColors.orange]),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.06, curve: Curves.easeOutCubic),
        Expanded(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _body(context)),
        ),
      ]),
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
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
                child: const Text('Decline'),
              ),
              FilledButton(
                onPressed: busy ? null : () => _approve(o),
                style: FilledButton.styleFrom(backgroundColor: AppColors.green),
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
