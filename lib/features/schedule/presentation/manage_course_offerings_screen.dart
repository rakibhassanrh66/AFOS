import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_bottom_nav.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/course_offering_repository.dart';

const _dayLabels = ['Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri'];

Color _statusColor(String s) => switch (s) {
  'approved' => AppColors.green, 'rejected' => AppColors.red, _ => AppColors.amber,
};

/// Teacher-facing: self-declare a course offering (admin-approved before it
/// goes live on the schedule) and review incoming student join requests for
/// offerings already approved.
class ManageCourseOfferingsScreen extends StatefulWidget {
  const ManageCourseOfferingsScreen({super.key});
  @override State<ManageCourseOfferingsScreen> createState() => _ManageCourseOfferingsScreenState();
}

class _ManageCourseOfferingsScreenState extends State<ManageCourseOfferingsScreen> with SingleTickerProviderStateMixin {
  final _repo = CourseOfferingRepository();
  late final TabController _tab = TabController(length: 2, vsync: this);
  List<Map<String, dynamic>> _offerings = [], _joinRequests = [];
  String _myDepartment = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = SupabaseConfig.uid;
      final results = await Future.wait([
        SupabaseConfig.client.from('profiles').select('department').eq('id', uid ?? '').maybeSingle() as Future,
        _repo.fetchMyOfferings(),
        _repo.fetchOfferingJoinRequests(),
      ]);
      if (mounted) {
        setState(() {
          _myDepartment = (results[0] as Map?)?['department'] as String? ?? '';
          _offerings = results[1] as List<Map<String, dynamic>>;
          _joinRequests = results[2] as List<Map<String, dynamic>>;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final pendingRequests = _joinRequests.where((r) => r['status'] == 'pending').length;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'My Course Offerings'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSheet(context),
        backgroundColor: AppColors.blue,
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text('New Offering', style: TextStyle(color: Colors.white)),
      ),
      body: Column(children: [
        FeatureHeader(
          title: 'Course Offerings',
          subtitle: _loading ? 'Loading…' : '${_offerings.length} offerings · $pendingRequests join requests',
          icon: AppIcons.schedule,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.blueLight, AppColors.blue]),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.06, curve: Curves.easeOutCubic),
        AnimatedBuilder(
          animation: _tab,
          builder: (ctx, _) => GlassTabBar(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            currentIndex: _tab.index,
            onChanged: (i) => setState(() => _tab.animateTo(i)),
            tabs: [
              const GlassTab('My Offerings', icon: Icons.menu_book_rounded),
              const GlassTab('Join Requests', icon: Icons.how_to_reg_rounded),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(child: _error != null
            ? _errorView(context)
            : TabBarView(controller: _tab, children: [
                _loading ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
                    : _OfferingsTab(offerings: _offerings, onWithdraw: _withdraw),
                _loading ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
                    : _JoinRequestsTab(requests: _joinRequests, onRespond: _respondToJoin),
              ])),
      ]),
    );
  }

  Widget _errorView(BuildContext context) => Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.error_outline_rounded, color: AppColors.red, size: 40),
        const SizedBox(height: 12),
        Text('Couldn\'t load: $_error', textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 12),
        TextButton(onPressed: _load, child: const Text('Retry')),
      ])));

  Future<void> _withdraw(String offeringId) async {
    try {
      await _repo.withdrawOffering(offeringId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _respondToJoin(Map<String, dynamic> request, bool approve) async {
    try {
      if (approve) {
        await _repo.approveJoin(request['id'] as String);
      } else {
        await _repo.rejectJoin(request['id'] as String);
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  void _showCreateSheet(BuildContext context) {
    showGlassSheet(context, child: _CreateOfferingForm(
      repo: _repo,
      myDepartment: _myDepartment,
      onCreated: () { Navigator.pop(context); _load(); },
    ));
  }
}

class _OfferingsTab extends StatelessWidget {
  final List<Map<String, dynamic>> offerings;
  final ValueChanged<String> onWithdraw;
  const _OfferingsTab({required this.offerings, required this.onWithdraw});

  @override
  Widget build(BuildContext context) {
    if (offerings.isEmpty) {
      return const EmptyState(icon: Icons.menu_book_outlined,
          title: 'No offerings yet', subtitle: 'Tap "New Offering" to declare a course you teach');
    }
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16 + GlassBottomNav.navContentClearance),
        itemCount: offerings.length,
        itemBuilder: (ctx, i) {
          final o = offerings[i];
          final course = o['courses'] as Map<String, dynamic>? ?? {};
          final status = o['status'] as String? ?? 'pending';
          final day = o['day_of_week'] as int?;
          final start = (o['start_time'] as String?)?.substring(0, 5) ?? '';
          final end = (o['end_time'] as String?)?.substring(0, 5) ?? '';
          return Container(
              margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('${course['code'] ?? '—'} · ${course['title'] ?? ''}',
                      style: AppTextStyles.titleMedium.copyWith(color: textPrimary),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Text(status.toUpperCase(), style: TextStyle(color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 6),
                Text('Batch ${o['batch']} · Section ${o['section']} · Sem ${o['semester']}',
                    style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                if (day != null && day >= 0 && day < 7)
                  Text('${_dayLabels[day]} $start–$end · ${o['building'] ?? ''} ${o['room_number'] ?? ''}',
                      style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                if (status == 'rejected' && (o['rejection_reason'] as String?)?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text('Reason: ${o['rejection_reason']}', style: const TextStyle(color: AppColors.red, fontSize: 12)),
                ],
                if (status == 'pending') ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: TextButton(
                      onPressed: () => onWithdraw(o['id'] as String),
                      child: const Text('Withdraw', style: TextStyle(fontSize: 12, color: AppColors.red)))),
                ],
              ])).animate(delay: Duration(milliseconds: i * 60)).fadeIn().slideY(begin: 0.05);
        });
  }
}

class _JoinRequestsTab extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  final void Function(Map<String, dynamic> request, bool approve) onRespond;
  const _JoinRequestsTab({required this.requests, required this.onRespond});

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return const EmptyState(icon: Icons.how_to_reg_outlined,
          title: 'No join requests yet', subtitle: 'Students requesting to join your offerings show up here');
    }
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16 + GlassBottomNav.navContentClearance),
        itemCount: requests.length,
        itemBuilder: (ctx, i) {
          final r = requests[i];
          final student = r['profiles'] as Map<String, dynamic>? ?? {};
          final offering = r['course_offerings'] as Map<String, dynamic>? ?? {};
          final course = offering['courses'] as Map<String, dynamic>? ?? {};
          final status = r['status'] as String? ?? 'pending';
          return Container(
              margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(student['full_name'] as String? ?? 'Student',
                      style: AppTextStyles.titleMedium.copyWith(color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _statusColor(status).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                      child: Text(status.toUpperCase(), style: TextStyle(color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 4),
                Text('wants to join ${course['code'] ?? ''} · Section ${offering['section'] ?? ''}',
                    style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                if ((student['batch'] as String?)?.isNotEmpty == true)
                  Text('Their batch/section: ${student['batch']}/${student['section'] ?? ''}',
                      style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
                if (status == 'pending') ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    TextButton(onPressed: () => onRespond(r, true),
                        child: const Text('Accept', style: TextStyle(fontSize: 12, color: AppColors.green))),
                    TextButton(onPressed: () => onRespond(r, false),
                        child: const Text('Decline', style: TextStyle(fontSize: 12, color: AppColors.red))),
                  ]),
                ],
              ])).animate(delay: Duration(milliseconds: i * 60)).fadeIn().slideY(begin: 0.05);
        });
  }
}

class _CreateOfferingForm extends StatefulWidget {
  final CourseOfferingRepository repo;
  final String myDepartment;
  final VoidCallback onCreated;
  const _CreateOfferingForm({required this.repo, required this.myDepartment, required this.onCreated});
  @override State<_CreateOfferingForm> createState() => _CreateOfferingFormState();
}

class _CreateOfferingFormState extends State<_CreateOfferingForm> {
  final _codeCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _creditsCtrl = TextEditingController(text: '3');
  final _sectionCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();
  final _semesterCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  String _courseType = 'theory';
  int _day = 2; // Monday
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 9, minute: 30);
  List<Map<String, dynamic>> _suggestions = [];
  bool _saving = false;

  @override
  void dispose() {
    _codeCtrl.dispose(); _titleCtrl.dispose(); _creditsCtrl.dispose();
    _sectionCtrl.dispose(); _batchCtrl.dispose(); _semesterCtrl.dispose();
    _roomCtrl.dispose(); _buildingCtrl.dispose();
    super.dispose();
  }

  Future<void> _searchCourses(String q) async {
    final res = await widget.repo.searchCourses(q);
    if (mounted) setState(() => _suggestions = res);
  }

  void _pickSuggestion(Map<String, dynamic> c) {
    setState(() {
      _codeCtrl.text = c['code'] as String? ?? '';
      _titleCtrl.text = c['title'] as String? ?? '';
      _creditsCtrl.text = '${c['credit_hours'] ?? 3}';
      _courseType = c['course_type'] as String? ?? 'theory';
      _suggestions = [];
    });
  }

  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _submit() async {
    if (_codeCtrl.text.trim().isEmpty || _titleCtrl.text.trim().isEmpty ||
        _sectionCtrl.text.trim().isEmpty || _batchCtrl.text.trim().isEmpty ||
        _semesterCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fill in course code, title, section, batch and semester'), backgroundColor: AppColors.amber));
      return;
    }
    final semester = int.tryParse(_semesterCtrl.text.trim());
    if (semester == null || semester < 1 || semester > 12) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Semester must be a number between 1 and 12'), backgroundColor: AppColors.amber));
      return;
    }
    setState(() => _saving = true);
    try {
      final courseId = await widget.repo.resolveOrCreateCourse(
        code: _codeCtrl.text.trim().toUpperCase(),
        title: _titleCtrl.text.trim(),
        creditHours: int.tryParse(_creditsCtrl.text.trim()) ?? 3,
        courseType: _courseType,
      );
      await widget.repo.createOffering(
        courseId: courseId,
        section: _sectionCtrl.text.trim(),
        department: widget.myDepartment,
        batch: _batchCtrl.text.trim(),
        semester: semester,
        dayOfWeek: _day,
        startTime: _fmtTime(_start),
        endTime: _fmtTime(_end),
        roomNumber: _roomCtrl.text.trim(),
        building: _buildingCtrl.text.trim(),
      );
      widget.onCreated();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Submitted for admin approval ✓'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(context: context, initialTime: isStart ? _start : _end);
    if (picked != null) setState(() { if (isStart) { _start = picked; } else { _end = picked; } });
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('New Course Offering', style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
          const SizedBox(height: 4),
          Text('Sent to admin for approval before it appears on the schedule',
              style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
          const SizedBox(height: 18),
          AfosTextField(hint: 'Course code (e.g. CSE431)', controller: _codeCtrl, onChanged: _searchCourses),
          if (_suggestions.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: _suggestions.map((c) =>
                  ActionChip(
                    label: Text('${c['code']} · ${c['title']}', style: const TextStyle(fontSize: 11)),
                    onPressed: () => _pickSuggestion(c),
                  )).toList())),
          const SizedBox(height: 12),
          AfosTextField(hint: 'Course title', controller: _titleCtrl),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: AfosTextField(hint: 'Credit hours', controller: _creditsCtrl, keyboardType: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: _courseType,
              items: const [DropdownMenuItem(value: 'theory', child: Text('Theory')), DropdownMenuItem(value: 'lab', child: Text('Lab'))],
              onChanged: (v) => setState(() => _courseType = v ?? 'theory'),
            )),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: AfosTextField(hint: 'Batch (e.g. 63)', controller: _batchCtrl)),
            const SizedBox(width: 10),
            Expanded(child: AfosTextField(hint: 'Section (e.g. A)', controller: _sectionCtrl)),
          ]),
          const SizedBox(height: 12),
          AfosTextField(hint: 'Semester (1-12)', controller: _semesterCtrl, keyboardType: TextInputType.number),
          const SizedBox(height: 12),
          Text('Day of week', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: List.generate(_dayLabels.length, (i) => ChoiceChip(
              label: Text(_dayLabels[i]), selected: _day == i,
              onSelected: (_) => setState(() => _day = i)))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _pickTime(true),
                child: Text('Start ${_start.format(context)}'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton(onPressed: () => _pickTime(false),
                child: Text('End ${_end.format(context)}'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: AfosTextField(hint: 'Building', controller: _buildingCtrl)),
            const SizedBox(width: 10),
            Expanded(child: AfosTextField(hint: 'Room number', controller: _roomCtrl)),
          ]),
          const SizedBox(height: 20),
          AfosButton(label: 'Submit for Approval', loading: _saving, onTap: _submit),
        ]));
  }
}
