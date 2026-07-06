import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override State<LibraryScreen> createState() => _LibraryState();
}

class _LibraryState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _borrowed = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _loading = true, _searching = false;
  double _totalFine = 0;
  Timer? _fineTimer;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
    _fineTimer = Timer.periodic(const Duration(seconds: 60), (_) => _calcFines());
  }

  @override
  void dispose() { _tab.dispose(); _fineTimer?.cancel(); _searchCtrl.dispose(); super.dispose(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final res = await SupabaseConfig.client
          .from('borrowed_books')
          .select('*, books(*)')
          .eq('student_id', uid)
          .eq('status', 'borrowed') as List;
      if (mounted) setState(() => _borrowed = res.cast());
      _calcFines();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _calcFines() {
    double total = 0;
    final now = DateTime.now();
    for (final b in _borrowed) {
      final due = b['due_date'] != null ? DateTime.tryParse(b['due_date']) : null;
      if (due != null && now.isAfter(due)) {
        total += now.difference(due).inDays * 5.0;
      }
    }
    if (mounted) setState(() => _totalFine = total);
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) { setState(() => _searchResults = []); return; }
    setState(() => _searching = true);
    try {
      final res = await SupabaseConfig.client
          .from('books').select()
          .or('title.ilike.%$q%,author.ilike.%$q%,isbn.ilike.%$q%') as List;
      if (mounted) setState(() => _searchResults = res.cast());
    } catch (_) {}
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _renew(String borrowId, String bookId) async {
    try {
      final newDue = DateTime.now().add(const Duration(days: 14));
      await SupabaseConfig.client.from('borrowed_books').update({
        'due_date': newDue.toIso8601String().substring(0, 10),
        'renewals_count': 1,
      }).eq('id', borrowId);
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Book renewed for 14 days ✓'),
              backgroundColor: AppColors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: AfosAppBar(title: 'Library'),
      body: Column(children: [
        Container(color: AppColors.surfaceOf(context), child: TabBar(
            controller: _tab,
            labelColor: AppColors.holoviolet,
            unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.holoviolet,
            tabs: const [Tab(text: 'Borrowed'), Tab(text: 'Search')])),
        Expanded(child: TabBarView(controller: _tab, children: [
          _BorrowedTab(borrowed: _borrowed, fine: _totalFine,
              loading: _loading, onRenew: _renew, onRefresh: _load),
          _SearchTab(ctrl: _searchCtrl, results: _searchResults,
              searching: _searching, onSearch: _search),
        ])),
      ]),
    );
  }
}

class _BorrowedTab extends StatelessWidget {
  final List<Map<String, dynamic>> borrowed;
  final double fine; final bool loading;
  final Future<void> Function(String, String) onRenew;
  final VoidCallback onRefresh;
  const _BorrowedTab({required this.borrowed, required this.fine,
      required this.loading, required this.onRenew, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppColors.holoviolet,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (fine > 0) RepaintBoundary(
          child: Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: AppColors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.red.withOpacity(0.3))),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.red),
              const SizedBox(width: 10),
              Text('Outstanding Fine: ৳${fine.toStringAsFixed(2)}',
                  style: AppTextStyles.titleLarge.copyWith(color: AppColors.red)),
            ]),
          ),
        ),
        if (borrowed.isEmpty) ...[
          const SizedBox(height: 40),
          EmptyState(icon: AppIcons.library,
              title: 'No books borrowed', subtitle: 'Search the catalogue to borrow'),
        ] else
          ...borrowed.asMap().entries.map((e) => _BookCard(
              borrow: e.value, index: e.key, onRenew: onRenew)),
      ]),
    );
  }
}

class _BookCard extends StatelessWidget {
  final Map<String, dynamic> borrow; final int index;
  final Future<void> Function(String, String) onRenew;
  const _BookCard({required this.borrow, required this.index, required this.onRenew});

  @override
  Widget build(BuildContext context) {
    final book = borrow['books'] as Map<String, dynamic>? ?? {};
    final dueDate = borrow['due_date'] != null ? DateTime.tryParse(borrow['due_date']) : null;
    final now = DateTime.now();
    final isOverdue = dueDate != null && now.isAfter(dueDate);
    final daysLeft = dueDate != null ? dueDate.difference(now).inDays : 0;
    final progress = dueDate != null
        ? (1 - daysLeft / 14.0).clamp(0.0, 1.0) : 0.0;
    final statusColor = isOverdue ? AppColors.red
        : daysLeft <= 3 ? AppColors.amber : AppColors.green;

    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 48, height: 64,
                decoration: BoxDecoration(
                    color: AppColors.holoviolet.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(Icons.book_rounded, color: AppColors.holoviolet, size: 28)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(book['title'] ?? 'Unknown',
                  style: AppTextStyles.titleMedium.copyWith(color: textPrimary), maxLines: 2),
              Text(book['author'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
              const SizedBox(height: 6),
              Text(isOverdue ? 'OVERDUE ${now.difference(dueDate).inDays} days'
                  : dueDate != null ? 'Due in $daysLeft days' : 'No due date',
                  style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600)),
            ])),
          ]),
          const SizedBox(height: 12),
          ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                  value: progress, minHeight: 6,
                  backgroundColor: AppColors.borderOf(context),
                  valueColor: AlwaysStoppedAnimation(statusColor))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(
                onPressed: () => onRenew(borrow['id'], borrow['book_id']),
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.holoBlue,
                    side: BorderSide(color: AppColors.holoBlue),
                    minimumSize: const Size(0, 40)),
                child: const Text('Renew'))),
            if (isOverdue) ...[
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.red, minimumSize: const Size(0, 40)),
                  child: const Text('Pay Fine'))),
            ],
          ]),
        ]),
      ),
    ).animate(delay: Duration(milliseconds: index * 80))
        .fadeIn(curve: Curves.easeOutCubic).slideY(begin: 0.05, curve: Curves.easeOutCubic);
  }
}

class _SearchTab extends StatelessWidget {
  final TextEditingController ctrl;
  final List<Map<String, dynamic>> results;
  final bool searching;
  final ValueChanged<String> onSearch;
  const _SearchTab({required this.ctrl, required this.results,
      required this.searching, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: TextField(
        controller: ctrl, onChanged: onSearch,
        style: TextStyle(color: textPrimary),
        decoration: InputDecoration(
            hintText: 'Search by title, author or ISBN',
            prefixIcon: Icon(Icons.search, color: textSecondary, size: 20),
            suffixIcon: ctrl.text.isNotEmpty
                ? IconButton(icon: Icon(Icons.clear, size: 18, color: textSecondary),
                    onPressed: () { ctrl.clear(); onSearch(''); }) : null,
            filled: true, fillColor: AppColors.glassFill(context),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.glassBorder(context), width: 0.5)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.glassBorder(context), width: 0.5)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.holoviolet, width: 1))),
      )),
      if (searching) LinearProgressIndicator(
          color: AppColors.holoviolet, backgroundColor: AppColors.borderOf(context)),
      Expanded(child: results.isEmpty && ctrl.text.isNotEmpty && !searching
          ? EmptyState(icon: Icons.search_off_rounded, title: 'No results',
              subtitle: 'Try a different search term')
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: results.length,
              itemBuilder: (ctx, i) {
                final b = results[i];
                final avail = (b['available_copies'] as int? ?? 0) > 0;
                return RepaintBoundary(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                    child: Row(children: [
                      Container(width: 44, height: 60,
                          decoration: BoxDecoration(color: AppColors.holoviolet.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.book_rounded, color: AppColors.holoviolet, size: 24)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b['title'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: textPrimary), maxLines: 2),
                        Text(b['author'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: (avail ? AppColors.green : AppColors.red).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(avail ? 'Available' : 'Checked Out',
                              style: TextStyle(color: avail ? AppColors.green : AppColors.red,
                                  fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ])),
                    ]),
                  ),
                );
              })),
    ]);
  }
}
