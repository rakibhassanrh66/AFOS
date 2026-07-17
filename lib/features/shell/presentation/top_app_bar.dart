import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../bloc/shell_bloc.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/services/web_title.dart';
import '../../notifications/presentation/notification_popover.dart';

class AfosAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  const AfosAppBar({super.key, required this.title, this.actions});
  @override Size get preferredSize => const Size.fromHeight(60);

  bool get _isSuperAdmin => RoleSession.role == 'super_admin';

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    // AfosAppBar must stay a bare PreferredSizeWidget (Scaffold.appBar
    // requires it), so it can't be wrapped in Flutter's Title widget the
    // usual way -- every screen already passes its own meaningful title
    // here, so this is the one place that already knows "what's actually
    // on screen" to drive the browser tab title with it. No-op on
    // Android/iOS (web_title_io.dart).
    setWebTitle('$title - AFOS');
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
                  AppColors.holoBlue.withValues(alpha:0.35),
                  AppColors.holoviolet.withValues(alpha:0.25),
                  AppColors.holoTeal.withValues(alpha:0.35),
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
        // Dismiss any open keyboard first -- opening the menu while a
        // TextField still holds focus (e.g. mid-search on Class Schedule)
        // raced the keyboard's close animation against the menu's slide-in,
        // producing a white, half-shifted frame. Confirmed live.
        onPressed:() { FocusScope.of(context).unfocus(); context.read<ShellBloc>().add(ToggleMenu()); },
      ),
      // A fixed-height row alone wasn't the fix -- AppBar's title slot itself
      // can be taller than that row and doesn't necessarily CENTER a shorter
      // child within it (it can top-align), which is exactly why the row sat
      // near the top of the bar with empty space below rather than centered
      // on "Dashboard". Center forces vertical centering within whatever
      // space AppBar actually hands the title, regardless of that slot's own
      // height or alignment behavior. The badge itself keeps its explicit
      // height so its own `alignment: center` stays unconditionally safe.
      title: Center(child: SizedBox(height: 34, child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Flexible(child: Text(title, style:AppTextStyles.headlineMed.copyWith(color: textPrimary), overflow: TextOverflow.ellipsis)),
        // Fixed height + Container alignment still left the text sitting
        // high with a gap below -- that's because only the descent side
        // (applyHeightToLastDescent) was trimmed from the text's line box;
        // the font's default ASCENT reservation above the actual cap-height
        // glyphs was still being centered as if it were real content,
        // pushing the visible ink up. Trimming both ascent and descent makes
        // the line box tightly hug the glyphs themselves, so plain symmetric
        // padding (no explicit height, no Container alignment needed at all)
        // centers the visible text correctly.
        if (_isSuperAdmin) Padding(padding: const EdgeInsets.only(left: 8), child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.holoviolet, AppColors.holoviolet.withValues(alpha: 0.6)]),
                borderRadius: BorderRadius.circular(20)),
            child: const Text('SUPER ADMIN',
                textHeightBehavior: TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                style: TextStyle(color: Colors.white, fontSize: 9, height: 1.0, fontWeight: FontWeight.w800, letterSpacing: 0.5)))),
      ]))),
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
  int _loadGen = 0;
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
    // Realtime fires one event per row change, so marking several
    // notifications read in quick succession (or one bulk "mark all
    // read") queues up several overlapping _load() calls. Their network
    // responses can resolve out of order -- an older call (queried before
    // a later update landed) finishing AFTER a newer, already-correct one
    // would overwrite the right count with a stale higher one, which read
    // as "the badge won't clear until I tap it 3-4 more times." This
    // generation guard only ever applies the result of the most recently
    // *issued* query.
    final gen = ++_loadGen;
    try {
      final res = await SupabaseConfig.client.from('user_notifications')
          .select('id').eq('user_id', uid).eq('is_read', false) as List;
      if (mounted && gen == _loadGen) setState(() => _unread = res.length);
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
        // The bell opens a compact floating tray on every platform; the
        // full-window Notification Center stays reachable via the slide
        // menu's Notifications entry (and the tray's "See all" footer).
        onPressed: () => showNotificationPopover(context),
      ),
      if (hasUnread)
        // alignment intentionally omitted -- a Positioned child that doesn't
        // pin both opposite edges (only right+top here) sizes itself loosely
        // rather than being stretched by the Stack, but that sizing still
        // interacts with Container's own bounded-constraints-plus-alignment
        // expand rule unpredictably; height:1.0 + textHeightBehavior below
        // centers the count text without touching how this Container sizes.
        Positioned(right: 6, top: 6, child: IgnorePointer(child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: BoxDecoration(color: AppColors.red, shape: BoxShape.circle,
                border: Border.all(color: AppColors.surfaceOf(context), width: 1.5)),
            child: Text(_unread > 9 ? '9+' : '$_unread', textAlign: TextAlign.center,
                textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                style: const TextStyle(color: Colors.white, fontSize: 9, height: 1.0, fontWeight: FontWeight.w700)))
            .animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(end: 1.15, duration: 700.ms))),
    ]);
  }
}
