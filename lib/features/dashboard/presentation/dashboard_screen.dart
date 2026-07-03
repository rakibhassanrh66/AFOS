import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../shell/presentation/top_app_bar.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override State<DashboardScreen> createState() => _DashboardState();
}

class _DashboardState extends State<DashboardScreen> {
  UserModel? _user;
  List<Map<String,dynamic>> _notices = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final profileRaw = await SupabaseConfig.client
          .from('profiles').select().eq('id', uid).single();
      final noticesRaw = await SupabaseConfig.client
          .from('notices').select()
          .order('created_at', ascending: false).limit(3);
      if (mounted) setState(() {
        _user    = UserModel.fromJson(profileRaw);
        _notices = noticesRaw.cast<Map<String,dynamic>>();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _modules = [
    _Module('Schedule',    Icons.calendar_today_rounded,   AppColors.blue,   '/schedule',  'Today\'s classes'),
    _Module('Hall',        Icons.apartment_rounded,         AppColors.amber,  '/hall',      'Application status'),
    _Module('Transport',   Icons.directions_bus_rounded,    AppColors.teal,   '/transport', 'Next departure'),
    _Module('Payment',     Icons.payment_rounded,           AppColors.gold,   '/payment',   'Check dues'),
    _Module('Library',     Icons.menu_book_rounded,         AppColors.purple, '/library',   'Borrowed books'),
    _Module('Lost & Found',Icons.search_rounded,            AppColors.coral,  '/lost-found','New found items'),
    _Module('Clubs',       Icons.groups_rounded,            AppColors.pink,   '/clubs',     'Upcoming events'),
    _Module('Mentorship',  Icons.school_rounded,            Color(0xFF60A5FA),'/mentorship','Book a session'),
    _Module('Exam Seats',  Icons.event_seat_rounded,        AppColors.orange, '/exam-seat', 'View seat plan'),
    _Module('Dept Chat',   Icons.chat_rounded,              AppColors.indigo, '/dept-chat', 'Department channel'),
    _Module('VR-ID',       Icons.qr_code_rounded,           AppColors.green,  '/vr-id',     'Active ✓'),
    _Module('Notices',     Icons.campaign_rounded,          AppColors.red,    '/notifications','Latest notices'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: AfosAppBar(title: 'Dashboard'),
      body: RefreshIndicator(
        onRefresh: _load, color: AppColors.holoBlue,
        backgroundColor: AppColors.surfaceOf(context),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              RepaintBoundary(
                child: GlassCard(
                  borderRadius: 20,
                  glowColor: AppColors.holoBlue,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _Greeting(user: _user, loading: _loading),
                      const SizedBox(height: 16),
                      _QuickChips(),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('Modules', style: AppTextStyles.headlineLarge
                  .copyWith(color: AppColors.textPrimaryOf(context))),
              const SizedBox(height: 12),
            ]),
          )),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: _loading
                ? SliverToBoxAdapter(child: ShimmerGrid(count: 12))
                : SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, crossAxisSpacing: 12,
                        mainAxisSpacing: 12, childAspectRatio: 1.1),
                    delegate: SliverChildBuilderDelegate(
                        (ctx, i) => _ModuleCard(m: _modules[i], index: i),
                        childCount: _modules.length)),
          ),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('📢 Latest Notices', style: AppTextStyles.headlineLarge
                    .copyWith(color: AppColors.textPrimaryOf(context))),
                TextButton(
                  onPressed: () => context.go('/notifications'),
                  child: Text('See all →', style: TextStyle(color: AppColors.holoBlue))),
              ]),
              const SizedBox(height: 12),
              if (_loading) const ShimmerList(count: 3, itemHeight: 80)
              else if (_notices.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('No notices yet',
                      style: TextStyle(color: AppColors.textSecondaryOf(context))))
              else ..._notices.asMap().entries.map((e) =>
                  _NoticeCard(notice: e.value, index: e.key)),
              const SizedBox(height: 32),
            ]),
          )),
        ]),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  final UserModel? user; final bool loading;
  const _Greeting({this.user, required this.loading});
  @override
  Widget build(BuildContext context) {
    if (loading) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ShimmerCard(width: 200, height: 28, radius: 6),
      const SizedBox(height: 8),
      ShimmerCard(width: 140, height: 18, radius: 4),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${AppFormatters.greetingEmoji()} ${AppFormatters.greeting()},',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
      Text(user?.firstName ?? 'Student', style: AppTextStyles.displayMedium
          .copyWith(color: AppColors.textPrimaryOf(context))),
      const SizedBox(height: 4),
      Text(AppFormatters.fullDate(DateTime.now()),
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
    ]).animate().fadeIn(duration: const Duration(milliseconds: 500), curve: Curves.easeOutCubic);
  }
}

class _QuickChips extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 44, child: ListView(
      scrollDirection: Axis.horizontal,
      children: ['📅 Today: 4 classes', '🚌 Route 5: On time',
                 '📚 2 books due soon', '🏠 Hall: Pending']
          .map((t) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: AppColors.glassFill(context),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: AppColors.glassBorder(context), width: 0.5)),
                  child: Text(t, style: TextStyle(
                      color: AppColors.textPrimaryOf(context), fontSize: 12)))))
          .toList()));
  }
}

/// Lightweight repeated-list-item card: gradient border only, no BackdropFilter.
/// Used for grid/list items where many are on screen at once — full [GlassCard]
/// blur is reserved for hero/summary panels per the perf budget.
class _LiteCard extends StatelessWidget {
  final Widget child; final double borderRadius; final Color accent;
  const _LiteCard({required this.child, required this.accent, this.borderRadius = 16});
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [accent.withOpacity(AppColors.isDark(context) ? 0.35 : 0.25),
                     AppColors.holoTeal.withOpacity(0.15)]),
        ),
        padding: const EdgeInsets.all(1),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(borderRadius - 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final _Module m; final int index;
  const _ModuleCard({required this.m, required this.index});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go(m.route),
      child: _LiteCard(
        accent: m.color,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                    color: m.color.withAlpha(38),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(m.icon, color: m.color, size: 22)),
              const Spacer(),
            ]),
            const Spacer(),
            Text(m.title, style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.textPrimaryOf(context)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(m.subtitle, style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondaryOf(context)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    ).animate(delay: Duration(milliseconds: index * 60))
        .fadeIn(curve: Curves.easeOutCubic)
        .scale(begin: const Offset(0.95, 0.95), curve: Curves.easeOutCubic);
  }
}

class _NoticeCard extends StatelessWidget {
  final Map<String,dynamic> notice; final int index;
  const _NoticeCard({required this.notice, required this.index});

  Color _catColor(String? cat) => switch (cat) {
    'EXAM'   => AppColors.red,   'EVENT' => AppColors.holoBlue,
    'URGENT' => AppColors.gold,  _ => AppColors.green,
  };

  @override
  Widget build(BuildContext context) {
    final cat = notice['category'] as String? ?? 'GENERAL';
    final c = _catColor(cat);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _LiteCard(
        borderRadius: 12,
        accent: c,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              border: Border(left: BorderSide(color: c, width: 3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: c.withAlpha(38), borderRadius: BorderRadius.circular(4)),
              child: Text(cat, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700))),
            const SizedBox(height: 6),
            Text(notice['title'] ?? '', style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.textPrimaryOf(context)),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(notice['body'] ?? '', style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondaryOf(context)),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    ).animate(delay: Duration(milliseconds: index * 100))
        .fadeIn(curve: Curves.easeOutCubic).slideY(begin: 0.05, curve: Curves.easeOutCubic);
  }
}

class _Module {
  final String title, route, subtitle; final IconData icon; final Color color;
  const _Module(this.title, this.icon, this.color, this.route, this.subtitle);
}
