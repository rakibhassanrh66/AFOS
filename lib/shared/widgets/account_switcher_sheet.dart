import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase, SignOutScope;
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_text_styles.dart';
import '../../core/auth/biometric_lock.dart';
import 'empty_state.dart';
import 'glass_sheet.dart';

/// Switches the live Supabase session to a different remembered account —
/// signs the current one out, restores the target's stored session, and
/// marks it as last-active. `switchingAccounts` tells bootstrap.dart's
/// reactive sign-out listener to skip forgetting the departing account
/// (an intentional switch, not a logout).
Future<bool> switchToAccount(BuildContext context, RememberedAccount target) async {
  final ok = await BiometricAuth.authenticate(
      'Switch to ${target.fullName ?? target.email}');
  if (!ok) return false;
  try {
    BiometricTokenStore.switchingAccounts = true;
    if (Supabase.instance.client.auth.currentSession != null) {
      // LOCAL on purpose. This is a hand-off, not a logout: a global sign-out
      // revokes every refresh token this user holds, which would invalidate
      // the very session JSON BiometricTokenStore has saved for them and
      // break switching back to this account later.
      await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    }
    await Supabase.instance.client.auth.recoverSession(target.sessionJson);
    await BiometricTokenStore.setLastActive(target.userId);
    return true;
  } catch (_) {
    // Stored session no longer valid (revoked/expired) — no point keeping
    // a dead entry around for next time.
    await BiometricTokenStore.forget(target.userId);
    return false;
  } finally {
    BiometricTokenStore.switchingAccounts = false;
  }
}

/// Bottom sheet listing every remembered account (quick-login enabled on
/// this device), highlighting the current one, with a tap-to-switch action
/// on the rest plus "Forget" per account and an "Add another account" exit
/// to the login screen.
Future<void> showAccountSwitcherSheet(BuildContext context) async {
  final accounts = await BiometricTokenStore.listAccounts();
  final currentUid = Supabase.instance.client.auth.currentUser?.id;
  if (!context.mounted) return;
  await showGlassSheet(context, child: _AccountSwitcherBody(accounts: accounts, currentUid: currentUid));
}

class _AccountSwitcherBody extends StatefulWidget {
  final List<RememberedAccount> accounts;
  final String? currentUid;
  const _AccountSwitcherBody({required this.accounts, required this.currentUid});
  @override State<_AccountSwitcherBody> createState() => _AccountSwitcherBodyState();
}

class _AccountSwitcherBodyState extends State<_AccountSwitcherBody> {
  late List<RememberedAccount> _accounts = widget.accounts;
  bool _busy = false;

  Future<void> _tap(RememberedAccount a) async {
    if (a.userId == widget.currentUid || _busy) return;
    setState(() => _busy = true);
    final switched = await switchToAccount(context, a);
    if (!mounted) return;
    setState(() => _busy = false);
    if (switched) {
      Navigator.pop(context);
      context.go('/home');
    } else {
      setState(() => _accounts = _accounts.where((x) => x.userId != a.userId || a.userId == widget.currentUid).toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Couldn't switch — that account's saved session expired"), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _forget(RememberedAccount a) async {
    await BiometricTokenStore.forget(a.userId);
    if (mounted) setState(() => _accounts = _accounts.where((x) => x.userId != a.userId).toList());
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Switch Account', style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
        const SizedBox(height: 4),
        Text('Accounts with fingerprint / Face ID quick-login enabled on this device',
            style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
        const SizedBox(height: 16),
        if (_accounts.isEmpty)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12),
              child: EmptyState(icon: Icons.people_outline_rounded,
                  title: 'No remembered accounts', subtitle: 'Enable quick-login in Settings first'))
        else
          ..._accounts.map((a) {
            final isCurrent = a.userId == widget.currentUid;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isCurrent ? AppColors.blue.withValues(alpha: 0.1) : AppColors.surfaceOf(context),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _busy ? null : () => _tap(a),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: isCurrent ? AppColors.blue.withValues(alpha: 0.4) : AppColors.borderOf(context), width: 0.5)),
                    child: Row(children: [
                      CircleAvatar(radius: 20, backgroundColor: AppColors.blue.withValues(alpha: 0.15),
                          backgroundImage: (a.avatarUrl?.isNotEmpty ?? false) ? NetworkImage(a.avatarUrl!) : null,
                          child: (a.avatarUrl?.isNotEmpty ?? false) ? null
                              : Text((a.fullName?.isNotEmpty ?? false) ? a.fullName![0].toUpperCase() : a.email[0].toUpperCase(),
                                  style: const TextStyle(color: AppColors.blue, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.fullName?.isNotEmpty == true ? a.fullName! : a.email,
                            style: AppTextStyles.titleMedium.copyWith(color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(a.email, style: AppTextStyles.labelSmall.copyWith(color: textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ])),
                      if (isCurrent)
                        const Padding(padding: EdgeInsets.only(right: 4),
                            child: Text('Current', style: TextStyle(color: AppColors.green, fontSize: 11, fontWeight: FontWeight.w700)))
                      else
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          color: textSecondary,
                          tooltip: 'Forget this account',
                          onPressed: _busy ? null : () => _forget(a),
                        ),
                    ]),
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () { Navigator.pop(context); context.go('/auth/login'); },
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add another account'),
        ),
      ]),
    );
  }
}
