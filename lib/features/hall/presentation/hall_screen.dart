import 'package:flutter/material.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

class HallScreen extends StatefulWidget {
  const HallScreen({super.key});
  @override State<HallScreen> createState() => _HallState();
}

class _HallState extends State<HallScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  Map<String,dynamic>? _application;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final res = await SupabaseConfig.client
          .from('hall_applications').select().eq('student_id', uid).maybeSingle();
      if (mounted) setState(() => _application = res);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: 'Hall Allocation'),
      body: Column(children: [
        Container(
          color: AppColors.surfaceOf(context),
          child: TabBar(
              controller: _tab,
              labelColor: AppColors.blue,
              unselectedLabelColor: AppColors.textSecondaryOf(context),
              indicatorColor: AppColors.blue,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [Tab(text: 'My Application'), Tab(text: 'Apply'), Tab(text: 'Complaints')])),
        Expanded(child: TabBarView(controller: _tab, children: [
          _loading
              ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _MyApplicationTab(app: _application, onRefresh: _load),
          _ApplyTab(onApplied: () { _load(); _tab.animateTo(0); }),
          const _ComplaintsTab(),
        ])),
      ]),
    );
  }
}

// ─── My Application Tab ───────────────────────────────────────────────────────
class _MyApplicationTab extends StatelessWidget {
  final Map<String,dynamic>? app; final VoidCallback onRefresh;
  const _MyApplicationTab({this.app, required this.onRefresh});

  static const _steps = ['Submitted', 'Under Review', 'Decision'];

  @override
  Widget build(BuildContext context) {
    if (app == null) return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 40),
        Icon(Icons.apartment_outlined, color: AppColors.textMutedOf(context), size: 64),
        const SizedBox(height: 16),
        Text('No Application Yet', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(context))),
        const SizedBox(height: 8),
        Text('Apply for a hall seat from the Apply tab',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)), textAlign: TextAlign.center),
      ]));

    final status    = app!['status'] as String? ?? 'pending';

    if (status == 'cancelled') return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 40),
        Icon(Icons.cancel_outlined, color: AppColors.textMutedOf(context), size: 64),
        const SizedBox(height: 16),
        Text('Application Cancelled', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(context))),
        const SizedBox(height: 8),
        Text('You can submit a new application from the Apply tab',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)), textAlign: TextAlign.center),
      ]));

    final stepIndex = {'pending': 0, 'reviewing': 1, 'approved': 2, 'rejected': 2}[status] ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Application Status', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(context))),
        const SizedBox(height: 20),
        ...List.generate(_steps.length, (i) {
          final done  = i <= stepIndex;
          final isLast = i == _steps.length - 1;
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Column(children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? AppColors.green : AppColors.surfaceOf(context),
                    border: Border.all(color: done ? AppColors.green : AppColors.borderOf(context))),
                child: Center(child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text('${i+1}', style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12)))),
              if (!isLast) Container(width: 2, height: 40,
                  color: i < stepIndex ? AppColors.green : AppColors.borderOf(context)),
            ]),
            const SizedBox(width: 14),
            Expanded(child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_steps[i], style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                if (i == stepIndex) Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                      status == 'approved' ? 'Approved ✓'
                      : status == 'rejected' ? 'Rejected' : 'In progress',
                      style: TextStyle(
                          color: status == 'rejected' ? AppColors.red : AppColors.green,
                          fontSize: 12))),
                SizedBox(height: isLast ? 0 : 28),
              ]))),
          ]);
        }),

        if (status == 'approved') ...[
          const SizedBox(height: 20),
          RepaintBoundary(
            child: GlassCard(
              glowColor: AppColors.green,
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.apartment, color: AppColors.green),
                  const SizedBox(width: 8),
                  Text('Your Room', style: AppTextStyles.titleLarge.copyWith(color: AppColors.green)),
                ]),
                const SizedBox(height: 12),
                _InfoRow('Room',     app!['assigned_room'] ?? '-'),
                _InfoRow('Floor',    '${app!['assigned_floor'] ?? '-'}'),
                _InfoRow('Building', app!['assigned_building'] ?? '-'),
              ]),
            ),
          ),
        ],

        if (status == 'rejected') ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppColors.red.withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.red.withAlpha(76))),
            child: Text('Reason: ${app!['rejection_reason'] ?? 'Not specified'}',
                style: const TextStyle(color: AppColors.red))),
        ],

        if (status == 'pending' || status == 'reviewing') ...[
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.red, side: const BorderSide(color: AppColors.red)),
            onPressed: () => _cancelApplication(context),
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Cancel Application'))),
        ],
      ]),
    );
  }

  Future<void> _cancelApplication(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(dialogCtx),
        title: Text('Cancel application?', style: TextStyle(color: AppColors.textPrimaryOf(dialogCtx))),
        content: Text('This will withdraw your pending hall application. You can apply again afterward.',
            style: TextStyle(color: AppColors.textSecondaryOf(dialogCtx))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Keep it')),
          TextButton(onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Cancel Application', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await SupabaseConfig.client.from('hall_applications')
          .update({'status': 'cancelled'}).eq('id', app!['id']);
      onRefresh();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.red));
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)))),
      Expanded(child: Text(value, style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]));
}

// ─── Apply Tab ────────────────────────────────────────────────────────────────
class _ApplyTab extends StatefulWidget {
  final VoidCallback onApplied;
  const _ApplyTab({required this.onApplied});
  @override State<_ApplyTab> createState() => _ApplyTabState();
}

class _ApplyTabState extends State<_ApplyTab> {
  final _formKey   = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController();
  String _hall = 'Ahsanullah Hall';
  String _pref = 'Shared';
  bool   _loading = false;

  @override
  void dispose() { _reasonCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await SupabaseConfig.client.from('hall_applications').insert({
        'student_id': SupabaseConfig.uid, 'preferred_hall': _hall,
        'preference': _pref, 'reason': _reasonCtrl.text.trim(), 'status': 'pending',
      });
      _formKey.currentState!.reset();
      _reasonCtrl.clear();
      if (mounted) setState(() { _hall = 'Ahsanullah Hall'; _pref = 'Shared'; });
      widget.onApplied();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Apply for Hall Seat', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(context))),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            value: _hall,
            decoration: InputDecoration(
                labelText: 'Preferred Hall', filled: true, fillColor: AppColors.surfaceOf(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.borderOf(context)))),
            dropdownColor: AppColors.surfaceOf(context),
            style: TextStyle(color: AppColors.textPrimaryOf(context)),
            items: ['Ahsanullah Hall', 'Bangabandhu Hall', 'Pritilata Hall', 'Sheikh Hasina Hall']
                .map((h) => DropdownMenuItem(value: h, child: Text(h))).toList(),
            onChanged: (v) => setState(() => _hall = v!),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: _PrefChip('Single', _pref, (v) => setState(() => _pref = v))),
            const SizedBox(width: 12),
            Expanded(child: _PrefChip('Shared', _pref, (v) => setState(() => _pref = v))),
          ]),
          const SizedBox(height: 16),
          AfosTextField(
            hint: 'Reason for applying...',
            controller: _reasonCtrl,
            maxLines: 3,
            validator: (v) => v == null || v.isEmpty ? 'Reason required' : null,
          ),
          const SizedBox(height: 24),
          AfosButton(label: 'Submit Application', loading: _loading, onTap: _submit),
        ]),
      ),
    );
  }
}

class _PrefChip extends StatelessWidget {
  final String label, selected; final ValueChanged<String> onTap;
  const _PrefChip(this.label, this.selected, this.onTap);
  @override
  Widget build(BuildContext context) {
    final sel = selected == label;
    return GestureDetector(
      onTap: () => onTap(label),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
            color: sel ? AppColors.blue : AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? AppColors.blue : AppColors.borderOf(context))),
        child: Center(child: Text(label, style: TextStyle(
            color: sel ? Colors.white : AppColors.textSecondaryOf(context),
            fontWeight: FontWeight.w600)))));
  }
}

class _ComplaintsTab extends StatefulWidget {
  const _ComplaintsTab();
  @override State<_ComplaintsTab> createState() => _ComplaintsTabState();
}

class _ComplaintsTabState extends State<_ComplaintsTab> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  String _category = 'Food';
  bool _loading = false;
  List<Map<String, dynamic>> _complaints = [];
  bool _listLoading = true;

  static const _categories = ['Food', 'Washroom', 'Maintenance', 'Security', 'Other'];

  @override
  void initState() { super.initState(); _loadMine(); }

  @override
  void dispose() { _descCtrl.dispose(); super.dispose(); }

  Future<void> _loadMine() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _listLoading = false); return; }
    try {
      final res = await SupabaseConfig.client.from('hall_complaints')
          .select().eq('student_id', uid).order('created_at', ascending: false) as List;
      if (mounted) setState(() { _complaints = res.cast(); _listLoading = false; });
    } catch (_) { if (mounted) setState(() => _listLoading = false); }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await SupabaseConfig.client.from('hall_complaints').insert({
        'student_id': SupabaseConfig.uid,
        'category': _category,
        'description': _descCtrl.text.trim(),
        'status': 'open',
      });
      _descCtrl.clear();
      _formKey.currentState!.reset();
      if (mounted) setState(() => _category = 'Food');
      await _loadMine();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _loading = false);
  }

  Color _statusColor(String s) => switch (s) {
        'resolved' => AppColors.green,
        'dismissed' => AppColors.textSecondary,
        'in_progress' => AppColors.amber,
        _ => AppColors.blue,
      };

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Submit a Complaint', style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: InputDecoration(
                labelText: 'Category', filled: true, fillColor: AppColors.surfaceOf(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.borderOf(context)))),
            dropdownColor: AppColors.surfaceOf(context),
            style: TextStyle(color: textPrimary),
            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 16),
          AfosTextField(
            hint: 'Describe the issue...',
            controller: _descCtrl,
            maxLines: 3,
            validator: (v) => v == null || v.isEmpty ? 'Description required' : null,
          ),
          const SizedBox(height: 20),
          AfosButton(label: 'Submit Complaint', loading: _loading, onTap: _submit),
          const SizedBox(height: 28),
          Text('My Complaints', style: AppTextStyles.titleLarge.copyWith(color: textPrimary)),
          const SizedBox(height: 12),
          if (_listLoading)
            const Padding(padding: EdgeInsets.only(top: 8), child: ShimmerList(count: 2))
          else if (_complaints.isEmpty)
            Text('No complaints filed yet', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary))
          else
            ...List.generate(_complaints.length, (i) {
              final c = _complaints[i];
              final status = c['status'] as String? ?? 'open';
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(c['category'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: textPrimary))),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                        child: Text(status.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.w700))),
                  ]),
                  const SizedBox(height: 4),
                  Text(c['description'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                  if ((c['resolution'] as String?)?.isNotEmpty ?? false)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text('Response: ${c['resolution']}',
                        style: TextStyle(color: AppColors.green, fontSize: 12))),
                ]),
              );
            }),
        ]),
      ),
    );
  }
}
