import 'package:flutter/material.dart';

import '../../../../config/supabase_config.dart';
import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../../core/utils/error_formatter.dart';
import '../../../../core/utils/role_labels.dart';
import '../../../notifications/data/repositories/notification_service.dart';
import '../../../../shared/widgets/glass_sheet.dart';
import 'user_card.dart';

/// Every per-user action Manage Users offers — delete, change role, appoint a
/// manager, delegate a permission — shared between the landing screen's
/// Pending queue and every per-role `UserDirectoryScreen` (Phase B), so the
/// two never drift into two different confirmation copies or two different
/// authorization stories for the same action.
///
/// Callers own their own list refresh: methods that change WHICH rows should
/// be visible (delete, role change) take an `onDone` callback instead of
/// reaching into a specific screen's reload method, since the landing screen
/// and a directory screen refresh differently.
mixin UserAdminActions<T extends StatefulWidget> on State<T> {
  /// Who holds which delegated areas, keyed by user id. RLS decides what
  /// lands here: a super_admin sees every grant, a manager sees only grants
  /// for areas they themselves hold.
  Map<String, Set<String>> grantsByUser = {};

  /// permission id of `permissions:delegate`. Null until the catalogue loads.
  String? delegatePermId;

  bool isManager(Map<String, dynamic> user) =>
      delegatePermId != null &&
      (grantsByUser[user['id']]?.contains(delegatePermId) ?? false);

  /// Areas a user can act in, NOT counting `permissions:delegate` itself.
  int areaCount(Map<String, dynamic> user) {
    final g = grantsByUser[user['id']];
    if (g == null) return 0;
    return g.where((id) => id != delegatePermId).length;
  }

  Future<void> loadGrants() async {
    try {
      final delegateRow = await SupabaseConfig.client
          .from('permissions').select('id')
          .eq('resource', 'permissions').eq('action', 'delegate').maybeSingle();
      final rows = await SupabaseConfig.client
          .from('user_permissions').select('user_id, permission_id') as List;
      final map = <String, Set<String>>{};
      for (final r in rows.cast<Map<String, dynamic>>()) {
        (map[r['user_id'] as String] ??= <String>{}).add(r['permission_id'] as String);
      }
      if (mounted) {
        setState(() {
          grantsByUser = map;
          delegatePermId = delegateRow?['id'] as String?;
        });
      }
    } catch (_) {
      // Deliberately silent: these are badges on a list that is otherwise
      // fine, and failing to decorate a row is not a reason to replace the
      // whole list with an error state.
    }
  }

  Future<bool> confirmAction(String title, String message, String confirmLabel) async {
    final confirm = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
              backgroundColor: AppColors.surfaceOf(dCtx),
              title: Text(title, style: TextStyle(color: AppColors.textPrimaryOf(dCtx))),
              content: Text(message, style: TextStyle(color: AppColors.textSecondaryOf(dCtx))),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(dCtx, true), child: Text(confirmLabel, style: const TextStyle(color: AppColors.red))),
              ],
            ));
    return confirm == true;
  }

  Future<void> deleteUser(Map<String, dynamic> user, {required VoidCallback onDone}) async {
    try {
      final res = await SupabaseConfig.client.functions.invoke('delete-user', body: {'targetUserId': user['id']});
      final data = res.data;
      if (data is Map && data['error'] != null) throw Exception(data['error']);
      if (mounted) {
        // Destructive and unrecoverable — the heaviest verb in the vocabulary.
        AppHaptics.warning();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user['full_name']} deleted'), backgroundColor: AppColors.green));
      }
      onDone();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> confirmDelete(Map<String, dynamic> user, {required VoidCallback onDone}) async {
    if (user['id'] == SupabaseConfig.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You cannot delete your own account'), backgroundColor: AppColors.red));
      return;
    }
    final confirm = await confirmAction('Delete ${user['full_name']} entirely?',
        'This removes the account and every row/photo/post tied to it, everywhere. This cannot be undone.',
        'Delete Everything');
    if (confirm) await deleteUser(user, onDone: onDone);
  }

  Future<void> rejectAndDelete(Map<String, dynamic> user, {required VoidCallback onDone}) async {
    final confirm = await confirmAction('Reject ${user['full_name']}?',
        'This permanently deletes the account so they can sign up again with the correct role.',
        'Reject & Delete');
    if (!confirm) return;
    await deleteUser(user, onDone: onDone);
  }

  // Roles a super-admin can assign. `all` is only a filter, not a role.
  static const assignableRoles = ['student', 'teacher', 'staff', 'admin', 'dept_admin', 'exam_controller', 'super_admin'];

  /// What a `roles:assign` holder may set, as opposed to a super_admin.
  ///
  /// This list is a MIRROR, not the rule. The rule is the `c_assignable`
  /// array in `protect_profile_privileged_columns`, which refuses anything
  /// else no matter what the client sends. Duplicating it here is what stops
  /// the picker offering "Super Admin" to someone who would then get a
  /// trigger exception quoting a Postgres array.
  static const delegateAssignableRoles = ['student', 'teacher', 'staff', 'exam_controller'];

  Future<String?> pickRole(String current, {required bool isSuperAdmin}) => showGlassModal<String>(context,
      builder: (sheetCtx) => SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Assign a role', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
          const SizedBox(height: 4),
          Text(
              isSuperAdmin
                  ? 'Takes effect immediately — access is enforced by the database (RLS).'
                  : 'Takes effect immediately, enforced by the database. Admin '
                    'and Super Admin are not on this list: those roles carry '
                    'authority over other people, so only a super-admin can '
                    'assign them.',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
          const SizedBox(height: 12),
          ...(isSuperAdmin ? assignableRoles : delegateAssignableRoles).map((r) {
            final sel = r == current;
            final c = UserCard.roleColors[r] ?? AppColors.textSecondary;
            return ListTile(
              dense: true,
              leading: Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: c, size: 20),
              title: Text(roleLabel(r), style: TextStyle(color: AppColors.textPrimaryOf(sheetCtx),
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
              trailing: sel ? Text('current', style: TextStyle(color: AppColors.textSecondaryOf(sheetCtx), fontSize: 11)) : null,
              onTap: () => Navigator.pop(sheetCtx, r),
            );
          }),
        ]),
      )));

  /// Super-admin (or a `roles:assign` holder, within the narrower list above)
  /// changes another user's role.
  Future<void> setRole(Map<String, dynamic> user, {required bool isSuperAdmin, required VoidCallback onDone}) async {
    if (user['id'] == SupabaseConfig.uid) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You can't change your own role"), backgroundColor: AppColors.red));
      return;
    }
    final current = user['role'] as String? ?? 'student';
    if (!isSuperAdmin && !delegateAssignableRoles.contains(current)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Only a super-admin can change the role of a '
              '${roleLabel(current)}.'),
          backgroundColor: AppColors.amber));
      return;
    }
    final picked = await pickRole(current, isSuperAdmin: isSuperAdmin);
    if (picked == null || picked == current || !mounted) return;
    final confirm = await confirmAction('Change role?',
        'Set ${user['full_name'] ?? 'this user'}\'s role to "$picked"? Their access changes immediately.',
        'Change role');
    if (!confirm) return;
    try {
      await SupabaseConfig.client.rpc('set_user_role', params: {
        'p_user_id': user['id'],
        'p_role': picked,
      });
      await NotificationService.sendToUsers(
        userIds: [user['id'] as String],
        title: 'Your role was updated',
        message: 'A super-admin set your AFOS account role to "$picked".',
        category: 'general',
      );
      if (mounted) {
        AppHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${user['full_name'] ?? 'User'} is now "$picked"'), backgroundColor: AppColors.green));
      }
      onDone();

      // STAFF STARTS WITH NOTHING, AND NOBODY WAS TOLD. `staff`'s menu is
      // built entirely from delegated grants, so setting someone to staff
      // and stopping there hands them home/transport/lost & found and no
      // job. Offer the second step immediately rather than leaving it to be
      // discovered.
      if (mounted && picked == 'staff') {
        await promptToAssignAreas(user, isSuperAdmin: isSuperAdmin, onDone: onDone);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  /// Offered immediately after a user is made `staff`. Not a snackbar: this
  /// is a step the admin has to take, and a message that disappears after
  /// four seconds is how the step got skipped in the first place.
  Future<void> promptToAssignAreas(Map<String, dynamic> user, {required bool isSuperAdmin, required VoidCallback onDone}) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(ctx),
        title: Text('Assign their work areas',
            style: TextStyle(color: AppColors.textPrimaryOf(ctx))),
        content: Text(
          'Staff accounts start with no admin tools at all. '
          '${user['full_name'] ?? 'This user'} cannot upload routines, manage '
          'a hall or publish notices until you grant those areas — the role on '
          'its own does nothing.',
          style: TextStyle(color: AppColors.textSecondaryOf(ctx)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('They need none',
                style: TextStyle(color: AppColors.textSecondaryOf(ctx))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.holoviolet),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Assign areas'),
          ),
        ],
      ),
    );
    if (go == true && mounted) await managePermissions(user, isSuperAdmin: isSuperAdmin, onDone: onDone);
  }

  /// Promote someone into — or out of — the management tier, in one action.
  /// Also does the second half nobody remembered: a manager may only pass on
  /// areas they themselves hold, so the area picker follows immediately when
  /// a brand-new manager holds nothing yet.
  Future<void> toggleManager(Map<String, dynamic> user, {required bool isSuperAdmin}) async {
    final permId = delegatePermId;
    if (permId == null) return;
    final name = user['full_name'] ?? 'This user';
    final wasManager = isManager(user);

    if (user['id'] == SupabaseConfig.uid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("You can't change your own management access"),
          backgroundColor: AppColors.red));
      return;
    }

    final areas = areaCount(user);
    final ok = await confirmAction(
      wasManager ? 'Remove management access?' : 'Make $name a manager?',
      wasManager
          ? '$name will keep their own work areas but can no longer give any '
            'of them to anyone else. Areas they already handed out stay in '
            'place — this stops them distributing more, it does not undo what '
            'they did.'
          : '$name will be able to give their own work areas to other people, '
            'and to take them back. They can never grant an area they do not '
            'hold themselves, so they cannot promote anyone above their own '
            'level — including themselves.'
            '${areas == 0 ? '\n\nThey hold no areas yet, so they would have '
                'nothing to give. Assign areas on the next screen.' : ''}',
      wasManager ? 'Remove access' : 'Make manager',
    );
    if (!ok) return;

    try {
      if (wasManager) {
        await SupabaseConfig.client.from('user_permissions').delete()
            .eq('user_id', user['id']).eq('permission_id', permId);
      } else {
        await SupabaseConfig.client.from('user_permissions').insert({
          'user_id': user['id'], 'permission_id': permId,
          'granted_by': SupabaseConfig.uid,
        });
      }
      await NotificationService.sendToUsers(
        userIds: [user['id'] as String],
        title: wasManager ? 'Management access removed' : 'You are now a manager',
        message: wasManager
            ? 'You can no longer assign your work areas to other people.'
            : 'You can now assign your own work areas to other people from '
              'Assign Work Areas.',
        category: 'general',
      );
      await loadGrants();
      if (!mounted) return;
      AppHaptics.success();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(wasManager
              ? '$name is no longer a manager'
              : '$name can now distribute their work areas'),
          backgroundColor: wasManager ? AppColors.amber : AppColors.green));

      if (!wasManager && areaCount(user) == 0) {
        await managePermissions(user, isSuperAdmin: isSuperAdmin, onDone: () {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  /// Grants ONE specific admin area to a user without changing their role.
  /// Writes to `user_permissions`, which `caller_can(resource, action)`
  /// already reads from at the RLS layer and `PermissionSession` reads
  /// client-side for the matching `/admin/*` router guards — a grant made
  /// here takes effect immediately end to end, not just as a UI checkbox.
  Future<void> managePermissions(Map<String, dynamic> user, {required bool isSuperAdmin, required VoidCallback onDone}) async {
    List<Map<String, dynamic>> catalog;
    Set<String> granted;
    try {
      final catalogRes = await SupabaseConfig.client
          .from('permissions').select('id, resource, action, scope')
          .order('resource').order('action') as List;
      catalog = catalogRes.cast<Map<String, dynamic>>();
      final grantedRes = await SupabaseConfig.client
          .from('user_permissions').select('permission_id')
          .eq('user_id', user['id']) as List;
      granted = grantedRes.map((r) => r['permission_id'] as String).toSet();

      // A DELEGATE MAY ONLY PASS ON WHAT THEY THEMSELVES HOLD. The database
      // enforces this (`delegate_grant_only_what_they_hold`) but a checkbox
      // the server will reject is a trap, so the catalogue a non-super_admin
      // sees is narrowed to their own grants up front.
      if (!isSuperAdmin) {
        final mineRes = await SupabaseConfig.client
            .from('user_permissions').select('permission_id')
            .eq('user_id', SupabaseConfig.uid!) as List;
        final mine = mineRes.map((r) => r['permission_id'] as String).toSet();
        catalog = catalog.where((p) =>
            mine.contains(p['id']) &&
            // ...except the one permission a manager holds but may not pass
            // on, or the tier could clone its own authority sideways.
            !(p['resource'] == 'permissions' && p['action'] == 'delegate')
        ).toList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
      return;
    }
    if (!mounted) return;
    final selected = Set<String>.of(granted);
    final saved = await showGlassModal<bool>(context,
        builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheetState) => SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 24),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Permissions for ${user['full_name'] ?? 'this user'}',
                      style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
                  const SizedBox(height: 4),
                  Text('Delegates ONE specific admin area without changing their role — '
                      'e.g. grant "transport: upload" so they can update bus routes without being made an admin. '
                      'Takes effect immediately, enforced by the database.',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
                  const SizedBox(height: 12),
                  for (final p in catalog)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.holoviolet,
                      value: selected.contains(p['id']),
                      onChanged: (v) => setSheetState(() {
                        if (v == true) {
                          selected.add(p['id'] as String);
                        } else {
                          selected.remove(p['id']);
                        }
                      }),
                      title: Text('${_titleCase(p['resource'] as String)}: ${p['action']}',
                          style: TextStyle(color: AppColors.textPrimaryOf(sheetCtx), fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text('scope: ${p['scope']}',
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.holoviolet),
                      onPressed: () => Navigator.pop(sheetCtx, true),
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Save permissions'))),
                ])))));
    if (saved != true || !mounted) return;

    final toGrant = selected.difference(granted);
    final toRevoke = granted.difference(selected);
    if (toGrant.isEmpty && toRevoke.isEmpty) return;
    try {
      if (toGrant.isNotEmpty) {
        await SupabaseConfig.client.from('user_permissions').insert([
          for (final id in toGrant) {'user_id': user['id'], 'permission_id': id, 'granted_by': SupabaseConfig.uid},
        ]);
      }
      if (toRevoke.isNotEmpty) {
        await SupabaseConfig.client.from('user_permissions').delete()
            .eq('user_id', user['id']).inFilter('permission_id', toRevoke.toList());
      }
      await NotificationService.sendToUsers(
        userIds: [user['id'] as String],
        title: 'Your permissions were updated',
        message: 'Your work areas in AFOS were changed. Open the menu to see '
            'what you can now access.',
        category: 'general',
      );
      // The badges on the list are now stale by exactly this change.
      await loadGrants();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Permissions updated for ${user['full_name'] ?? 'user'}'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';
}
