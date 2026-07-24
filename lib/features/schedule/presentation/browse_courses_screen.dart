import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_bottom_nav.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/course_offering_repository.dart';

const _dayLabels = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

Color _statusColor(String s) => switch (s) {
  'approved' => AppColors.green, 'rejected' => AppColors.red, _ => AppColors.amber,
};

/// Student-facing: browse teacher-declared, admin-approved course offerings
/// in their own department and request to join one (e.g. a retake or an
/// elective outside their default batch/section) — the offering's teacher
/// reviews each request before it's added to the student's schedule.
class BrowseCoursesScreen extends StatefulWidget {
  const BrowseCoursesScreen({super.key});
  @override State<BrowseCoursesScreen> createState() => _BrowseCoursesScreenState();
}

class _BrowseCoursesScreenState extends State<BrowseCoursesScreen> {
  final _repo = CourseOfferingRepository();
  List<Map<String, dynamic>> _offerings = [];
  Map<String, Map<String, dynamic>> _myEnrollmentsByOffering = {};
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = SupabaseConfig.uid;
      final profile = await SupabaseConfig.client.from('profiles')
          .select('department').eq('id', uid ?? '').maybeSingle();
      final department = profile?['department'] as String? ?? '';
      final results = await Future.wait([
        _repo.fetchJoinableOfferings(department),
        _repo.fetchMyEnrollments(),
      ]);
      final enrollments = results[1];
      final byOffering = <String, Map<String, dynamic>>{};
      for (final e in enrollments) {
        byOffering[e['offering_id'] as String] = e;
      }
      if (mounted) {
        setState(() {
          _offerings = results[0];
          _myEnrollmentsByOffering = byOffering;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _requestJoin(String offeringId) async {
    setState(() => _busy = true);
    try {
      await _repo.requestJoin(offeringId);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Requested — the teacher will review it ✓'), backgroundColor: AppColors.green));
      }
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
      appBar: const AfosAppBar(title: 'Browse Courses'),
      body: Column(children: [
        FeatureHeader(
          title: 'Browse Courses',
          subtitle: _loading ? 'Loading…' : '${_offerings.length} offerings in your department',
          icon: AppIcons.schedule,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.blueLight, AppColors.blue]),
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
    if (_offerings.isEmpty) {
      return const EmptyState(icon: Icons.menu_book_outlined,
          title: 'No offerings yet', subtitle: 'Course offerings your teachers declare will appear here once approved');
    }
    return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16 + GlassBottomNav.navContentClearance),
        itemCount: _offerings.length,
        // Guarded by the `if (_offerings.isEmpty) return EmptyState(...)`
        // early-return above, so .first is safe. The `day != null` check
        // below is defensive: course_offerings.day_of_week is nullable at
        // the DB level, but CourseOfferingRepository.createOffering (the
        // ONLY insert path into this table anywhere in the app) requires
        // dayOfWeek/startTime/endTime as non-nullable params, always
        // populated from the create form's day/time pickers — so every row
        // this app can ever produce already has them set, and this branch
        // never actually varies row height in practice.
        prototypeItem: _buildOfferingRow(context, _offerings.first, 0),
        itemBuilder: (ctx, i) => _buildOfferingRow(ctx, _offerings[i], i));
  }

  Widget _buildOfferingRow(BuildContext ctx, Map<String, dynamic> o, int i) {
    final textPrimary = AppColors.textPrimaryOf(ctx);
    final textSecondary = AppColors.textSecondaryOf(ctx);
    final course = o['courses'] as Map<String, dynamic>? ?? {};
    final teacher = o['profiles'] as Map<String, dynamic>? ?? {};
    final day = o['day_of_week'] as int?;
    final start = (o['start_time'] as String?)?.substring(0, 5) ?? '';
    final end = (o['end_time'] as String?)?.substring(0, 5) ?? '';
    final myRequest = _myEnrollmentsByOffering[o['id']];
    final status = myRequest?['status'] as String?;
    return Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surfaceOf(ctx), borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderOf(ctx), width: 0.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${course['code'] ?? '—'} · ${course['title'] ?? ''}',
              style: AppTextStyles.titleMedium.copyWith(color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text('Taught by ${teacher['full_name'] ?? 'Faculty'}',
              style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
          Text('Batch ${o['batch']} · Section ${o['section']}',
              style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
          if (day != null && day >= 0 && day < 7)
            Text('${_dayLabels[day]} $start–$end · ${o['building'] ?? ''} ${o['room_number'] ?? ''}',
                style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
          const SizedBox(height: 10),
          if (status == null)
            Align(alignment: Alignment.centerRight, child: FilledButton(
                onPressed: _busy ? null : () => _requestJoin(o['id'] as String),
                child: const Text('Request to Join')))
          else
            Align(alignment: Alignment.centerRight, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Text(status == 'pending' ? 'REQUEST PENDING' : status.toUpperCase(),
                    style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.w700)))),
        ])).animate(delay: Duration(milliseconds: i * 60)).fadeIn().slideY(begin: 0.05);
  }
}
