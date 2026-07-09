import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../bloc/shell_bloc.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/role_session.dart';

class AfosAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  const AfosAppBar({super.key, required this.title, this.actions});
  @override Size get preferredSize => const Size.fromHeight(60);

  bool get _isSuperAdmin => RoleSession.role == 'super_admin';

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    return AppBar(
      backgroundColor: AppColors.surfaceOf(context),
      elevation: 0,
      // Super admin gets a persistent, unmistakable visual signal across
      // every screen in the app (not just its own dedicated tools) — a
      // bolder solid violet underline plus a badge, rather than the thin
      // blended tri-color line every other role sees.
      bottom: PreferredSize(preferredSize: Size.fromHeight(_isSuperAdmin ? 2.5 : 1),
        child:Container(
          height: _isSuperAdmin ? 2.5 : 1,
          decoration: BoxDecoration(
            gradient: _isSuperAdmin
              ? LinearGradient(colors: [AppColors.holoviolet, AppColors.holoviolet.withValues(alpha: 0.4)])
              : LinearGradient(colors:[
                  AppColors.holoBlue.withOpacity(0.35),
                  AppColors.holoviolet.withOpacity(0.25),
                  AppColors.holoTeal.withOpacity(0.35),
                ]),
          ),
        )),
      leading: IconButton(
        icon: BlocBuilder<ShellBloc,ShellState>(
          builder:(_,state) => AnimatedSwitcher(
            duration:const Duration(milliseconds:200),
            switchInCurve: Curves.easeOutCubic,
            transitionBuilder: (child, anim) => RotationTransition(
              turns: Tween(begin: 0.75, end: 1.0).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            ),
            child:Icon(state.isOpen?Icons.close:Icons.menu_rounded,
              key:ValueKey(state.isOpen),color:textPrimary))),
        onPressed:()=>context.read<ShellBloc>().add(ToggleMenu()),
      ),
      title: Row(children: [
        Flexible(child: Text(title, style:AppTextStyles.headlineMed.copyWith(color: textPrimary), overflow: TextOverflow.ellipsis)),
        if (_isSuperAdmin) Padding(padding: const EdgeInsets.only(left: 8), child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.holoviolet, AppColors.holoviolet.withValues(alpha: 0.6)]),
                borderRadius: BorderRadius.circular(20)),
            child: const Text('SUPER ADMIN', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)))),
      ]),
      actions: [
        ...?actions,
        _NotificationBell(color: textPrimary),
        const SizedBox(width:8),
      ],
    );
  }
}

/// Unread-count badge on the bell icon — previously the icon gave zero
/// indication a new notification had arrived unless the user manually
/// opened the panel to check.
class _NotificationBell extends StatefulWidget {
  final Color color;
  const _NotificationBell({required this.color});
  @override State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  int _unread = 0;
  RealtimeChannel? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    final uid = SupabaseConfig.uid;
    // Unique per-instance channel name: AfosAppBar (and this bell) is
    // instantiated on nearly every screen, and go_router's nested navigator
    // keeps pushed-under screens' State alive rather than disposing them,
    // so multiple bells for the same user are routinely mounted at once.
    // supabase-dart dedupes channels by topic name, so a shared name meant
    // one instance's dispose()->unsubscribe() could tear the channel down
    // out from under the others. Filtering to this user's own rows also
    // matters once SOS alerts start bulk-inserting into this same table.
    _sub = SupabaseConfig.client
        .channel('notif_bell_${uid}_${identityHashCode(this)}')
        .onPostgresChanges(event: PostgresChangeEvent.all, schema: 'public',
            table: 'user_notifications',
            filter: uid == null ? null : PostgresChangeFilter(
                type: PostgresChangeFilterType.eq, column: 'user_id', value: uid),
            callback: (_) => _load())
        .subscribe();
  }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    try {
      final res = await SupabaseConfig.client.from('user_notifications')
          .select('id').eq('user_id', uid).eq('is_read', false) as List;
      if (mounted) setState(() => _unread = res.length);
    } catch (_) {}
  }

  @override
  void dispose() { _sub?.unsubscribe(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _unread > 0;
    return Stack(clipBehavior: Clip.none, children: [
      IconButton(
        icon: Container(width: 34, height: 34,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (hasUnread ? AppColors.holoBlue : widget.color).withValues(alpha: 0.1)),
            child: Icon(hasUnread ? AppIcons.notifications : Icons.notifications_none_rounded,
                color: hasUnread ? AppColors.holoBlue : widget.color, size: 19)),
        onPressed: () => context.push('/notifications'),
      ),
      if (hasUnread)
        Positioned(right: 6, top: 6, child: IgnorePointer(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle,
                border: Border.all(color: AppColors.surfaceOf(context), width: 1.5)),
            child: Text(_unread > 9 ? '9+' : '$_unread', textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)))
            .animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(end: 1.15, duration: 700.ms))),
    ]);
  }
}
