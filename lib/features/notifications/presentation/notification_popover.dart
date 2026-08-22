import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/supabase_config.dart';
import '../../../core/services/unread_counter.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/liquid_glass_theme.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';

import '../../../core/layout/nav_insets.dart';
/// Compact floating notification panel, anchored under the app-bar bell.
///
/// The bell deliberately does NOT navigate to the full-screen center any
/// more: tapping the bell should feel like peeking at a small scrollable
/// tray (identical behavior on web, Android, and iOS), while the
/// "Notifications" entry in the slide menu remains the full-window view.
Future<void> showNotificationPopover(BuildContext context) {
  final reduceMotion = MediaQuery.of(context).disableAnimations;

  // WHERE THE BELL ACTUALLY IS, measured from the button's own box.
  //
  // This used to be a hardcoded `Alignment.topRight` with `top: 64, end: 12`,
  // which is only correct when the bell is at the top-right of the SCREEN --
  // true on a phone, false on the web. There the bell sits at the right edge
  // of the page header inside a content area that starts after a 248px
  // sidebar, so at 1440px the bell was at x=1065 while the tray was pinned to
  // x=1428: the panel hung 360px to the right of the thing that opened it,
  // with the bell at its far top-left corner rather than above it.
  //
  // `context` here is the IconButton's own context (see top_app_bar.dart), so
  // the anchor needs no new parameter and no GlobalKey.
  // GLOBAL coordinates, with no `ancestor:`. Measuring against the enclosing
  // Overlay was wrong and moved the panel the other way by ~260px: on web that
  // overlay begins after the 248px sidebar, so the rect came back in the
  // content area's space while `MediaQuery.size` below is the whole window.
  // Two coordinate spaces, one subtraction, panel in the wrong place again.
  // showGeneralDialog uses the ROOT navigator, so the dialog is laid out in
  // full-screen space and the anchor has to be measured the same way.
  final box = context.findRenderObject() as RenderBox?;
  Rect? anchor;
  if (box != null && box.hasSize) {
    anchor = box.localToGlobal(Offset.zero) & box.size;
  }

  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss notifications',
    barrierColor: Colors.black.withValues(alpha: 0.25),
    transitionDuration:
        reduceMotion ? Duration.zero : LiquidGlass.entranceDuration,
    pageBuilder: (dialogCtx, _, __) {
      final size = MediaQuery.of(dialogCtx).size;
      final width = size.width < 420 ? size.width - 24.0 : 380.0;
      final maxHeight =
          (size.height * 0.66).clamp(280.0, 520.0).toDouble();

      // Right edge of the panel lines up with the right edge of the bell, so
      // the tray hangs directly beneath it. Falls back to the old constants
      // when the anchor cannot be measured, which is what a test with no
      // overlay sees.
      var top = 64.0;
      var right = 12.0;
      if (anchor != null) {
        top = anchor.bottom + 8;
        // Never let it run off either edge: 12px minimum gutter on the right,
        // and never so far right that the panel's left edge leaves the screen.
        final maxRight = size.width - width - 12;
        right = size.width - anchor.right;
        right = maxRight < 12 ? 12.0 : right.clamp(12.0, maxRight).toDouble();
      }

      return SafeArea(
        child: Stack(children: [
          Positioned(
            top: top,
            right: right,
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: const _NotificationPopover(),
            ),
          ),
        ]),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOut);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: LiquidGlass.entranceScaleFrom, end: 1)
              .animate(curved),
          alignment: Alignment.topRight,
          child: child,
        ),
      );
    },
  );
}

class _NotificationPopover extends StatefulWidget {
  const _NotificationPopover();
  @override
  State<_NotificationPopover> createState() => _NotificationPopoverState();
}

class _NotificationPopoverState extends State<_NotificationPopover> {
  List<Map<String, dynamic>> _notifs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final res = await SupabaseConfig.client
          .from('user_notifications')
          .select()
          .eq('user_id', uid)
          .order('received_at', ascending: false)
          .limit(20) as List;
      if (mounted) setState(() { _notifs = res.cast(); _error = null; });
    } catch (e) {
      // Silent failure looked identical to "all caught up".
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _markAllRead() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    setState(() {
      _notifs = [for (final n in _notifs) {...n, 'is_read': true}];
    });
    // Tell the bell now, not after the round trip. This list already updates
    // itself instantly; the badge six pixels away used to wait for a realtime
    // event plus a fresh count, which is what made the tap feel ignored.
    UnreadCounter.clear();
    try {
      await SupabaseConfig.client
          .from('user_notifications')
          .update({'is_read': true}).eq('user_id', uid);
    } catch (_) {}
  }

  Future<void> _onTap(Map<String, dynamic> n) async {
    final id = n['id'] as String;
    final wasUnread = !(n['is_read'] as bool? ?? false);
    setState(() {
      final idx = _notifs.indexWhere((e) => e['id'] == id);
      if (idx >= 0) _notifs[idx] = {..._notifs[idx], 'is_read': true};
    });
    // Only if it was actually unread — re-tapping an already-read row must
    // not drive the badge below the truth.
    if (wasUnread) UnreadCounter.decrement();
    try {
      await SupabaseConfig.client
          .from('user_notifications')
          .update({'is_read': true}).eq('id', id);
    } catch (_) {}
    if (!mounted) return;
    final route = n['deep_link_route'] as String?;
    Navigator.of(context).pop();
    if (route != null && route.isNotEmpty) {
      // ignore: use_build_context_synchronously
      GoRouter.of(context).push(route);
    }
  }

  // Kept in sync with NotificationCenterScreen's category visuals.
  static IconData _catIcon(String? cat) => switch (cat) {
        'schedule' => AppIcons.schedule,
        'transport' => AppIcons.transport,
        'payment' => AppIcons.payment,
        'library' => AppIcons.library,
        'lost_found' => AppIcons.lostFound,
        'club' => AppIcons.clubs,
        'message' => AppIcons.deptChat,
        'exam' => AppIcons.examSeat,
        _ => AppIcons.notifications,
      };

  static Color _catColor(String? cat) => switch (cat) {
        'schedule' => AppColors.red,
        'transport' => AppColors.amber,
        'payment' => AppColors.gold,
        'library' => AppColors.indigo,
        'lost_found' => AppColors.coral,
        'club' => AppColors.pink,
        'message' => AppColors.blue,
        'exam' => AppColors.orange,
        _ => AppColors.blue,
      };

  @override
  Widget build(BuildContext context) {
    final glass = LiquidGlassTheme.of(context);
    final unread =
        _notifs.where((n) => !(n['is_read'] as bool? ?? false)).length;
    return Material(
      color: Colors.transparent,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          // Near-opaque canvas blend: the popover floats over arbitrary
          // content, so it needs its own legible surface rather than a
          // see-through fill.
          color: Color.alphaBlend(
              AppColors.glassFill(context), glass.canvas.withValues(alpha: 0.97)),
          borderRadius: LiquidGlass.signatureRadius(LiquidGlass.radiusCard),
          border: Border.all(color: glass.glassBorder, width: 1),
          boxShadow: glass.ambientGlow(),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 8),
            child: Row(children: [
              Icon(AppIcons.notifications, size: 18, color: glass.accentSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  unread > 0 ? 'Notifications ($unread new)' : 'Notifications',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.textPrimaryOf(context)),
                ),
              ),
              if (unread > 0)
                Flexible(
                  child: TextButton(
                    onPressed: _markAllRead,
                    child: Text('Mark all read',
                        maxLines: 1,
                        style: TextStyle(
                            color: glass.accentSecondary, fontSize: 11)),
                  ),
                ),
            ]),
          ),
          Divider(height: 1, color: glass.glassBorder),
          Flexible(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(28),
                    child: Center(
                        child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))),
                  )
                : _error != null
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 34, color: AppColors.red),
                          const SizedBox(height: 8),
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondaryOf(context))),
                          TextButton(onPressed: () { setState(() => _loading = true); _load(); },
                              child: const Text('Retry')),
                        ]),
                      )
                : _notifs.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.notifications_none_rounded,
                              size: 34, color: AppColors.textMutedOf(context)),
                          const SizedBox(height: 8),
                          Text("You're all caught up.",
                              style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondaryOf(context))),
                        ]),
                      )
                    // BUG_REGISTER P2-05 — confirmed bounded, and worth saying
                    // so here because the bound is 150 lines away: `_load()`
                    // ends in `.limit(20)`, so `shrinkWrap` lays out at most 20
                    // rows, not an open-ended feed. The full list is a route
                    // away behind 'See all notifications'. If that limit is
                    // ever raised, this becomes a real cost.
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsetsDirectional.fromSTEB(0, 4, 0, 4 + NavInsets.of(context)),
                        itemCount: _notifs.length,
                        separatorBuilder: (_, __) =>
                            Divider(height: 1, indent: 56, color: glass.glassBorder),
                        itemBuilder: (ctx, i) {
                          final n = _notifs[i];
                          final isRead = n['is_read'] as bool? ?? false;
                          final cat = n['category'] as String?;
                          final color = _catColor(cat);
                          final time = n['received_at'] != null
                              ? DateTime.tryParse(n['received_at'])
                              : null;
                          return InkWell(
                            onTap: () => _onTap(n),
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(9)),
                                      child: Icon(_catIcon(cat), color: color, size: 16),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(n['title'] ?? '',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: AppTextStyles.bodyMedium.copyWith(
                                                    color: AppColors.textPrimaryOf(context),
                                                    fontWeight: isRead
                                                        ? FontWeight.w500
                                                        : FontWeight.w700)),
                                            const SizedBox(height: 2),
                                            Text(n['body'] ?? '',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: AppTextStyles.labelSmall.copyWith(
                                                    color: AppColors
                                                        .textSecondaryOf(context))),
                                            if (time != null)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 2),
                                                child: Text(
                                                    AppFormatters.relativeTime(time),
                                                    style: AppTextStyles.labelSmall
                                                        .copyWith(
                                                            fontSize: 9,
                                                            color: AppColors
                                                                .textMutedOf(context))),
                                              ),
                                          ]),
                                    ),
                                    if (!isRead)
                                      Container(
                                          width: 7,
                                          height: 7,
                                          margin: const EdgeInsetsDirectional.only(top: 5, start: 6),
                                          decoration: BoxDecoration(
                                              color: glass.accentSecondary,
                                              shape: BoxShape.circle)),
                                  ]),
                            ),
                          );
                        },
                      ),
          ),
          Divider(height: 1, color: glass.glassBorder),
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              GoRouter.of(context).push('/notifications');
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('See all notifications',
                    style: AppTextStyles.bodyMedium.copyWith(
                        color: glass.accentSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_rounded,
                    size: 14, color: glass.accentSecondary),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
