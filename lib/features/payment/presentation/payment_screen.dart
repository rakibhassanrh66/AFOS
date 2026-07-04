import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
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

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final res = await SupabaseConfig.client
          .from('payment_records')
          .select()
          .eq('student_id', uid)
          .order('created_at', ascending: false) as List;
      if (mounted) setState(() => _history = res.cast());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  static const _categories = [
    _PayCat('Tuition Fee',   Icons.school_rounded,         AppColors.blue,   'tuition'),
    _PayCat('Hall Fee',      Icons.apartment_rounded,       AppColors.amber,  'hall'),
    _PayCat('Library Fine',  Icons.menu_book_rounded,       AppColors.purple, 'library'),
    _PayCat('Exam Fee',      Icons.assignment_rounded,      AppColors.orange, 'exam'),
    _PayCat('Admission Fee', Icons.badge_rounded,           AppColors.green,  'admission'),
    _PayCat('Other',         Icons.more_horiz_rounded,      AppColors.textSecondary, 'other'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: AfosAppBar(title: 'Payment'),
      body: Column(children: [
        Container(
          color: AppColors.surfaceOf(context),
          child: TabBar(
            controller: _tab,
            labelColor: AppColors.holoBlue,
            unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.holoBlue,
            tabs: const [Tab(text: 'Pay Now'), Tab(text: 'History')],
          ),
        ),
        Expanded(child: TabBarView(controller: _tab, children: [
          _PayNowTab(categories: _categories),
          _loading
              ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
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
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: 1.1),
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
              colors: [cat.color.withOpacity(AppColors.isDark(context)?0.32:0.22),
                       AppColors.holoTeal.withOpacity(0.12)]),
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
                  color: cat.color.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
                child: Icon(cat.icon, color: cat.color, size: 26),
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
                    color: AppColors.holoBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.receipt_outlined, color: AppColors.holoBlue, size: 20),
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
                      color: statusColor.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
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
