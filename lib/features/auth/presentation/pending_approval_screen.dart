import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/role_session.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/supernova_loader.dart';

/// Shown to any account with profiles.is_verified = false — new signups
/// only (existing accounts were grandfathered to verified=true when this
/// gate was introduced). Streams the profile row so the moment a
/// super_admin approves the account, this screen auto-navigates to /home
/// without the user needing to restart or manually refresh.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});
  @override State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  RealtimeChannel? _sub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    _sub = SupabaseConfig.client.channel('pending_approval_$uid')
        .onPostgresChanges(
            event: PostgresChangeEvent.update, schema: 'public', table: 'profiles',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: uid),
            callback: (payload) {
              final isVerified = payload.newRecord['is_verified'] as bool? ?? false;
              if (isVerified) _approve();
            })
        .subscribe();
    // The channel only reports a CHANGE, so it never fires for someone
    // approved between registering and this screen ever mounting -- they
    // would otherwise wait here forever for an update that already happened.
    // It also silently misses an event on a channel that drops mid-wait
    // (killed connection, backgrounded app) with nothing to notice or
    // reconnect it. A direct check now, then every 15s, catches both without
    // depending on the realtime channel actually being healthy.
    _checkNow();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _checkNow());
  }

  Future<void> _checkNow() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    try {
      final row = await SupabaseConfig.client.from('profiles')
          .select('is_verified').eq('id', uid).maybeSingle();
      if ((row?['is_verified'] as bool?) ?? false) _approve();
    } catch (_) {
      // Offline or a transient error -- the next poll (or a live event, if
      // the channel is actually connected) will catch it. Nothing to show
      // for this: it isn't the user's account that's wrong, just this one
      // check, and the screen already explains what it's waiting for.
    }
  }

  void _approve() {
    if (!mounted) return;
    RoleSession.markVerified();
    context.go('/home');
  }

  @override
  void dispose() {
    _sub?.unsubscribe();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.global);
    if (mounted) context.go('/auth/login');
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      body: SafeArea(child: Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          glowColor: AppColors.gold,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SupernovaLoader(size: 48, color: AppColors.gold),
              const SizedBox(height: 24),
              Text('Waiting for approval', style: AppTextStyles.headlineLarge.copyWith(color: textPrimary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                'A super admin needs to verify your account before you can use AFOS. '
                'This page will move on automatically as soon as you\'re approved — '
                'no need to check back manually.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: textSecondary),
              ),
              const SizedBox(height: 28),
              TextButton(onPressed: _logout, child: const Text('Log out')),
            ]),
          ),
        ),
      ))),
    );
  }
}
