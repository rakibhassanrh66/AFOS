import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/motion.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

import '../../../core/layout/nav_insets.dart';
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});
  @override State<NotificationCenterScreen> createState() => _NotifState();
}

class _NotifState extends State<NotificationCenterScreen> {
  static const _pageSize = 50;
  List<Map<String, dynamic>> _notifs = [];
  bool _loading = true, _loadingMore = false, _hasMore = true;
  String? _error;
  int _loadGen = 0;

  @override
  void initState() { super.initState(); _load(); }

  // Narrowed to exactly what this screen reads/acts on (list rendering +
  // _onTapNotification's deep link) — this table's history was previously
  // fetched in full with no cap at all, unlike the popover's own query on
  // the same table which already limits to 20.
  static const _columns = 'id, is_read, category, received_at, title, body, deep_link_route';

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    // Guard against out-of-order responses: a pull-to-refresh racing with
    // _markRead/_markAllRead (or two quick refreshes) could otherwise let
    // an older, slower response overwrite a fresher one with stale data.
    final gen = ++_loadGen;
    try {
      final res = await SupabaseConfig.client
          .from('user_notifications')
          .select(_columns)
          .eq('user_id', uid)
          .order('received_at', ascending: false)
          .range(0, _pageSize - 1) as List;
      if (mounted && gen == _loadGen) {
        setState(() { _notifs = res.cast(); _error = null; _hasMore = res.length == _pageSize; });
      }
    } catch (e) {
      // Silent failure looked identical to "no notifications yet".
      if (mounted && gen == _loadGen) setState(() => _error = friendlyError(e));
    }
    if (mounted && gen == _loadGen) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    final uid = SupabaseConfig.uid;
    if (uid == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final res = await SupabaseConfig.client
          .from('user_notifications')
          .select(_columns)
          .eq('user_id', uid)
          .order('received_at', ascending: false)
          .range(_notifs.length, _notifs.length + _pageSize - 1) as List;
      if (mounted) {
        setState(() { _notifs = [..._notifs, ...res.cast()]; _hasMore = res.length == _pageSize; });
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _markAllRead() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    try {
      await SupabaseConfig.client.from('user_notifications')
          .update({'is_read': true}).eq('user_id', uid);
      _load();
    } catch (_) {}
  }

  Future<void> _markRead(String id) async {
    try {
      await SupabaseConfig.client.from('user_notifications')
          .update({'is_read': true}).eq('id', id);
      if (mounted) {
        setState(() {
        final idx = _notifs.indexWhere((n) => n['id'] == id);
        if (idx >= 0) _notifs[idx] = {..._notifs[idx], 'is_read': true};
      });
      }
    } catch (_) {}
  }

  void _onTapNotification(Map<String, dynamic> n) {
    _markRead(n['id'] as String);
    final route = n['deep_link_route'] as String?;
    if (route != null && route.isNotEmpty) context.push(route);
  }

  static IconData _catIcon(String? cat) => switch (cat) {
    'schedule'    => AppIcons.schedule,
    'transport'   => AppIcons.transport,
    'payment'     => AppIcons.payment,
    'library'     => AppIcons.library,
    'lost_found'  => AppIcons.lostFound,
    'club'        => AppIcons.clubs,
    'message'     => AppIcons.deptChat,
    'exam'        => AppIcons.examSeat,
    // Emitted by CourseOfferingRepository (approve/reject/new-course) and by
    // the course group chat. Both previously fell through to the generic
    // bell, so a course notification was indistinguishable from any other.
    'course_offering' => AppIcons.schedule,
    'course_message'  => AppIcons.deptChat,
    'assignment'  => AppIcons.assignments,
    _             => AppIcons.notifications,
  };

  static Color _catColor(String? cat) => switch (cat) {
    'schedule'    => AppColors.red,
    'transport'   => AppColors.amber,
    'payment'     => AppColors.gold,
    'library'     => AppColors.indigo,
    'lost_found'  => AppColors.coral,
    'club'        => AppColors.pink,
    'message'     => AppColors.blue,
    'exam'        => AppColors.orange,
    'course_offering' => AppColors.green,
    'course_message'  => AppColors.blue,
    'assignment'  => AppColors.purple,
    _             => AppColors.blue,
  };

  @override
  Widget build(BuildContext context) {
    final unread = _notifs.where((n) => !(n['is_read'] as bool? ?? false)).length;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(
        title: 'Notifications',
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read',
                  style: TextStyle(color: AppColors.blue, fontSize: 12)),
            ),
        ],
      ),
      body: Column(children: [
        if (!_loading && _notifs.isNotEmpty) FeatureHeader(
          title: 'Notifications',
          subtitle: '$unread unread of ${_notifs.length}',
          icon: Icons.notifications_active_rounded,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.indigo, AppColors.blue]),
          margin: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
        ).animate().fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
            .slideY(begin: -0.06, curve: AppMotion.standard),
        Expanded(child: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 6))
          : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _notifs.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'No notifications',
                  subtitle: 'You\'re all caught up.')
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.blue,
                  child: ListView.builder(
                    padding: EdgeInsetsDirectional.fromSTEB(12, 12, 12, 12 + NavInsets.of(context)),
                    itemCount: _notifs.length + (_hasMore ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == _notifs.length) {
                        // Fires once the footer scrolls into view — no
                        // separate scroll-position tracking needed since
                        // ListView.builder only builds items near the
                        // viewport in the first place.
                        if (!_loadingMore) WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
                        return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(child: SizedBox(width: 24, height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.blue))));
                      }
                      final n = _notifs[i];
                      final isRead = n['is_read'] as bool? ?? false;
                      final cat = n['category'] as String?;
                      final color = _catColor(cat);
                      final time = n['received_at'] != null
                          ? DateTime.tryParse(n['received_at']) : null;
                      return Dismissible(
                        key: Key(n['id'] as String),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsetsDirectional.only(end: 20),
                          decoration: BoxDecoration(
                              color: AppColors.red.withValues(alpha:0.8),
                              borderRadius: AppDepth.radius(1)),
                          child: const Icon(Icons.delete_outline_rounded,
                              color: Colors.white)),
                        // A swipe-to-dismiss that has passed the threshold and
                        // committed — the one gesture on this screen that
                        // destroys something.
                        onDismissed: (_) { AppHaptics.warning(); setState(() => _notifs.removeAt(i)); },
                        child: GestureDetector(
                          onTap: () => _onTapNotification(n),
                          child: Container(
                            clipBehavior: Clip.antiAlias,
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceOf(context),
                              borderRadius: AppDepth.radius(1),
                              border: Border.all(color: AppColors.borderOf(context), width: 0.5),
                            ),
                            // Was IntrinsicHeight + CrossAxisAlignment.stretch just to
                            // make the unread-color stripe span the row's full height --
                            // that forces a two-pass layout that occasionally
                            // overflowed by a rounding pixel ("RenderFlex overflowed by
                            // 1.00 pixels"). A Positioned stripe in a Stack spans the
                            // same full height without the extra layout pass or the
                            // overflow risk.
                            child: Stack(children: [
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(17, 14, 14, 14),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                    color: color.withValues(alpha:0.15),
                                    borderRadius: AppDepth.radius(1)),
                                child: Icon(_catIcon(cat), color: color, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Expanded(child: Text(n['title'] ?? '',
                                      style: AppTextStyles.titleMedium.copyWith(
                                          color: AppColors.textPrimaryOf(context),
                                          fontWeight: isRead ? FontWeight.w500 : FontWeight.w700))),
                                  if (!isRead) Container(width: 8, height: 8,
                                      decoration: const BoxDecoration(
                                          color: AppColors.blue, shape: BoxShape.circle)),
                                ]),
                                const SizedBox(height: 3),
                                Text(n['body'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)),
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                                if (time != null) ...[
                                  const SizedBox(height: 4),
                                  Text(AppFormatters.relativeTime(time),
                                      style: AppTextStyles.labelSmall.copyWith(fontSize: 10, color: AppColors.textMutedOf(context))),
                                ],
                              ])),
                                ]),
                              ),
                              if (!isRead) Positioned(left: 0, top: 0, bottom: 0,
                                  child: Container(width: 3, color: color)),
                            ]),
                          ),
                        ).animate(delay: AppMotion.staggerFor(context, i)).fadeIn().slideX(begin: 0.03),
                      );
                    },
                  ),
                )),
      ]),
    );
  }
}
