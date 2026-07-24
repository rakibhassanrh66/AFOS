import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_bottom_nav.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../schedule/data/repositories/course_offering_repository.dart';
import '../../shell/presentation/top_app_bar.dart';

const _dayLabels = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

/// Admin-facing approval queue for teacher-declared course offerings.
/// Approving an offering generates the matching `schedule_slots` row so it
/// immediately shows up in every student/teacher schedule view.
class ManageCourseOfferingsAdminScreen extends StatefulWidget {
  const ManageCourseOfferingsAdminScreen({super.key});
  @override State<ManageCourseOfferingsAdminScreen> createState() => _ManageCourseOfferingsAdminScreenState();
}

class _ManageCourseOfferingsAdminScreenState extends State<ManageCourseOfferingsAdminScreen> {
  final _repo = CourseOfferingRepository();
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() { super.initState(); _load(); }

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
    setState(() => _busy = true);
    try {
      await _repo.approveOffering(offering);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _reject(Map<String, dynamic> offering) async {
    final course = offering['courses'] as Map<String, dynamic>? ?? {};
    final label = '${course['code'] ?? ''} · Section ${offering['section'] ?? ''}';
    final reasonCtrl = TextEditingController();
    final confirmed = await showGlassModal<bool>(context, builder: (sheetCtx) => Padding(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Decline $label?', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
          const SizedBox(height: 12),
          AfosTextField(hint: 'Reason (optional)', controller: reasonCtrl, maxLines: 2),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: TextButton(onPressed: () => Navigator.pop(sheetCtx, false), child: const Text('Cancel'))),
            Expanded(child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppColors.red),
                onPressed: () => Navigator.pop(sheetCtx, true), child: const Text('Decline'))),
          ]),
        ])));
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _repo.rejectOffering(
        offeringId: offering['id'] as String,
        teacherId: offering['teacher_id'] as String,
        courseLabel: label,
        reason: reasonCtrl.text.trim(),
      );
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busy = false);
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
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.amber, AppColors.orange]),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.06, curve: Curves.easeOutCubic),
        Expanded(child: _error != null ? _errorView(context) : _body(context)),
      ]),
    );
  }

  Widget _errorView(BuildContext context) => Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 40),
        const SizedBox(height: 12),
        Text('Couldn\'t load: $_error', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 12),
        TextButton(onPressed: _load, child: const Text('Retry')),
      ])));

  Widget _body(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_pending.isEmpty) {
      return const EmptyState(icon: Icons.menu_book_outlined,
          title: 'No pending offerings', subtitle: 'Teacher-submitted course offerings will appear here for review');
    }
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16 + GlassBottomNav.navContentClearance),
        itemCount: _pending.length,
        itemBuilder: (ctx, i) {
          final o = _pending[i];
          final course = o['courses'] as Map<String, dynamic>? ?? {};
          final teacher = o['profiles'] as Map<String, dynamic>? ?? {};
          final day = o['day_of_week'] as int?;
          final start = (o['start_time'] as String?)?.substring(0, 5) ?? '';
          final end = (o['end_time'] as String?)?.substring(0, 5) ?? '';
          return Container(
              margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${course['code'] ?? '—'} · ${course['title'] ?? ''}',
                    style: AppTextStyles.titleMedium.copyWith(color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text('by ${teacher['full_name'] ?? 'Teacher'} · ${o['department'] ?? ''}',
                    style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                Text('Batch ${o['batch']} · Section ${o['section']} · Sem ${o['semester']}',
                    style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                if (day != null && day >= 0 && day < 7)
                  Text('${_dayLabels[day]} $start–$end · ${o['building'] ?? ''} ${o['room_number'] ?? ''}',
                      style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: OutlinedButton(
                      onPressed: _busy ? null : () => _reject(o),
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
                      child: const Text('Decline'))),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(
                      onPressed: _busy ? null : () => _approve(o),
                      style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                      child: const Text('Approve'))),
                ]),
              ])).animate(delay: Duration(milliseconds: i * 60)).fadeIn().slideY(begin: 0.05);
        });
  }
}
