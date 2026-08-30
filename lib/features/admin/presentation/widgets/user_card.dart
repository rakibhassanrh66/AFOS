import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/depth.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/utils/role_labels.dart';
import '../../../../shared/widgets/glass_sheet.dart';

/// One row in a user list — the Pending queue, the Code-Failed queue, and
/// every per-role directory screen all share this, so approving, deleting or
/// re-assigning someone reads as one system no matter which list it happened
/// in. Promoted out of `manage_users_screen.dart` (Phase B) so
/// `UserDirectoryScreen` can use the exact same row and detail sheet instead
/// of a second copy that could drift.
class UserCard extends StatelessWidget {
  final Map<String, dynamic> user;
  final bool pending;
  final VoidCallback? onApprove, onReject, onDelete, onChangeRole, onManagePermissions, onToggleManager;

  /// Holds `permissions:delegate` — may hand their own areas to others.
  final bool isManager;

  /// Delegated areas held, excluding `permissions:delegate` itself.
  final int areaCount;

  const UserCard({
    super.key, required this.user, required this.pending,
    this.onApprove, this.onReject, this.onDelete, this.onChangeRole,
    this.onManagePermissions, this.onToggleManager,
    this.isManager = false, this.areaCount = 0,
  });

  /// Also used by `UserAdminActions.pickRole()` to colour the role picker
  /// identically to the row it was opened from.
  static const roleColors = {
    'super_admin': AppColors.holoviolet, 'admin': AppColors.holoBlue, 'dept_admin': AppColors.holoTeal,
    'teacher': AppColors.gold, 'staff': AppColors.amber, 'exam_controller': AppColors.orange, 'student': AppColors.textSecondary,
  };

  void _showDetails(BuildContext context) {
    final role = user['role'] as String? ?? 'student';
    final color = roleColors[role] ?? AppColors.textSecondary;
    final createdAt = user['created_at'] != null ? DateTime.tryParse(user['created_at'] as String) : null;
    String fmt(String? v) => (v == null || v.trim().isEmpty) ? 'Not provided' : v;
    final rows = <MapEntry<String, String>>[
      MapEntry('Full name', fmt(user['full_name'] as String?)),
      MapEntry('Email', fmt(user['email'] as String?)),
      MapEntry('Phone', fmt(user['phone'] as String?)),
      MapEntry('Role', roleLabel(role)),
      MapEntry('University ID', fmt(user['university_id'] as String?)),
      MapEntry('Department', fmt(user['department'] as String?)),
      if (role == 'student') MapEntry('Batch', fmt(user['batch'] as String?)),
      if (role == 'student') MapEntry('Section', fmt(user['section'] as String?)),
      if (role == 'teacher') MapEntry('Teacher initial', fmt(user['teacher_initial'] as String?)),
      MapEntry('Gender', fmt(user['gender'] as String?)),
      MapEntry('Emergency contact', fmt(user['emergency_contact'] as String?)),
      MapEntry('Joined', createdAt != null ? AppFormatters.relativeTime(createdAt) : 'Join date unavailable'),
      MapEntry('Approved', user['is_verified'] == true ? 'Yes' : 'Pending approval'),
    ];
    showGlassModal(context,
        builder: (sheetCtx) => SafeArea(
            child: SingleChildScrollView(
                // Sheet content — GlassSheet's SafeArea already applies it.
                padding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 24),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    CircleAvatar(radius: 24, backgroundColor: color.withValues(alpha: 0.15),
                        backgroundImage: (user['avatar_url'] as String?)?.isNotEmpty == true ? CachedNetworkImageProvider(user['avatar_url'], maxWidth: 128, maxHeight: 128) : null,
                        child: (user['avatar_url'] as String?)?.isNotEmpty != true
                            ? Text(((user['full_name'] as String?)?.isNotEmpty == true ? (user['full_name'] as String)[0] : '?').toUpperCase(),
                                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18))
                            : null),
                    const SizedBox(width: 14),
                    Expanded(child: Text(fmt(user['full_name'] as String?),
                        style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx)))),
                  ]),
                  const SizedBox(height: 20),
                  ...rows.map((r) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 130, child: Text(r.key,
                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(sheetCtx)))),
                        Expanded(child: Text(r.value,
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimaryOf(sheetCtx)))),
                      ]))),
                  if (onChangeRole != null) ...[
                    const SizedBox(height: 18),
                    SizedBox(width: double.infinity, child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.holoviolet),
                        onPressed: () { Navigator.pop(sheetCtx); onChangeRole!(); },
                        icon: const Icon(Icons.manage_accounts_rounded, size: 18),
                        label: const Text('Change role'))),
                  ],
                  if (onManagePermissions != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.holoviolet,
                            side: const BorderSide(color: AppColors.holoviolet)),
                        onPressed: () { Navigator.pop(sheetCtx); onManagePermissions!(); },
                        icon: const Icon(Icons.rule_rounded, size: 18),
                        label: Text(areaCount == 0
                            ? 'Assign work areas'
                            : 'Work areas ($areaCount assigned)'))),
                  ],
                  if (onToggleManager != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: isManager ? AppColors.amber : AppColors.holoTeal,
                            side: BorderSide(color: isManager ? AppColors.amber : AppColors.holoTeal)),
                        onPressed: () { Navigator.pop(sheetCtx); onToggleManager!(); },
                        icon: Icon(isManager
                            ? Icons.person_remove_alt_1_rounded
                            : Icons.supervisor_account_rounded, size: 18),
                        label: Text(isManager
                            ? 'Remove management access'
                            : 'Make a manager'))),
                    const SizedBox(height: 6),
                    Text(
                      isManager
                          ? 'They can pass their own work areas to other people. '
                            'They can never grant an area they do not hold.'
                          : 'A manager can hand their own work areas to other '
                            'people, and take them back — without becoming an admin.',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondaryOf(sheetCtx)),
                    ),
                  ],
                ]))));
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final role = user['role'] as String? ?? 'student';
    final color = roleColors[role] ?? AppColors.textSecondary;
    final createdAt = user['created_at'] != null ? DateTime.tryParse(user['created_at']) : null;
    return GestureDetector(
      onTap: () => _showDetails(context),
      child: Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(1),
          border: Border.all(color: pending ? AppColors.gold.withValues(alpha: 0.4) : AppColors.borderOf(context), width: pending ? 1 : 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 20, backgroundColor: color.withValues(alpha: 0.15),
              backgroundImage: (user['avatar_url'] as String?)?.isNotEmpty == true ? CachedNetworkImageProvider(user['avatar_url'], maxWidth: 128, maxHeight: 128) : null,
              child: (user['avatar_url'] as String?)?.isNotEmpty != true
                  ? Text(((user['full_name'] as String?)?.isNotEmpty == true ? (user['full_name'] as String)[0] : '?').toUpperCase(),
                      style: TextStyle(color: color, fontWeight: FontWeight.bold))
                  : null),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user['full_name'] ?? 'Unknown', style: AppTextStyles.titleMedium.copyWith(color: textPrimary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(user['email'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          if (onDelete != null && !pending)
            IconButton(icon: const Icon(Icons.delete_outline, color: AppColors.red, size: 20), onPressed: onDelete),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppDepth.radius(0)),
              child: Text(roleLabel(role), style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700))),
          // AUTHORITY THAT DOES NOT COME FROM THE ROLE.
          //
          // These two facts decide what this person can actually do, and
          // neither is visible in `role`: a `student` holding four areas has
          // more reach than a `staff` holding none. Without them the list
          // answers "what were they signed up as", not "what can they do".
          if (isManager) ...[
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.holoviolet.withValues(alpha: 0.14),
                    borderRadius: AppDepth.radius(0)),
                child: const Text('Manager',
                    style: TextStyle(color: AppColors.holoviolet, fontSize: 11, fontWeight: FontWeight.w700))),
          ],
          if (areaCount > 0) ...[
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.holoTeal.withValues(alpha: 0.14),
                    borderRadius: AppDepth.radius(0)),
                child: Text(areaCount == 1 ? '1 area' : '$areaCount areas',
                    style: const TextStyle(color: AppColors.holoTeal, fontSize: 11, fontWeight: FontWeight.w700))),
          ] else if (isManager) ...[
            // A manager with nothing to give. Worth calling out: they will
            // open the sheet to an empty list and conclude the app is broken.
            const SizedBox(width: 6),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.14),
                    borderRadius: AppDepth.radius(0)),
                child: const Text('no areas',
                    style: TextStyle(color: AppColors.amber, fontSize: 11, fontWeight: FontWeight.w700))),
          ],
          const SizedBox(width: 8),
          // Expanded, not Flexible-beside-a-Spacer. `Spacer` is an `Expanded`
          // with flex 1 and `Flexible` defaults to flex 1, so the two split the
          // free space 50/50: the department could only use HALF of what was
          // left before ellipsising, with an identical gap sitting next to it.
          // On a narrow phone that rendered a real department as "C…" beside
          // blank space. The Spacer is only needed when there is no department
          // to push "Joined" to the right.
          if ((user['department'] as String?)?.isNotEmpty == true)
            Expanded(child: Text(user['department'], style: TextStyle(color: textSecondary, fontSize: 11),
                maxLines: 1, overflow: TextOverflow.ellipsis))
          else
            const Spacer(),
          if (createdAt != null) ...[
            const SizedBox(width: 8),
            // Flexible + ellipsis: this is unbounded text at the end of a Row,
            // so at a large text scale it overflowed the card rather than
            // shortening.
            Flexible(
              child: Text('Joined ${AppFormatters.relativeTime(createdAt)}',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMutedOf(context), fontSize: 10)),
            ),
          ],
        ]),
        if (pending) ...[
          const SizedBox(height: 10),
          Row(children: [
            // A disabled Reject button would still say "you could do this if
            // you tried harder". Absent is the honest rendering for a
            // users:approve holder, whose job is the approving half.
            if (onReject != null) ...[
              Expanded(child: OutlinedButton(onPressed: onReject,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
                  child: const Text('Reject'))),
              const SizedBox(width: 8),
            ],
            Expanded(child: ElevatedButton(onPressed: onApprove,
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: Colors.white),
                child: const Text('Approve'))),
          ]),
        ],
      ]),
    ));
  }
}
