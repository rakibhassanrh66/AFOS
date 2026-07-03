import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});
  @override State<NotificationCenterScreen> createState() => _NotifState();
}

class _NotifState extends State<NotificationCenterScreen> {
  List<Map<String, dynamic>> _notifs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final res = await SupabaseConfig.client
          .from('user_notifications')
          .select()
          .eq('user_id', uid)
          .order('received_at', ascending: false) as List;
      if (mounted) setState(() => _notifs = res.cast());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
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
      if (mounted) setState(() {
        final idx = _notifs.indexWhere((n) => n['id'] == id);
        if (idx >= 0) _notifs[idx] = {..._notifs[idx], 'is_read': true};
      });
    } catch (_) {}
  }

  static IconData _catIcon(String? cat) => switch (cat) {
    'schedule'    => Icons.calendar_today_rounded,
    'transport'   => Icons.directions_bus_rounded,
    'payment'     => Icons.payment_rounded,
    'library'     => Icons.menu_book_rounded,
    'lost_found'  => Icons.search_rounded,
    'club'        => Icons.groups_rounded,
    'message'     => Icons.chat_rounded,
    'exam'        => Icons.event_seat_rounded,
    _             => Icons.notifications_rounded,
  };

  static Color _catColor(String? cat) => switch (cat) {
    'schedule'    => AppColors.red,
    'transport'   => AppColors.amber,
    'payment'     => AppColors.gold,
    'library'     => AppColors.purple,
    'lost_found'  => AppColors.coral,
    'club'        => AppColors.pink,
    'message'     => AppColors.blue,
    'exam'        => AppColors.orange,
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
      body: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 6))
          : _notifs.isEmpty
              ? EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'No notifications',
                  subtitle: 'You\'re all caught up!')
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.blue,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _notifs.length,
                    itemBuilder: (ctx, i) {
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
                          padding: const EdgeInsets.only(right: 20),
                          decoration: BoxDecoration(
                              color: AppColors.red.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(14)),
                          child: const Icon(Icons.delete_outline_rounded,
                              color: Colors.white)),
                        onDismissed: (_) => setState(() => _notifs.removeAt(i)),
                        child: GestureDetector(
                          onTap: () => _markRead(n['id'] as String),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceOf(context),
                              borderRadius: BorderRadius.circular(14),
                              border: Border(
                                left: BorderSide(
                                    color: isRead ? Colors.transparent : color,
                                    width: 3),
                                right: BorderSide(color: AppColors.borderOf(context), width: 0.5),
                                top: BorderSide(color: AppColors.borderOf(context), width: 0.5),
                                bottom: BorderSide(color: AppColors.borderOf(context), width: 0.5),
                              ),
                            ),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                    color: color.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10)),
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
                        ).animate(delay: Duration(milliseconds: i * 40)).fadeIn().slideX(begin: 0.03),
                      );
                    },
                  ),
                ),
    );
  }
}
