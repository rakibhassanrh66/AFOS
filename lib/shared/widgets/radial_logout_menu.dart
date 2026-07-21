import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_icons.dart';

/// What the user picked in the leave dialog. `null` (a dismiss) means "stay
/// signed in" — the safe default, so tapping outside can never sign anyone out
/// by accident.
enum LogoutChoice { switchAccount, lock, signOut }

class _LeaveOption {
  final LogoutChoice choice;
  final String label;
  final String detail;
  final IconData icon;
  final Color color;
  const _LeaveOption(this.choice, this.label, this.detail, this.icon, this.color);
}

const List<_LeaveOption> _kOptions = [
  _LeaveOption(LogoutChoice.lock, 'Lock app',
      'Stay signed in, ask for fingerprint', AppIcons.lockOutline, AppColors.holoTeal),
  _LeaveOption(LogoutChoice.switchAccount, 'Switch account',
      'Sign out and go to login', Icons.swap_horiz_rounded, AppColors.holoBlue),
  _LeaveOption(LogoutChoice.signOut, 'Sign out',
      'End this session on this device', AppIcons.logout, AppColors.red),
];

/// The AFOS leave dialog.
///
/// Deliberately a plain, centred dialog in the same shape and language as the
/// app-exit confirmation in `app_shell.dart` — same rounded surface, same
/// "cancel is the safe default" behaviour. It replaced a radial burst menu that
/// fanned the options out on an arc from the tapped row: visually novel, but it
/// looked nothing like the rest of the app, needed a separate fallback path for
/// short screens and screen readers, and depended on the caller's render box
/// being laid out. This needs none of that and behaves identically everywhere.
///
/// [context] is only used for theming now; any context will do.
Future<LogoutChoice?> showRadialLogoutMenu(BuildContext context) {
  return showDialog<LogoutChoice>(
    context: context,
    builder: (dctx) => AlertDialog(
      backgroundColor: AppColors.surfaceOf(dctx),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 6),
      contentPadding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      title: Text('Leave AFOS?',
          style: TextStyle(
              color: AppColors.textPrimaryOf(dctx),
              fontSize: 19,
              fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final o in _kOptions)
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: o.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(o.icon, color: o.color, size: 19),
            ),
            title: Text(o.label,
                style: TextStyle(
                    color: AppColors.textPrimaryOf(dctx),
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
            subtitle: Text(o.detail,
                style: TextStyle(
                    color: AppColors.textSecondaryOf(dctx), fontSize: 12)),
            onTap: () => Navigator.pop(dctx, o.choice),
          ),
      ]),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dctx),
          child: Text('Stay',
              style: TextStyle(color: AppColors.textSecondaryOf(dctx))),
        ),
      ],
    ),
  );
}

/// Carries out the chosen leave action. Shared by the slide menu and Settings
/// so both entry points behave identically — the two stock dialogs this
/// replaced had already drifted apart in wording and context handling.
///
/// A `null` choice (dismiss / Back / "Stay") is a deliberate no-op: dismissing
/// must never sign anyone out.
Future<void> applyLogoutChoice(BuildContext context, LogoutChoice? choice) async {
  if (choice == null) return;
  if (choice == LogoutChoice.lock) {
    // The session stays valid on purpose. `/auth/unlock` is explicitly exempt
    // from the router's "logged in ⇒ bounce away from /auth/*" redirect
    // (app_router.dart) precisely so it can gate an already-valid session.
    context.go('/auth/unlock');
    return;
  }
  // Switch-account and sign-out both end the session: AFOS keeps no
  // multi-account store, so switching *is* signing out and returning to login
  // — the separate label only tells the user why they're going there.
  // The stored biometric session is cleared by bootstrap.dart's
  // AuthChangeEvent.signedOut listener, so it must NOT be cleared again here.
  await Supabase.instance.client.auth.signOut();
  if (context.mounted) context.go('/auth/login');
}
