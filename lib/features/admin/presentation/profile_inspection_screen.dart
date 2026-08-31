import 'package:flutter/material.dart';

import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/button_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/auth/profile_completeness.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/role_labels.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../web/presentation/widgets/adaptive_list.dart';
import 'widgets/user_admin_actions_mixin.dart';

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

class _ProfileInspectionScreenState extends State<ProfileInspectionScreen>
    with UserAdminActions<ProfileInspectionScreen> {
  bool _loading = true;
  String? _error;

  /// Reject & delete is offered to a super_admin only — the same gate the
  /// per-role directory applies to the identical action. The `delete-user`
  /// edge function decides for real, but a button the server will refuse is a
  /// trap, so the UI does not offer one.
  bool _isSuperAdmin = false;
  List<(Map<String, dynamic> user, List<String> reasons)> _incomplete = [];
  final _notifying = <String>{};

  /// user id -> when this person was last nudged about their profile.
  ///
  /// Comes from `admin_profile_nudge_status()`, NOT from a direct read of
  /// `user_notifications`: that table's only SELECT policy is
  /// `auth.uid() = user_id`, so a client asking about anyone else gets zero
  /// rows SILENTLY — which would have rendered as "nobody has ever been
  /// notified" on every card rather than as an error.
  Map<String, DateTime> _notifiedAt = const {};

  @override
  void initState() {
    super.initState();
    _load();
    _loadViewerRole();
  }

  Future<void> _loadViewerRole() async {
    final role = await RoleSession.ensureLoaded();
    if (mounted) setState(() => _isSuperAdmin = role == 'super_admin');
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
              'joined_on, is_verified, created_at, '
              // `designation` is NOT selected here, and must never be added
              // back: there is no `profiles.designation` column. Verified
              // against information_schema on 2026-08-31 — asking for it
              // makes PostgREST reject the WHOLE select with 42703
              // ("column profiles.designation does not exist"), so this
              // screen rendered its error state on every single open rather
              // than listing anyone. It was named here on the belief, written
              // into this repo's own notes, that the column "exists but is
              // never populated" for teacher/staff. It does not exist at all.
              //
              // The designation genuinely lives on the linked teachers/staff
              // row (which is where profile_is_complete() checks it too), so
              // these two embeds are the real source, and
              // resolvedDesignation() below reads them. Note the dashboard's
              // ring never hit this because it selects `*` plus the same
              // embeds — `*` cannot name a column that is not there.
              'teachers(designation), staff(designation)')
          .eq('is_verified', true)
          .order('created_at', ascending: false)
          .limit(500) as List;

      final rows = res.cast<Map<String, dynamic>>();
      final flagged = <(Map<String, dynamic>, List<String>)>[];
      for (final row in rows) {
        row['designation'] = resolvedDesignation(row);
        final reasons = incompleteReasons(row);
        if (reasons.isNotEmpty) flagged.add((row, reasons));
      }
      if (mounted) setState(() { _incomplete = flagged; _loading = false; });
      await _loadNudgeStatus(flagged.map((f) => '${f.$1['id']}').toList());
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  /// Who on this list has already been chased, and when.
  ///
  /// Deliberately AFTER the list is on screen and in its own try/catch: this
  /// decorates the cards, and losing it must not turn a working list into an
  /// error page. A card with no timestamp simply shows "Not notified yet",
  /// which is also what it shows when the answer is genuinely no.
  Future<void> _loadNudgeStatus(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      final res = await SupabaseConfig.client
          .rpc('admin_profile_nudge_status', params: {'p_user_ids': ids});
      final map = <String, DateTime>{};
      (res as Map?)?.forEach((k, v) {
        final at = DateTime.tryParse('$v');
        if (at != null) map['$k'] = at.toLocal();
      });
      if (mounted) setState(() => _notifiedAt = map);
    } catch (_) {
      // Left empty on purpose — see above.
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
        // Recorded straight away rather than re-fetching: the row is already
        // written, and the card should stop saying "Not notified yet" the
        // instant the send succeeds.
        setState(() => _notifiedAt = {..._notifiedAt, id: DateTime.now()});
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
                      // Whether this person has already been chased. Without
                      // it an admin working down the list cannot tell who has
                      // been contacted and who has never heard anything, and
                      // ends up notifying the same people repeatedly.
                      Row(children: [
                        Icon(
                            _notifiedAt.containsKey(id)
                                ? Icons.mark_email_read_outlined
                                : Icons.mark_email_unread_outlined,
                            size: 14,
                            color: _notifiedAt.containsKey(id)
                                ? AppColors.green
                                : AppColors.textSecondaryOf(context)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              _notifiedAt.containsKey(id)
                                  ? 'Notified ${AppFormatters.relativeTime(_notifiedAt[id]!)}'
                                  : 'Not notified yet',
                              style: AppTextStyles.labelSmall.copyWith(
                                  color: _notifiedAt.containsKey(id)
                                      ? AppColors.green
                                      : AppColors.textSecondaryOf(context))),
                        ),
                      ]),
                      const SizedBox(height: AppSpace.xs),
                      // Wrap, not Row: two buttons plus a long label do not sit
                      // side by side on a 320dp phone at a large text scale,
                      // and a Row answers that by clipping the last one off the
                      // edge — the same reason SelectionBar uses one.
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: AppSpace.sm,
                        children: [
                        if (_isSuperAdmin)
                          TextButton.icon(
                            style: rowAction(TextButton.styleFrom(
                                foregroundColor: AppColors.red)),
                            // Reuses the shared mixin's action, so this screen
                            // cannot drift into a second confirmation copy or
                            // a second authorization story for the same verb.
                            // Its dialog already explains the re-apply path:
                            // the account is deleted so they can sign up again.
                            onPressed: () => rejectAndDelete(user, onDone: _load),
                            icon: const Icon(Icons.person_remove_outlined, size: 18),
                            label: const Text('Reject & delete'),
                          ),
                        TextButton.icon(
                          style: rowAction(),
                          onPressed: _notifying.contains(id) ? null : () => _notify(user, reasons),
                          icon: _notifying.contains(id)
                              ? const SizedBox(width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.notifications_active_rounded, size: 18),
                          label: Text(_notifying.contains(id)
                              ? 'Notifying…'
                              : _notifiedAt.containsKey(id)
                                  // Says plainly that this is a REPEAT nudge,
                                  // so sending one is a decision rather than
                                  // something done by accident to someone who
                                  // was already chased an hour ago.
                                  ? 'Notify again'
                                  : 'Notify to finish profile'),
                        ),
                      ]),
                    ]),
                  );
                },
              ),
      ),
    );
  }
}
