import 'package:flutter/material.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

/// Staff/admin-side book checkout — real DIU library policy requires a
/// physical sign-in/handover, so borrowing was never meant to be pure
/// student self-service. Previously there was no way for ANYONE to issue a
/// book at all (borrowed_books had zero INSERT policy, books had zero
/// write policy) — students could only search the catalogue and see
/// Available/Checked-Out status with no path to actually get a book.
class ManageLibraryScreen extends StatefulWidget {
  const ManageLibraryScreen({super.key});
  @override State<ManageLibraryScreen> createState() => _ManageLibraryState();
}

class _ManageLibraryState extends State<ManageLibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _activeBorrows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); _load(); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await SupabaseConfig.client.from('borrowed_books')
          .select('*, books(title,author), profiles!student_id(full_name,university_id)')
          .eq('status', 'borrowed').order('due_date') as List;
      if (mounted) setState(() { _activeBorrows = res.cast(); _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = friendlyError(e); _loading = false; });
    }
  }

  Future<void> _returnBook(Map<String, dynamic> borrow) async {
    try {
      // available_copies is incremented atomically by the
      // trg_adjust_book_availability DB trigger — don't also bump it here
      // (that used to be a read-then-write race between concurrent staff).
      await SupabaseConfig.client.from('borrowed_books').update({
        'status': 'returned',
        'return_date': DateTime.now().toIso8601String().substring(0, 10),
      }).eq('id', borrow['id']);
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Book returned ✓'), backgroundColor: AppColors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: 'Manage Library'),
      body: Column(children: [
        Container(color: AppColors.surfaceOf(context), child: TabBar(controller: _tab,
            labelColor: AppColors.purple, unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.purple,
            tabs: const [Tab(text: 'Issue Book'), Tab(text: 'Currently Borrowed')])),
        Expanded(child: TabBarView(controller: _tab, children: [
          _IssueBookTab(onIssued: _load),
          _loading
              ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _error != null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 40),
                      const SizedBox(height: 12),
                      Text('Couldn\'t load: $_error', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondaryOf(context))),
                      const SizedBox(height: 12),
                      TextButton(onPressed: _load, child: const Text('Retry')),
                    ])))
                  : _activeBorrows.isEmpty
                      ? EmptyState(icon: Icons.menu_book_rounded, title: 'No books currently borrowed', subtitle: 'Issued books will appear here')
                      : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _activeBorrows.length,
                          itemBuilder: (ctx, i) {
                            final b = _activeBorrows[i];
                            final book = b['books'] as Map<String, dynamic>? ?? {};
                            final student = b['profiles'] as Map<String, dynamic>? ?? {};
                            final dueDate = b['due_date'] != null ? DateTime.tryParse(b['due_date']) : null;
                            final overdue = dueDate != null && DateTime.now().isAfter(dueDate);
                            return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(book['title'] ?? 'Unknown book', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                                  Text('${student['full_name'] ?? 'Unknown'} · ${student['university_id'] ?? ''}',
                                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
                                  const SizedBox(height: 6),
                                  Text(overdue ? 'Overdue since ${b['due_date']}' : 'Due ${b['due_date']}',
                                      style: TextStyle(color: overdue ? AppColors.red : AppColors.textSecondaryOf(context), fontSize: 12, fontWeight: overdue ? FontWeight.w700 : FontWeight.w400)),
                                  const SizedBox(height: 10),
                                  SizedBox(width: double.infinity, child: OutlinedButton(
                                      onPressed: () => _returnBook(b),
                                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.green, side: const BorderSide(color: AppColors.green), minimumSize: const Size(0, 40)),
                                      child: const Text('Mark Returned'))),
                                ]));
                          }),
        ])),
      ]),
    );
  }
}

class _IssueBookTab extends StatefulWidget {
  final VoidCallback onIssued;
  const _IssueBookTab({required this.onIssued});
  @override State<_IssueBookTab> createState() => _IssueBookTabState();
}

class _IssueBookTabState extends State<_IssueBookTab> {
  final _studentCtrl = TextEditingController();
  final _bookCtrl = TextEditingController();
  List<Map<String, dynamic>> _studentResults = [], _bookResults = [];
  Map<String, dynamic>? _selectedStudent, _selectedBook;
  bool _issuing = false;

  @override
  void dispose() { _studentCtrl.dispose(); _bookCtrl.dispose(); super.dispose(); }

  Future<void> _searchStudents(String q) async {
    if (q.trim().isEmpty) { setState(() => _studentResults = []); return; }
    try {
      final res = await SupabaseConfig.client.from('profiles')
          .select('id, full_name, university_id').eq('role', 'student')
          .or('full_name.ilike.%$q%,university_id.ilike.%$q%').limit(8) as List;
      if (mounted) setState(() => _studentResults = res.cast());
    } catch (_) {}
  }

  Future<void> _searchBooks(String q) async {
    if (q.trim().isEmpty) { setState(() => _bookResults = []); return; }
    try {
      final res = await SupabaseConfig.client.from('books')
          .select('id, title, author, available_copies').gt('available_copies', 0)
          .or('title.ilike.%$q%,author.ilike.%$q%,isbn.ilike.%$q%').limit(8) as List;
      if (mounted) setState(() => _bookResults = res.cast());
    } catch (_) {}
  }

  Future<void> _issue() async {
    final student = _selectedStudent, book = _selectedBook;
    if (student == null || book == null) return;
    setState(() => _issuing = true);
    try {
      final due = DateTime.now().add(const Duration(days: 7));
      // available_copies is decremented atomically by the
      // trg_adjust_book_availability DB trigger (and the insert is refused
      // if a concurrent issue already took the last copy) — don't also
      // read-then-write the count here.
      await SupabaseConfig.client.from('borrowed_books').insert({
        'student_id': student['id'], 'book_id': book['id'],
        'borrowed_date': DateTime.now().toIso8601String().substring(0, 10),
        'due_date': due.toIso8601String().substring(0, 10),
        'status': 'borrowed',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${book['title']} issued to ${student['full_name']} ✓'), backgroundColor: AppColors.green));
        setState(() {
          _selectedStudent = null; _selectedBook = null;
          _studentCtrl.clear(); _bookCtrl.clear();
          _studentResults = []; _bookResults = [];
        });
      }
      widget.onIssued();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _issuing = false);
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Student', style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
        const SizedBox(height: 8),
        if (_selectedStudent != null)
          _SelectedChip(label: '${_selectedStudent!['full_name']} (${_selectedStudent!['university_id']})',
              onClear: () => setState(() => _selectedStudent = null))
        else ...[
          TextField(controller: _studentCtrl, onChanged: _searchStudents,
              style: TextStyle(color: textPrimary),
              decoration: InputDecoration(hintText: 'Search name or university ID', filled: true,
                  fillColor: AppColors.glassFill(context),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
          ..._studentResults.map((s) => ListTile(
              title: Text(s['full_name'] ?? '', style: TextStyle(color: textPrimary)),
              subtitle: Text(s['university_id'] ?? '', style: TextStyle(color: textSecondary)),
              onTap: () => setState(() { _selectedStudent = s; _studentResults = []; _studentCtrl.clear(); }))),
        ],
        const SizedBox(height: 20),
        Text('Book', style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
        const SizedBox(height: 8),
        if (_selectedBook != null)
          _SelectedChip(label: '${_selectedBook!['title']} (${_selectedBook!['available_copies']} left)',
              onClear: () => setState(() => _selectedBook = null))
        else ...[
          TextField(controller: _bookCtrl, onChanged: _searchBooks,
              style: TextStyle(color: textPrimary),
              decoration: InputDecoration(hintText: 'Search title, author or ISBN', filled: true,
                  fillColor: AppColors.glassFill(context),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
          ..._bookResults.map((b) => ListTile(
              title: Text(b['title'] ?? '', style: TextStyle(color: textPrimary)),
              subtitle: Text('${b['author'] ?? ''} · ${b['available_copies']} available', style: TextStyle(color: textSecondary)),
              onTap: () => setState(() { _selectedBook = b; _bookResults = []; _bookCtrl.clear(); }))),
        ],
        const SizedBox(height: 24),
        AfosButton(label: 'Issue Book (7-day loan)', loading: _issuing,
            onTap: (_selectedStudent != null && _selectedBook != null) ? _issue : () {}),
      ]),
    );
  }
}

class _SelectedChip extends StatelessWidget {
  final String label; final VoidCallback onClear;
  const _SelectedChip({required this.label, required this.onClear});
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.purple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.purple.withValues(alpha: 0.3))),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: AppColors.purple, fontWeight: FontWeight.w600))),
        IconButton(icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.purple), onPressed: onClear),
      ]));
}
