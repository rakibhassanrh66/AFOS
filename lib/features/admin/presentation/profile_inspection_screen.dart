import 'package:flutter/material.dart';

import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/auth/profile_completeness.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/role_labels.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../web/presentation/widgets/adaptive_list.dart';

/// The owner's ask, verbatim: a place for someone specifically tasked with
/// checking whether a profile is okay, that can nudge the one person who
/// still needs to fix it — rather than only reacting to submissions in the
/// Pending/Photos queues.
///
/// WHY THIS NEEDED ZERO BACKEND CHANGES. `admin_search_users`'s return shape
/// is explicitly frozen at 17 columns ("the screen reads these by name and
/// must not have to adapt" — 20260822112415) and does not carry
/// permanent_division/verified_at/avatar_review_status/admission_season/
/// designation/etc., all of which `incompleteReasons()` needs. Extending it
/// would be exactly the return-type change the constitution forbids. A DIRECT
/// `profiles` select was already the established alternative for this shape
/// of problem — `_loadManagement()` in user_directory_screen.dart does the
/// same thing — and the row policies already allow it: `admin_read_all`
/// (admin/teacher/dept_admin/super_admin) and `decision_holders_read_profiles`
/// (users:approve/roles:assign holders), both unrestricted by column
/// (20260816014500). So this reads `profiles` directly, exactly like that
/// screen already does, rather than inventing a new RPC.
///
/// Scoped to VERIFIED accounts only — an unverified signup already has its
/// own queue (Pending) and its own reason (the code, or a manual review); this
/// screen is specifically for someone who is IN the app and still missing
/// something `profile_is_complete()` requires.
class ProfileInspectionScreen extends StatefulWidget {
  const ProfileInspectionScreen({super.key});

  @override
  State<ProfileInspectionScreen> createState() => _ProfileInspectionScreenState();
}

class _ProfileInspectionScreenState extends State<ProfileInspectionScreen> {
  bool _loading = true;
  String? _error;
  List<(Map<String, dynamic> user, List<String> reasons)> _incomplete = [];
  final _notifying = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await SupabaseConfig.client
          .from('profiles')
          .select('id, full_name, email, phone, role, university_id, department, '
              'department_id, batch, section, semester, gender, emergency_contact, '
              'permanent_division, permanent_district, permanent_upazila, '
              'verified_at, avatar_review_status, admission_season, admission_year, '
              'joined_on, designation, is_verified, created_at')
          .eq('is_verified', true)
          .order('created_at', ascending: false)
          .limit(500) as List;

      final rows = res.cast<Map<String, dynamic>>();
      final flagged = <(Map<String, dynamic>, List<String>)>[];
      for (final row in rows) {
        final reasons = incompleteReasons(row);
        if (reasons.isNotEmpty) flagged.add((row, reasons));
      }
      if (mounted) setState(() { _incomplete = flagged; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _notify(Map<String, dynamic> user, List<String> reasons) async {
    final id = '${user['id']}';
    setState(() => _notifying.add(id));
    try {
      // Same mechanism the role-change/permission/CR-approval actions already
      // use (NotificationService.sendToUsers -> send-notification), already
      // permission-gated server-side for an admin-tier caller sending to an
      // arbitrary single recipient. No new backend needed here either.
      await NotificationService.sendToUsers(
        userIds: [id],
        title: 'Your AFOS profile needs attention',
        message: 'Please finish your profile: ${reasons.join(', ')}.',
        category: 'general',
        deepLink: '/complete-profile',
      );
      AppHaptics.success();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Notified ${user['full_name'] ?? 'this user'}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    } finally {
      if (mounted) setState(() => _notifying.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Profile Inspection'),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
            : _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : _incomplete.isEmpty
            ? const EmptyState(
                icon: Icons.fact_check_rounded,
                title: 'Everyone is complete',
                subtitle: 'Every verified account currently passes every '
                    'profile requirement.')
            : AdaptiveList(
                padding: EdgeInsetsDirectional.fromSTEB(16, 12, 16, 16 + NavInsets.of(context)),
                itemCount: _incomplete.length,
                itemBuilder: (context, i) {
                  final (user, reasons) = _incomplete[i];
                  final id = '${user['id']}';
                  return SurfaceCard(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${user['full_name'] ?? 'Unnamed'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.titleMedium
                                    .copyWith(color: AppColors.textPrimaryOf(context))),
                            const SizedBox(height: 2),
                            Text(
                              [
                                roleLabel('${user['role']}'),
                                if ('${user['university_id'] ?? ''}'.isNotEmpty)
                                  '${user['university_id']}',
                              ].join(' · '),
                              style: AppTextStyles.labelSmall
                                  .copyWith(color: AppColors.textSecondaryOf(context)),
                            ),
                          ]),
                        ),
                        Flexible(
                            child: PillBadge(label: '${reasons.length} missing', color: AppColors.amber)),
                      ]),
                      const SizedBox(height: AppSpace.sm),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final r in reasons)
                          Container(
                            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 4),
                            decoration: BoxDecoration(
                              color: AppColors.red.withValues(alpha: 0.1),
                              borderRadius: AppDepth.radius(0),
                            ),
                            child: Text(r,
                                style: AppTextStyles.labelSmall
                                    .copyWith(color: AppColors.red)),
                          ),
                      ]),
                      const SizedBox(height: AppSpace.sm),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: _notifying.contains(id) ? null : () => _notify(user, reasons),
                          icon: _notifying.contains(id)
                              ? const SizedBox(width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.notifications_active_rounded, size: 18),
                          label: Text(_notifying.contains(id) ? 'Notifying…' : 'Notify to finish profile'),
                        ),
                      ),
                    ]),
                  );
                },
              ),
      ),
    );
  }
}
