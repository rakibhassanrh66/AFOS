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
import 'notification_visuals.dart';

import '../../../core/layout/nav_insets.dart';
/// Compact floating notification panel, anchored under the app-bar bell.
///
/// The bell deliberately does NOT navigate to the full-screen center any
/// more: tapping the bell should feel like peeking at a small scrollable
/// tray (identical behavior on web, Android, and iOS), while the
/// "Notifications" entry in the slide menu remains the full-window view.
///
/// ANCHORING: this used to be a hardcoded `Alignment.topRight` with `top: 64,
/// end: 12` (correct on a phone, wrong on web where the bell sits inside a
/// sidebar-offset content column), then a manual `localToGlobal` measurement
/// fed into `showGeneralDialog` (correct on web, but wrapped in a `SafeArea`
/// that double-counted the phone status-bar inset against already-global
/// coordinates, breaking the app). Both were hand-rolled coordinate math
/// across two different Navigators (the bell lives inside the ShellRoute's
/// nested navigator; the tray needs to render above everything, in the root
/// one) -- exactly the kind of thing that keeps regressing.
///
/// The third attempt anchored it with `CompositedTransformTarget`/`Follower`,
/// which does place the panel under the bell correctly and survives being in
/// a different Navigator. What it does NOT do -- and what nothing here did --
/// is keep the panel inside the window. `CompositedTransformFollower` applies
/// a transform; it has no notion of a screen edge, so the tray simply hung
/// off the bell wherever the bell happened to be:
///
///   * On a phone the panel was `screenWidth - 24` wide, right-aligned to a
///     bell whose own right edge sits 18px in, leaving **6px on the left and
///     18px on the right**. Off-centre by exactly the amount that reads as a
///     mistake rather than a margin.
///   * Nothing bounded the bottom. `maxHeight` was a fraction of the screen
///     measured from zero, not from where the panel actually starts, so on a
///     short browser window the list ran under the bottom edge and the "See
///     all notifications" footer was unreachable.
///
/// So the anchoring is now measured AND clamped: [notificationPopoverRect]
/// is pure geometry over the anchor and the safe area, unit-tested in
/// test/notification_popover_anchor_test.dart, and the panel is placed at the
/// rect it returns. The anchor is re-measured with `localToGlobal` on every
/// build rather than captured once, so resizing a browser window moves the
/// tray with the bell instead of stranding it.
///
/// There is deliberately no `SafeArea` anywhere in here: it is what broke
/// attempt two, padding a panel by the device's constant insets regardless of
/// where the panel actually was. The insets are an INPUT to the geometry
/// below, applied once, in one place.

/// Where the tray goes: right-aligned under [anchor], pulled back inside the
/// safe area, flipped above the anchor when there is genuinely more room
/// there, and never taller than the space it landed in.
///
/// Pure function of its arguments so the arithmetic can be tested without
/// pumping a widget or faking an overlay — the positioning has regressed
/// three times, each time in a way that only showed up on a device nobody
/// had to hand.
@visibleForTesting
Rect notificationPopoverRect({
  required Rect anchor,
  required Size screen,
  required EdgeInsets viewPadding,
  required double preferredWidth,
  required double preferredHeight,
  double margin = 12,
  double gap = 8,
}) {
  final minX = viewPadding.left + margin;
  final maxX = screen.width - viewPadding.right - margin;
  final minY = viewPadding.top + margin;
  final maxY = screen.height - viewPadding.bottom - margin;

  final available = (maxX - minX).clamp(0.0, double.infinity);
  final width = preferredWidth < available ? preferredWidth : available;

  // Right edge follows the bell, then the whole panel is pushed back inside
  // the safe box. Clamping the LEFT edge last matters: on a narrow phone the
  // panel is as wide as the safe box, so the right-align above would put it
  // slightly off the left edge, and this is what re-centres it.
  var left = anchor.right - width;
  if (left + width > maxX) left = maxX - width;
  if (left < minX) left = minX;

  final below = maxY - (anchor.bottom + gap);
  final above = (anchor.top - gap) - minY;

  double top;
  double height;
  if (below >= preferredHeight || below >= above) {
    top = anchor.bottom + gap;
    height = preferredHeight < below ? preferredHeight : below;
  } else {
    height = preferredHeight < above ? preferredHeight : above;
    top = anchor.top - gap - height;
  }
  if (height < 0) height = 0;
  if (top < minY) top = minY;

  return Rect.fromLTWH(left, top, width, height);
}

void showNotificationPopover(BuildContext context) {
  final overlay = Navigator.of(context, rootNavigator: true).overlay!;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _PopoverOverlay(
      anchorContext: context,
      onClose: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _PopoverOverlay extends StatefulWidget {
  /// The bell's own context, kept (not its coordinates) so the anchor can be
  /// re-measured every build.
  final BuildContext anchorContext;
  final VoidCallback onClose;
  const _PopoverOverlay({required this.anchorContext, required this.onClose});

  @override
  State<_PopoverOverlay> createState() => _PopoverOverlayState();
}

class _PopoverOverlayState extends State<_PopoverOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _curved;
  bool _closing = false;

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: LiquidGlass.entranceDuration);
    _curved = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  // _reduceMotion reads MediaQuery, which throws if touched from initState --
  // dependOnInheritedElement() is only legal once the element has actually
  // mounted (same class of bug already found and fixed in splash_screen.dart
  // this session). didChangeDependencies is the framework's designated place
  // for it, and still fires before the first frame, so starting the entrance
  // here costs nothing relative to before. Guarded because
  // didChangeDependencies can fire more than once.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (_reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Animates out, then actually removes the entry -- yanking it mid-fade
  // would cut the exit transition off on the last frame.
  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    if (!_reduceMotion) {
      await _controller.reverse();
    }
    widget.onClose();
  }

  /// The bell's rectangle in global coordinates, or null if it has gone away
  /// (the route under the tray was popped while it was open).
  Rect? get _anchor {
    final box = widget.anchorContext.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final anchor = _anchor;
    // Nothing to anchor to any more. Closing is the honest response — a tray
    // pinned to a control that no longer exists is the "weird place" bug in
    // its purest form.
    if (anchor == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close());
      return const SizedBox.shrink();
    }

    final rect = notificationPopoverRect(
      anchor: anchor,
      screen: media.size,
      viewPadding: media.viewPadding,
      preferredWidth: 380,
      preferredHeight: (media.size.height * 0.66).clamp(280.0, 520.0).toDouble(),
    );

    return Stack(children: [
      // Full-screen transparent barrier -- tap outside the panel to dismiss,
      // same as showGeneralDialog's old barrierDismissible.
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _close,
          child: const SizedBox.expand(),
        ),
      ),
      Positioned.fromRect(
        rect: rect,
        child: FadeTransition(
          opacity: _curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: LiquidGlass.entranceScaleFrom, end: 1)
                .animate(_curved),
            // Grows out of the corner nearest the bell, so the motion reads as
            // coming FROM the thing that was tapped.
            alignment: rect.top < anchor.top
                ? Alignment.bottomRight
                : Alignment.topRight,
            child: _NotificationPopover(onClose: _close),
          ),
        ),
      ),
    ]);
  }
}

class _NotificationPopover extends StatefulWidget {
  final VoidCallback onClose;
  const _NotificationPopover({required this.onClose});
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
    widget.onClose();
    if (route != null && route.isNotEmpty) {
      // ignore: use_build_context_synchronously
      GoRouter.of(context).push(route);
    }
  }


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
                          final color = NotificationVisuals.colorOf(cat);
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
                                      child: Icon(NotificationVisuals.iconOf(cat), color: color, size: 16),
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
              widget.onClose();
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
