import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
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
  String? _error;
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
    setState(() => _error = null);
    try {
      final res = await SupabaseConfig.client
          .from('borrowed_books')
          .select('*, books(*)')
          .eq('student_id', uid)
          .eq('status', 'borrowed') as List;
      if (mounted) setState(() => _borrowed = res.cast());
      _calcFines();
    } catch (e) {
      // Previously swallowed silently — a real load failure rendered
      // identically to "you have no borrowed books", same class of bug
      // already found and fixed once in Manage Hall.
      if (mounted) setState(() => _error = friendlyError(e));
    }
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
      // DIU's real library policy is a 7-day loan period for books
      // (library.daffodilvarsity.edu.bd/content/library-policy) — this
      // used to renew for 14 days, double the actual real-world policy.
      final newDue = DateTime.now().add(const Duration(days: 7));
      await SupabaseConfig.client.from('borrowed_books').update({
        'due_date': newDue.toIso8601String().substring(0, 10),
        'renewals_count': 1,
      }).eq('id', borrowId);
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Book renewed for 7 days ✓'),
              backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  static const _tabLabels = ['Borrowed', 'Search'];
  static const _tabIcons = [Icons.menu_book_rounded, Icons.search_rounded];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: const AfosAppBar(title: 'Library'),
      body: Column(children: [
        FeatureHeader(
          title: 'Library',
          subtitle: _loading ? 'Loading…' : '${_borrowed.length} book${_borrowed.length == 1 ? '' : 's'} borrowed',
          icon: Icons.local_library_rounded,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.blue, AppColors.indigo]),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          trailing: (!_loading && _totalFine > 0)
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('৳${_totalFine.toStringAsFixed(0)}', textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                        style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.0, fontWeight: FontWeight.w800)),
                    Text('fine due', textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10, height: 1.0)),
                  ]),
                )
              : null,
        ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.06, curve: Curves.easeOutCubic),
        AnimatedBuilder(
          animation: _tab,
          builder: (ctx, _) => GlassTabBar(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            currentIndex: _tab.index,
            onChanged: (i) => _tab.animateTo(i),
            tabs: [
              for (var i = 0; i < _tabLabels.length; i++)
                GlassTab(_tabLabels[i], icon: _tabIcons[i]),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: TabBarView(controller: _tab, children: [
          _BorrowedTab(borrowed: _borrowed, fine: _totalFine,
              loading: _loading, error: _error, onRenew: _renew, onRefresh: _load),
          _SearchTab(ctrl: _searchCtrl, results: _searchResults,
              searching: _searching, onSearch: _search),
        ])),
      ]),
    );
  }
}

class _BorrowedTab extends StatelessWidget {
  final List<Map<String, dynamic>> borrowed;
  final double fine; final bool loading; final String? error;
  final Future<void> Function(String, String) onRenew;
  final VoidCallback onRefresh;
  const _BorrowedTab({required this.borrowed, required this.fine,
      required this.loading, required this.error, required this.onRenew, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    if (loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 40),
        const SizedBox(height: 12),
        Text('Couldn\'t load: $error', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 12),
        TextButton(onPressed: onRefresh, child: const Text('Retry')),
      ])));
    }
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppColors.blue,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (fine > 0) RepaintBoundary(
          child: Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha:0.1), borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.red.withValues(alpha:0.3))),
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
          const EmptyState(icon: AppIcons.library,
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
        ? (1 - daysLeft / 7.0).clamp(0.0, 1.0) : 0.0;
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
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [AppColors.blue, AppColors.indigo]),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]),
                child: const Icon(Icons.book_rounded, color: Colors.white, size: 28)),
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
                    side: const BorderSide(color: AppColors.holoBlue),
                    minimumSize: const Size(0, 40)),
                child: const Text('Renew'))),
            if (isOverdue) ...[
              const SizedBox(width: 10),
              // Online fine payment isn't wired yet — shown disabled with a
              // "Coming soon" label rather than a button that silently does
              // nothing when tapped.
              Expanded(child: Tooltip(
                message: 'Online fine payment is coming soon',
                child: ElevatedButton(
                    onPressed: null,
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.red.withValues(alpha: 0.4),
                        disabledBackgroundColor: AppColors.red.withValues(alpha: 0.18),
                        disabledForegroundColor: AppColors.textSecondaryOf(context),
                        minimumSize: const Size(0, 40)),
                    child: const Text('Pay Fine · Soon',
                        maxLines: 1, overflow: TextOverflow.ellipsis)))),
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
                borderSide: const BorderSide(color: AppColors.blue, width: 1))),
      )),
      if (searching) LinearProgressIndicator(
          color: AppColors.blue, backgroundColor: AppColors.borderOf(context)),
      Expanded(child: results.isEmpty && ctrl.text.isNotEmpty && !searching
          ? const EmptyState(icon: Icons.search_off_rounded, title: 'No results',
              subtitle: 'Try a different search term')
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: results.length,
              itemBuilder: (ctx, i) {
                final b = results[i];
                final avail = (b['available_copies'] as int? ?? 0) > 0;
                return RepaintBoundary(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showBookDetail(context, b),
                      child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.surfaceOf(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                    child: Row(children: [
                      Container(width: 44, height: 60,
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                                  colors: [AppColors.blue, AppColors.indigo]),
                              borderRadius: BorderRadius.circular(9),
                              boxShadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.25), blurRadius: 6, offset: const Offset(0, 2))]),
                          child: const Icon(Icons.book_rounded, color: Colors.white, size: 24)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b['title'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: textPrimary), maxLines: 2),
                        Text(b['author'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: (avail ? AppColors.green : AppColors.red).withValues(alpha:0.12),
                              borderRadius: BorderRadius.circular(10)),
                          child: Text(avail ? 'Available' : 'Checked Out',
                              style: TextStyle(color: avail ? AppColors.green : AppColors.red,
                                  fontSize: 10, fontWeight: FontWeight.w600)),
                        ),
                      ])),
                    ]),
                      ),
                    ),
                  ),
                );
              })),
    ]);
  }

  void _showBookDetail(BuildContext context, Map<String, dynamic> book) {
    final avail = (book['available_copies'] as int? ?? 0) > 0;
    showGlassModal(context,
        builder: (sheetCtx) {
          final textPrimary = AppColors.textPrimaryOf(sheetCtx);
          final textSecondary = AppColors.textSecondaryOf(sheetCtx);
          Widget row(String label, String? value) {
            if (value == null || value.isEmpty) return const SizedBox.shrink();
            return Padding(padding: const EdgeInsets.only(bottom: 10), child: Row(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 90, child: Text(label, style: TextStyle(color: textSecondary, fontSize: 12))),
              Expanded(child: Text(value, style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w500))),
            ]));
          }
          return SafeArea(child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 64, height: 88,
                      decoration: BoxDecoration(color: AppColors.blue.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10)),
                      child: (book['cover_url'] as String?)?.isNotEmpty == true
                          ? ClipRRect(borderRadius: BorderRadius.circular(10),
                              child: Image.network(book['cover_url'] as String, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.book_rounded, color: AppColors.blue, size: 28)))
                          : const Icon(Icons.book_rounded, color: AppColors.blue, size: 28)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(book['title'] ?? '', style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
                    const SizedBox(height: 4),
                    Text(book['author'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                    const SizedBox(height: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: (avail ? AppColors.green : AppColors.red).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text(avail ? 'Available' : 'Checked Out',
                            style: TextStyle(color: avail ? AppColors.green : AppColors.red, fontSize: 11, fontWeight: FontWeight.w700))),
                  ])),
                ]),
                const SizedBox(height: 20),
                row('ISBN', book['isbn'] as String?),
                row('Publisher', book['publisher'] as String?),
                row('Year', book['year']?.toString()),
                row('Category', book['category'] as String?),
                row('Shelf', book['shelf_location'] as String?),
                row('Copies', '${book['available_copies'] ?? 0} of ${book['total_copies'] ?? 0} available'),
                if ((book['description'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text('About', style: TextStyle(color: textSecondary, fontSize: 12, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(book['description'] as String, style: TextStyle(color: textPrimary, fontSize: 13, height: 1.4)),
                ],
              ])));
        });
  }
}
