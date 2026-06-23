import 'package:flutter/material.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/widgets/afos_button.dart';
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
      backgroundColor: AppColors.background,
      appBar: AfosAppBar(title: 'Hall Allocation'),
      body: Column(children: [
        Container(
          color: AppColors.surface,
          child: TabBar(
              controller: _tab,
              labelColor: AppColors.blue,
              unselectedLabelColor: AppColors.textSecondary,
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
        const Icon(Icons.apartment_outlined, color: AppColors.textMuted, size: 64),
        const SizedBox(height: 16),
        Text('No Application Yet', style: AppTextStyles.headlineLarge),
        const SizedBox(height: 8),
        Text('Apply for a hall seat from the Apply tab',
            style: AppTextStyles.bodyMedium, textAlign: TextAlign.center),
      ]));

    final status    = app!['status'] as String? ?? 'pending';
    final stepIndex = {'pending': 0, 'reviewing': 1, 'approved': 2, 'rejected': 2}[status] ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Application Status', style: AppTextStyles.headlineLarge),
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
                    color: done ? AppColors.green : AppColors.card,
                    border: Border.all(color: done ? AppColors.green : AppColors.border)),
                child: Center(child: done
                    ? const Icon(Icons.check, size: 14, color: Colors.white)
                    : Text('${i+1}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)))),
              if (!isLast) Container(width: 2, height: 40,
                  color: i < stepIndex ? AppColors.green : AppColors.border),
            ]),
            const SizedBox(width: 14),
            Expanded(child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_steps[i], style: AppTextStyles.titleMedium),
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: AppColors.green.withAlpha(20),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.green.withAlpha(76))),
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
            ])),
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
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      SizedBox(width: 80, child: Text(label, style: AppTextStyles.bodyMedium)),
      Text(value, style: AppTextStyles.titleMedium),
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
          Text('Apply for Hall Seat', style: AppTextStyles.headlineLarge),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            value: _hall,
            decoration: InputDecoration(
                labelText: 'Preferred Hall', filled: true, fillColor: AppColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.border))),
            dropdownColor: AppColors.card,
            style: const TextStyle(color: AppColors.textPrimary),
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
          TextFormField(
            controller: _reasonCtrl,
            maxLines: 3,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
                hintText: 'Reason for applying...', filled: true, fillColor: AppColors.card),
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
            color: sel ? AppColors.blue : AppColors.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? AppColors.blue : AppColors.border)),
        child: Center(child: Text(label, style: TextStyle(
            color: sel ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.w600)))));
  }
}

class _ComplaintsTab extends StatelessWidget {
  const _ComplaintsTab();
  @override
  Widget build(BuildContext context) => const Center(
      child: Text('Submit complaints via hall management office.',
          style: TextStyle(color: AppColors.textSecondary)));
}
