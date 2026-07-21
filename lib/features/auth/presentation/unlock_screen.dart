import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/biometric_lock.dart';
import '../../../core/utils/last_route.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/supernova_loader.dart';

/// The biometric lock screen shown on cold start when quick-login is enabled.
/// It gates access to an already-valid, on-device session: a passing biometric
/// check proceeds into the app; it never mints or validates a session itself.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});
  @override State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy) return;
    setState(() { _busy = true; _failed = false; });
    final ok = await BiometricAuth.authenticate('Unlock AFOS');
    if (!mounted) return;
    if (!ok) { setState(() { _busy = false; _failed = true; }); return; }

    // Biometric passed — ensure the session is live, restoring from the stored
    // JSON only if Supabase didn't already auto-restore it this launch.
    try {
      if (Supabase.instance.client.auth.currentSession == null) {
        final stored = await BiometricTokenStore.readSession();
        if (stored == null) { await _fallbackToPassword(); return; }
        await Supabase.instance.client.auth.recoverSession(stored);
      }
    } catch (_) {
      await _fallbackToPassword();
      return;
    }
    if (!mounted) return;
    final target = await loadLastRoute() ?? '/home';
    if (!mounted) return;
    context.go(target);
  }

  /// Give up on quick-login: clear the stored token and sign out to the normal
  /// password form.
  Future<void> _fallbackToPassword() async {
    await BiometricTokenStore.clear();
    try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
    if (mounted) context.go('/auth/login');
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: GlassCard(
                glowColor: AppColors.holoBlue,
                animated: true,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 96, height: 96,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [
                          AppColors.holoBlue.withValues(alpha: 0.22), Colors.transparent,
                        ]),
                        border: Border.all(color: AppColors.holoBlue.withValues(alpha: 0.4)),
                      ),
                      alignment: Alignment.center,
                      child: _busy
                          ? const SupernovaLoader(size: 44)
                          : const Icon(Icons.fingerprint_rounded, size: 52, color: AppColors.holoBlue)
                              .animate(onPlay: (c) => c.repeat(reverse: true))
                              .scaleXY(begin: 1.0, end: 1.08, duration: 1200.ms, curve: Curves.easeInOut),
                    ),
                    const SizedBox(height: 24),
                    Text('Unlock AFOS', style: AppTextStyles.displayMedium.copyWith(color: textPrimary)),
                    const SizedBox(height: 8),
                    Text(_failed
                        ? 'Authentication cancelled or failed. Try again, or use your password.'
                        : 'Confirm it’s you to continue.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                    const SizedBox(height: 28),
                    AfosButton(
                      label: _busy ? 'Unlocking…' : 'Unlock',
                      icon: Icons.fingerprint_rounded,
                      loading: _busy,
                      onTap: _unlock,
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _busy ? null : _fallbackToPassword,
                      child: Text('Use password instead',
                          style: TextStyle(color: textSecondary, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
