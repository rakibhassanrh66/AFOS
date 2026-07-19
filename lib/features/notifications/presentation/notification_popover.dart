import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/liquid_glass_theme.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';

import '../../../shared/widgets/glass_bottom_nav.dart';
/// Compact floating notification panel, anchored under the app-bar bell.
///
/// The bell deliberately does NOT navigate to the full-screen center any
/// more: tapping the bell should feel like peeking at a small scrollable
/// tray (identical behavior on web, Android, and iOS), while the
/// "Notifications" entry in the slide menu remains the full-window view.
Future<void> showNotificationPopover(BuildContext context) {
  final reduceMotion = MediaQuery.of(context).disableAnimations;
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
      return SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 64, right: 12),
            child: SizedBox(
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: const _NotificationPopover(),
              ),
            ),
          ),
        ),
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
    try {
      await SupabaseConfig.client
          .from('user_notifications')
          .update({'is_read': true}).eq('user_id', uid);
    } catch (_) {}
  }

  Future<void> _onTap(Map<String, dynamic> n) async {
    final id = n['id'] as String;
    setState(() {
      final idx = _notifs.indexWhere((e) => e['id'] == id);
      if (idx >= 0) _notifs[idx] = {..._notifs[idx], 'is_read': true};
    });
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
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
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
                TextButton(
                  onPressed: _markAllRead,
                  child: Text('Mark all read',
                      style: TextStyle(color: glass.accentSecondary, fontSize: 11)),
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
                          Text("You're all caught up!",
                              style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondaryOf(context))),
                        ]),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(0, 4, 0, 4 + GlassBottomNav.navContentClearance),
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
                                          margin: const EdgeInsets.only(top: 5, left: 6),
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
