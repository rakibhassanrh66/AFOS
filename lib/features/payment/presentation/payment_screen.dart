import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import 'payment_webview_screen.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});
  @override State<PaymentScreen> createState() => _PaymentState();
}

class _PaymentState extends State<PaymentScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadHistory() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    setState(() => _error = null);
    try {
      final res = await SupabaseConfig.client
          .from('payment_records')
          .select()
          .eq('student_id', uid)
          .order('created_at', ascending: false) as List;
      if (mounted) setState(() => _history = res.cast());
    } catch (e) {
      // Previously swallowed silently — a real load failure for financial
      // records rendered identically to "no payment history", which is a
      // bad thing to get wrong.
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  static const _categories = [
    _PayCat('Tuition Fee',   Icons.school_rounded,         AppColors.blue,   'tuition'),
    _PayCat('Hall Fee',      AppIcons.hall,                  AppColors.amber,  'hall'),
    _PayCat('Library Fine',  AppIcons.library,               AppColors.indigo, 'library'),
    _PayCat('Exam Fee',      Icons.assignment_rounded,      AppColors.orange, 'exam'),
    _PayCat('Admission Fee', Icons.badge_rounded,           AppColors.green,  'admission'),
    _PayCat('Other',         Icons.more_horiz_rounded,      AppColors.textSecondary, 'other'),
  ];

  static const _tabLabels = ['Pay Now', 'History'];
  static const _tabIcons = [Icons.payments_rounded, Icons.receipt_long_rounded];

  double get _totalPaid => _history.where((p) => p['status'] == 'paid')
      .fold<double>(0, (sum, p) => sum + ((p['amount'] as num?)?.toDouble() ?? 0));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: const AfosAppBar(title: 'Payment'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: AppColors.goldGradient,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: const Icon(Icons.payments_rounded, color: Colors.white, size: 24)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Payments', style: AppTextStyles.titleLarge.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('${_categories.length} fee categories', style: AppTextStyles.bodyMedium.copyWith(color: Colors.white.withValues(alpha: 0.9))),
              ])),
              if (!_loading && _totalPaid > 0) Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(12)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('৳${_totalPaid.toStringAsFixed(0)}', textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                      style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.0, fontWeight: FontWeight.w800)),
                  Text('total paid', textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 10, height: 1.0)),
                ]),
              ),
            ]),
          ),
        ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.06, curve: Curves.easeOutCubic),
        AnimatedBuilder(
          animation: _tab,
          builder: (ctx, _) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: List.generate(_tabLabels.length, (i) {
              final sel = _tab.index == i;
              return Expanded(child: GestureDetector(
                onTap: () => _tab.animateTo(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                      gradient: sel ? AppColors.goldGradient : null,
                      color: sel ? null : AppColors.glassFill(context),
                      borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(_tabIcons[i], size: 16, color: sel ? Colors.white : AppColors.textSecondaryOf(context)),
                    const SizedBox(width: 6),
                    Text(_tabLabels[i],
                        textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                        style: TextStyle(color: sel ? Colors.white : AppColors.textSecondaryOf(context),
                            fontSize: 12.5, height: 1.0, fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                  ]),
                ),
              ));
            })),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: TabBarView(controller: _tab, children: [
          const _PayNowTab(categories: _categories),
          _loading
              ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 40),
                      const SizedBox(height: 12),
                      Text('Couldn\'t load: $_error', textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textSecondaryOf(context))),
                      const SizedBox(height: 12),
                      TextButton(onPressed: _loadHistory, child: const Text('Retry')),
                    ])))
                  : _HistoryTab(history: _history),
        ])),
      ]),
    );
  }
}

class _PayNowTab extends StatelessWidget {
  final List<_PayCat> categories;
  const _PayNowTab({required this.categories});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      // Fixed 2-column count stretched into 2 giant tiles on a wide desktop
      // browser window; max-extent keeps each tile a consistent size and
      // adds columns as space allows instead (see dashboard_screen.dart).
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 200, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 1.1),
      itemCount: categories.length,
      itemBuilder: (ctx, i) => _PayCard(cat: categories[i], index: i),
    );
  }
}

class _PayCard extends StatelessWidget {
  final _PayCat cat; final int index;
  const _PayCard({required this.cat, required this.index});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => PaymentWebViewScreen(category: cat.label))),
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [cat.color.withValues(alpha:AppColors.isDark(context)?0.32:0.22),
                       AppColors.holoTeal.withValues(alpha:0.12)]),
          ),
          padding: const EdgeInsets.all(1),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(15)),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [cat.color, cat.color.withValues(alpha: 0.7)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: cat.color.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]),
                child: Icon(cat.icon, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 12),
              Text(cat.label,
                  style: AppTextStyles.titleMedium.copyWith(color: textPrimary),
                  textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('Check balance →',
                  style: AppTextStyles.bodyMedium.copyWith(color: cat.color, fontSize: 11)),
            ]),
          ),
        ),
      ).animate(delay: Duration(milliseconds: index * 60))
          .fadeIn(curve: Curves.easeOutCubic).scale(begin: const Offset(0.95, 0.95), curve: Curves.easeOutCubic),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  const _HistoryTab({required this.history});

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.receipt_long_outlined, color: AppColors.textMutedOf(context), size: 56),
          const SizedBox(height: 16),
          Text('No payment history',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      itemBuilder: (ctx, i) {
        final p = history[i];
        final status = p['status'] as String? ?? 'pending';
        final statusColor = status == 'paid' ? AppColors.green
            : status == 'failed' ? AppColors.red : AppColors.amber;
        return RepaintBoundary(
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: AppColors.holoBlue.withValues(alpha:0.1), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.receipt_outlined, color: AppColors.holoBlue, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p['category'] ?? '',
                    style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                Text(p['payment_date'] != null
                    ? AppFormatters.date(DateTime.parse(p['payment_date']))
                    : 'Pending',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('৳${p['amount'] ?? 0}',
                    style: AppTextStyles.titleLarge.copyWith(color: AppColors.gold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: statusColor.withValues(alpha:0.12), borderRadius: BorderRadius.circular(10)),
                  child: Text(status.toUpperCase(),
                      style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

class _PayCat {
  final String label, id; final IconData icon; final Color color;
  const _PayCat(this.label, this.icon, this.color, this.id);
}
