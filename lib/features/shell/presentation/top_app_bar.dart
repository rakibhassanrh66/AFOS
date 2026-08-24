import '../../../config/theme/depth.dart';
import '../../../config/theme/motion.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../bloc/shell_bloc.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../core/services/unread_counter.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/services/web_title.dart';
import '../../../core/utils/responsive.dart';
import '../../notifications/presentation/notification_popover.dart';
import '../../web/presentation/web_sidebar.dart';

/// The width `_WebPageHeader` should escape out to on desktop web: the true
/// browser window width minus the sidebar, ignoring app_shell.dart's 1440px
/// body-readability cap. Pure arithmetic, factored out of the widget so it's
/// unit-testable without pumping anything -- `_WebPageHeader` never builds
/// under a non-web `flutter test` run, since `kIsWeb` is a compile-time
/// constant.
double webHeaderOverflowWidth({required double windowWidth, required double railWidth}) {
  final width = windowWidth - railWidth;
  return width < 0 ? 0 : width;
}

class AfosAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  const AfosAppBar({super.key, required this.title, this.actions});

  /// 70 on mobile for the floating pill; 84 on a desktop browser for the page
  /// header that replaces it.
  ///
  /// This getter cannot read context, so it cannot ask how wide the window is.
  /// `kIsWeb` alone is the right test anyway: a narrow browser window still
  /// gets the desktop header, and the header is the better answer there too —
  /// what it must never do is appear in the Android build, and kIsWeb is a
  /// compile-time constant, so it does not.
  @override
  Size get preferredSize =>
      kIsWeb ? const Size.fromHeight(84) : const Size.fromHeight(70);

  bool get _isSuperAdmin => RoleSession.role == 'super_admin';

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);

    // ON THE WEB THIS IS NOT A PHONE TOOLBAR.
    //
    // The floating glass pill below is a phone component: a hamburger on the
    // left for a thumb, a centred title, a bell on the right. On a desktop
    // browser the sidebar is permanently visible, so the hamburger opens
    // nothing; and the pill's 54px height and pill radius sat above every page
    // as a second bar under the sidebar's own header — the "two stacked bars"
    // that made the web read as a resized phone app.
    //
    // The desktop header is a page title: large, left-aligned, sitting on the
    // page rather than floating over it, with the screen's own actions inline
    // where a mouse expects them. Same widget, same call sites — all 52
    // screens that already use AfosAppBar get this without being edited, which
    // is the only way a 62-screen sweep stays consistent.
    if (kIsWeb) {
      setWebTitle('$title - AFOS');
      return _WebPageHeader(
        title: title,
        actions: actions,
        isSuperAdmin: _isSuperAdmin,
      );
    }

    // AfosAppBar must stay a bare PreferredSizeWidget (Scaffold.appBar
    // requires it), so it can't be wrapped in Flutter's Title widget the
    // usual way -- every screen already passes its own meaningful title
    // here, so this is the one place that already knows "what's actually
    // on screen" to drive the browser tab title with it. No-op on
    // Android/iOS (web_title_io.dart).
    setWebTitle('$title - AFOS');
    // Super admin keeps its unmistakable signal as a solid violet rim on the
    // floating pill (replacing the old edge-to-edge underline).
    final borderColor = _isSuperAdmin ? AppColors.holoviolet : AppColors.glassBorder(context);
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      toolbarHeight: 70,
      // The bar is now a floating, rounded glass pill detached from the screen
      // edges — not an edge-to-edge Material bar.
      title: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 10),
        child: Container(
          height: 54,
          decoration: BoxDecoration(
            color: Color.alphaBlend(AppColors.glassFill(context), AppColors.surfaceOf(context)),
            borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
            border: Border.all(color: borderColor, width: _isSuperAdmin ? 1.5 : 1),
            boxShadow: [
              BoxShadow(
                color: (_isSuperAdmin ? AppColors.holoviolet : AppColors.holoBlue).withValues(alpha: 0.12),
                blurRadius: 18,
                spreadRadius: -4,
                offset: AppDepth.litOffset(6),
              ),
            ],
          ),
          child: Row(children: [
            const SizedBox(width: 4),
            IconButton(
              icon: BlocBuilder<ShellBloc,ShellState>(
                builder:(_,state) => AnimatedSwitcher(
                  duration: LiquidGlass.motionFast,
                  switchInCurve: LiquidGlass.motionCurve,
                  transitionBuilder: (child, anim) => RotationTransition(
                    turns: Tween(begin: 0.75, end: 1.0).animate(anim),
                    child: FadeTransition(opacity: anim, child: child),
                  ),
                  child:Icon(state.isOpen?Icons.close:Icons.menu_rounded,
                    key:ValueKey(state.isOpen),color:textPrimary))),
              // Dismiss any open keyboard first -- opening the menu while a
              // TextField still holds focus (e.g. mid-search on Class
              // Schedule) raced the keyboard's close animation against the
              // menu's slide-in, producing a white, half-shifted frame.
              onPressed:() { FocusScope.of(context).unfocus(); context.read<ShellBloc>().add(ToggleMenu()); },
            ),
            Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Flexible(child: Text(title, style:AppTextStyles.headlineMed.copyWith(color: textPrimary), overflow: TextOverflow.ellipsis)),
              if (_isSuperAdmin) Padding(padding: const EdgeInsetsDirectional.only(start: 8), child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [AppColors.holoviolet, AppColors.holoviolet.withValues(alpha: 0.6)]),
                      borderRadius: BorderRadius.circular(LiquidGlass.radiusPill)),
                  child: const Text('SUPER ADMIN',
                      textHeightBehavior: TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                      style: TextStyle(color: Colors.white, fontSize: 9, height: 1.0, fontWeight: FontWeight.w800, letterSpacing: 0.5)))),
            ])),
            ...?actions,
            _NotificationBell(color: textPrimary),
            const SizedBox(width: 6),
          ]),
        ),
      ),
    );
  }
}

/// The desktop replacement for the floating pill.
///
/// Deliberately NOT glass and NOT floating. The shell already owns one blurred
/// surface (the constitution's rule is that blur belongs to the shell and a
/// content surface does not add another), and a second translucent bar
/// hovering over every page was the single loudest reason the web build looked
/// like a phone app someone had resized.
///
/// What it is instead: a page title in the display role, left-aligned, with a
/// hairline under it separating chrome from content, and the screen's own
/// actions inline on the right where a mouse looks for them.
class _WebPageHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;
  final bool isSuperAdmin;

  const _WebPageHeader({
    required this.title,
    required this.actions,
    required this.isSuperAdmin,
  });

  @override
  Size get preferredSize => const Size.fromHeight(84);

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final header = Container(
      height: 84,
      padding: const EdgeInsetsDirectional.fromSTEB(24, 0, 16, 0),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(
          bottom: BorderSide(color: AppColors.borderOf(context), width: 0.5),
        ),
      ),
      child: Row(children: [
        Flexible(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.displayMedium.copyWith(
                  color: textPrimary, fontWeight: FontWeight.w700)),
        ),
        if (isSuperAdmin) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              // Flat fill, not the mobile pill's gradient: the constitution
              // bans symmetric two-stop gradients, and a badge this small has
              // nothing to gain from one.
              color: AppColors.holoviolet.withValues(alpha: 0.16),
              borderRadius: AppDepth.radius(0),
            ),
            child: const Text('SUPER ADMIN',
                textHeightBehavior: TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false),
                style: TextStyle(
                    color: AppColors.holoviolet,
                    fontSize: 10,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5)),
          ),
        ],
        const Spacer(),
        ...?actions,
        _NotificationBell(color: textPrimary),
        const SizedBox(width: 4),
      ]),
    );

    // app_shell.dart caps and centers the ENTIRE routed screen -- this
    // header included -- at 1440px on desktop web, for body-content
    // readability (see the comment there). That's the right call for a
    // scrollable list, but a page header/toolbar reads as web convention
    // (Gmail, most SaaS apps) only when it's flush against the real browser
    // edge, not centred with dead space beside it on a wide monitor.
    // OverflowBox escapes just THIS header back out to the true available
    // width -- window minus the sidebar -- without touching app_shell.dart's
    // cap for anything else. Left-aligned so the title stays exactly where
    // the 1440 column already put it; only the right side (actions/bell)
    // extends outward. Same desktop test app_shell.dart uses, so the two
    // never disagree about when this applies.
    final isDesktop = kIsWeb && Responsive.isExpanded(context);
    if (!isDesktop) return header;
    return OverflowBox(
      minWidth: 0,
      maxWidth: webHeaderOverflowWidth(
          windowWidth: MediaQuery.sizeOf(context).width,
          railWidth: WebSidebar.railWidth),
      alignment: Alignment.centerLeft,
      child: header,
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
  int _loadGen = 0;
  RealtimeChannel? _sub;
  // Anchors the popover to this bell via the compositing layer tree, not
  // BuildContext ancestry -- so it works regardless of which Navigator/Overlay
  // the bell itself lives inside (the bell is inside the ShellRoute's nested
  // navigator; the popover is inserted into the root Overlay). See
  // notification_popover.dart for why this replaced manual localToGlobal math.
  final LayerLink _bellLink = LayerLink();

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
      // HEAD count, not `select('id')` counted client-side. The bell sits in
      // the app bar of essentially every screen and reloads on every realtime
      // notification event, so this was the single most frequently issued
      // query in the app — and it transferred one uuid per unread row purely
      // to render a number. `.count()` sends no body at all.
      final unread = await SupabaseConfig.client.from('user_notifications')
          .count().eq('user_id', uid).eq('is_read', false);
      // Publish the authoritative count. This is what reconciles any
      // optimistic decrement the popover applied while this query was in
      // flight; the generation guard above already discards stale answers.
      if (mounted && gen == _loadGen) UnreadCounter.set(unread);
    } catch (_) {}
  }

  @override
  void dispose() { _sub?.unsubscribe(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    // Rebuilds the instant anything publishes a new count — including the
    // popover's optimistic decrement, which lands long before a query could
    // confirm it. Previously this read a field only `_load()` ever wrote, so
    // the number waited on a network round trip to change.
    return ValueListenableBuilder<int>(
      valueListenable: UnreadCounter.value,
      builder: (context, unread, __) => _buildBell(context, unread),
    );
  }

  Widget _buildBell(BuildContext context, int unread) {
    final hasUnread = unread > 0;
    return CompositedTransformTarget(
      link: _bellLink,
      child: Stack(clipBehavior: Clip.none, children: [
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
          onPressed: () => showNotificationPopover(context, link: _bellLink),
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
              child: Text(unread > 9 ? '9+' : '$unread', textAlign: TextAlign.center,
                  textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                  style: const TextStyle(color: Colors.white, fontSize: 9, height: 1.0, fontWeight: FontWeight.w700)))
              // The FIFTH perpetual animation found in this sweep, and the worst
              // placed: the unread badge pulses forever in the app bar, so it ran
              // on every screen in the app regardless of reduced motion. Under
              // reduced motion the badge is simply drawn at rest — it still says
              // the same thing, because the number is the information.
              .animate(
                  onPlay: (c) { if (!AppMotion.isReduced(context)) c.repeat(reverse: true); })
              .scaleXY(
                  end: AppMotion.isReduced(context) ? 1.0 : 1.15,
                  duration: AppMotion.durationOf(context, AppMotion.hero)))),
      ]),
    );
  }
}
