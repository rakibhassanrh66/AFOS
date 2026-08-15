import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/motion.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_chip.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/course_offering_repository.dart';
import 'course_group_screen.dart';
import 'widgets/offering_card.dart';
import '../../../core/layout/nav_insets.dart';

/// Student-facing: the courses running this term for their own batch and
/// section, with a fallback view of everything in the department (which is
/// how a retake or irregular student finds another section).
///
/// Seeing a course is automatic; joining is not — the student requests, and
/// the offering's teacher approves before it reaches their routine.
class BrowseCoursesScreen extends StatefulWidget {
  const BrowseCoursesScreen({super.key});
  @override
  State<BrowseCoursesScreen> createState() => _BrowseCoursesScreenState();
}

class _BrowseCoursesScreenState extends State<BrowseCoursesScreen> {
  final _repo = CourseOfferingRepository();
  List<Map<String, dynamic>> _offerings = [];
  Map<String, Map<String, dynamic>> _myEnrollmentsByOffering = {};
  Map<String, dynamic>? _term;
  String _department = '';
  String _batch = '';
  String _section = '';
  bool _loading = true;
  bool _showAllDepartment = false;
  String? _error;

  /// Per-row, so requesting one course doesn't disable every other button.
  final Set<String> _busyOfferings = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = SupabaseConfig.uid;
      final profile = await SupabaseConfig.client
          .from('profiles')
          .select('department, batch, section')
          .eq('id', uid ?? '')
          .maybeSingle();
      _department = profile?['department'] as String? ?? '';
      _batch = profile?['batch'] as String? ?? '';
      _section = profile?['section'] as String? ?? '';

      final results = await Future.wait([
        _repo.fetchJoinableOfferings(
          department: _department,
          batch: _batch,
          section: _section,
          allDepartmentCourses: _showAllDepartment,
        ),
        _repo.fetchMyEnrollments(),
        _repo.fetchActiveTerm().then((t) => t == null ? <Map<String, dynamic>>[] : [t]),
      ]);

      final byOffering = <String, Map<String, dynamic>>{};
      for (final e in results[1]) {
        byOffering[e['offering_id'] as String] = e;
      }
      if (mounted) {
        setState(() {
          _offerings = results[0];
          _myEnrollmentsByOffering = byOffering;
          _term = results[2].isEmpty ? null : results[2].first;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  bool get _canScopeToSection => _batch.isNotEmpty && _section.isNotEmpty;

  Future<void> _cancelRequest(String offeringId) async {
    final enrollmentId = _myEnrollmentsByOffering[offeringId]?['id'] as String?;
    if (enrollmentId == null) return;
    setState(() => _busyOfferings.add(offeringId));
    try {
      await _repo.withdrawJoinRequest(enrollmentId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Request cancelled'), backgroundColor: AppColors.amber));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busyOfferings.remove(offeringId));
  }

  Future<void> _requestJoin(String offeringId) async {
    setState(() => _busyOfferings.add(offeringId));
    try {
      await _repo.requestJoin(offeringId);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Requested — the teacher will review it'),
            backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _busyOfferings.remove(offeringId));
  }

  String get _subtitle {
    if (_loading) return 'Loading…';
    final term = _term?['name'] as String?;
    final scope = _showAllDepartment || !_canScopeToSection
        ? 'all $_department courses'
        : 'Batch $_batch · Section $_section';
    return '${_offerings.length} ${_offerings.length == 1 ? 'course' : 'courses'} · $scope'
        '${term == null ? '' : ' · $term'}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'My Courses'),
      body: Column(children: [
        FeatureHeader(
          title: 'My Courses',
          subtitle: _subtitle,
          icon: AppIcons.schedule,
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.blueLight, AppColors.blue]),
          margin: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
        )
            .animate()
            .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
            .slideY(begin: -0.06, curve: AppMotion.standard),
        if (_canScopeToSection)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
            child: Row(children: [
              Expanded(
                child: GlassChip(
                  label: 'My section',
                  selected: !_showAllDepartment,
                  expand: true,
                  onTap: _showAllDepartment
                      ? () {
                          setState(() => _showAllDepartment = false);
                          _load();
                        }
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlassChip(
                  label: 'All $_department',
                  selected: _showAllDepartment,
                  expand: true,
                  onTap: _showAllDepartment
                      ? null
                      : () {
                          setState(() => _showAllDepartment = true);
                          _load();
                        },
                ),
              ),
            ]),
          ),
        Expanded(
          child: _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : RefreshIndicator(onRefresh: _load, child: _body(context)),
        ),
      ]),
    );
  }

  /// The student's own requests and enrolments whose offering is NOT in the
  /// browsable list — because it was archived, or because it belongs to a
  /// batch/section the current filter excludes.
  ///
  /// Without this they simply vanish. A student who asked to join a course, or
  /// was already enrolled in one, saw it disappear from this screen with no
  /// row, no status and no explanation the moment the teacher ended it — while
  /// the enrolment still existed and still carried their marks. The teacher has
  /// an "Ended" section for exactly this reason; the student had nothing.
  List<Map<String, dynamic>> get _offListEnrollments {
    final shown = _offerings.map((o) => o['id'] as String).toSet();
    final out = <Map<String, dynamic>>[];
    for (final e in _myEnrollmentsByOffering.values) {
      final id = e['offering_id'] as String?;
      if (id == null || shown.contains(id)) continue;
      if (e['course_offerings'] is Map<String, dynamic>) out.add(e);
    }
    return out;
  }

  Widget _body(BuildContext context) {
    if (_loading) return const OfferingCardSkeleton();
    final elsewhere = _offListEnrollments;

    if (_offerings.isEmpty && elsewhere.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 40),
        EmptyState(
          icon: Icons.menu_book_outlined,
          title: _showAllDepartment ? 'Nothing running yet' : 'No courses for your section',
          subtitle: _showAllDepartment
              ? 'Courses your teachers declare will appear here once an admin approves them'
              : 'Nothing is running for Batch $_batch Section $_section yet — try "All $_department"',
        ),
      ]);
    }
    return ListView.builder(
      padding: NavInsets.content(context, top: 0),
      itemCount: _offerings.length + (elsewhere.isEmpty ? 0 : elsewhere.length + 1),
      itemBuilder: (ctx, rawIndex) {
        if (rawIndex >= _offerings.length) {
          final ai = rawIndex - _offerings.length;
          if (ai == 0) return UnlistedEnrollmentsHeader(count: elsewhere.length);
          return UnlistedEnrollmentRow(enrollment: elsewhere[ai - 1]);
        }
        final o = _offerings[rawIndex];
        final id = o['id'] as String;
        final status = _myEnrollmentsByOffering[id]?['status'] as String?;
        return OfferingCard(
          offering: o,
          index: rawIndex,
          onTap: status == 'approved'
              ? () => Navigator.of(ctx).push(MaterialPageRoute(
                    builder: (_) => CourseGroupScreen(offering: o),
                  ))
              : null,
          trailing: _actionFor(id, status),
        );
      },
    );
  }

  Widget _actionFor(String offeringId, String? status) {
    if (status == null) {
      final busy = _busyOfferings.contains(offeringId);
      return FilledButton(
        onPressed: busy ? null : () => _requestJoin(offeringId),
        child: busy
            ? const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Text('Request to Join'),
      );
    }
    if (status == 'approved') {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const PillBadge(label: 'ENROLLED', color: AppColors.green),
        const SizedBox(width: 8),
        Icon(Icons.forum_outlined, size: 16, color: AppColors.textSecondaryOf(context)),
      ]);
    }
    if (status == 'pending') {
      // Was a dead 'REQUEST PENDING' badge with nothing to press. A request
      // sent to the wrong section sat in the teacher's queue forever and the
      // student had no way to take it back — there was no DELETE policy on
      // enrollments at all, so the missing button was the symptom, not the
      // cause. Cancelling is allowed only while it is still undecided.
      final busy = _busyOfferings.contains(offeringId);
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const PillBadge(label: 'PENDING', color: AppColors.amber),
        const SizedBox(width: 6),
        TextButton(
          onPressed: busy ? null : () => _cancelRequest(offeringId),
          style: TextButton.styleFrom(
              foregroundColor: AppColors.red,
              visualDensity: VisualDensity.compact),
          child: busy
              ? const SizedBox(
                  width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Cancel'),
        ),
      ]);
    }
    return PillBadge(
      label: status.toUpperCase(),
      color: offeringStatusColor(status),
    );
  }
}

/// Separates the browsable courses from the student's own history.
class UnlistedEnrollmentsHeader extends StatelessWidget {
  final int count;
  const UnlistedEnrollmentsHeader({super.key, required this.count});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.history_rounded,
                size: 16, color: AppColors.textSecondaryOf(context)),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Not in this list ($count)',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.textPrimaryOf(context))),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
              'Courses you asked to join or were enrolled in that are no longer '
              'shown above — usually because the teacher ended them.',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textSecondaryOf(context))),
        ]),
      );
}

/// One such enrolment, stating plainly what happened to it.
class UnlistedEnrollmentRow extends StatelessWidget {
  final Map<String, dynamic> enrollment;
  const UnlistedEnrollmentRow({super.key, required this.enrollment});

  @override
  Widget build(BuildContext context) {
    final offering = enrollment['course_offerings'] as Map<String, dynamic>? ?? const {};
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final status = enrollment['status'] as String? ?? 'pending';
    final archived = offering['is_archived'] == true;
    final dim = AppTextStyles.labelSmall
        .copyWith(color: AppColors.textSecondaryOf(context));

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        border: Border.all(color: AppColors.borderOf(context), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Badge under the title. Beside it, the status pill is laid out first
        // at its full width and leaves the Expanded the remainder, which on a
        // narrow phone at a large text scale is not enough for a course code
        // plus a title — the same starve fixed on the Teaching Load and
        // Allocation cards, and the reason those needed fixing twice.
        Text('${course['code'] ?? '—'} — ${course['title'] ?? ''}',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium
                .copyWith(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: PillBadge(
              label: status.toUpperCase(),
              color: offeringStatusColor(status),
              maxWidth: double.infinity),
        ),
        const SizedBox(height: 3),
        Text(
            'Batch ${offering['batch'] ?? '—'} · Section ${offering['section'] ?? '—'}',
            maxLines: 1, overflow: TextOverflow.ellipsis, style: dim),
        const SizedBox(height: 6),
        Text(
          archived
              ? (status == 'approved'
                  ? 'This course has ended. Your enrolment and your marks are kept.'
                  : 'This course ended before your request was decided, so it can no longer be accepted.')
              : 'This course is not shown for your current batch and section filter.',
          maxLines: 3, overflow: TextOverflow.ellipsis,
          style: dim.copyWith(color: archived ? AppColors.amber : null),
        ),
      ]),
    );
  }
}
