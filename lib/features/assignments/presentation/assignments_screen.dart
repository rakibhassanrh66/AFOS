import 'package:flutter/material.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../grades/data/repositories/grades_repository.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/assignments_repository.dart';

class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({super.key});
  @override State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen> {
  final _repo = AssignmentsRepository();
  bool get _isTeacher => RoleSession.role == 'teacher';
  bool get _isSuperAdmin => RoleSession.role == 'super_admin';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: 'Assignments', actions: _isTeacher
          ? [IconButton(icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () => _openCreate(context))]
          : null),
      body: _isTeacher
          ? _TeacherAssignmentsTab(repo: _repo)
          : _isSuperAdmin
              ? _ObserveTab()
              : _StudentAssignmentsTab(repo: _repo),
    );
  }

  void _openCreate(BuildContext context) {
    showModalBottomSheet(context: context, isScrollControlled: true,
        backgroundColor: AppColors.surfaceOf(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetCtx) => _CreateAssignmentSheet(repo: _repo, onCreated: () => setState(() {})));
  }
}

class _CreateAssignmentSheet extends StatefulWidget {
  final AssignmentsRepository repo; final VoidCallback onCreated;
  const _CreateAssignmentSheet({required this.repo, required this.onCreated});
  @override State<_CreateAssignmentSheet> createState() => _CreateAssignmentSheetState();
}

class _CreateAssignmentSheetState extends State<_CreateAssignmentSheet> {
  final _gradesRepo = GradesRepository();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  List<Map<String, String>> _sections = [];
  Map<String, String>? _selectedSection;
  DateTime? _deadline;
  bool _loading = true, _saving = false;

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    final profile = await SupabaseConfig.client.from('profiles').select('teacher_initial').eq('id', uid).maybeSingle();
    final initial = profile?['teacher_initial'] as String?;
    if (initial != null && initial.isNotEmpty) {
      _sections = await _gradesRepo.getMyTaughtSections(initial);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 7)),
        firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 23, minute: 59));
    if (time == null) return;
    setState(() => _deadline = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (_selectedSection == null || _titleCtrl.text.trim().isEmpty || _deadline == null) return;
    setState(() => _saving = true);
    try {
      final deptRow = await SupabaseConfig.client.from('departments').select('id').eq('code', _selectedSection!['department']!).maybeSingle();
      await widget.repo.createAssignment(
        departmentId: deptRow?['id'] as String,
        departmentCode: _selectedSection!['department']!,
        batch: _selectedSection!['batch']!,
        section: _selectedSection!['section']!,
        semester: int.tryParse(_selectedSection!['semester'] ?? '') ?? 1,
        courseCode: _selectedSection!['subjectCode']!,
        courseTitle: _selectedSection!['subject']!,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        deadline: _deadline!,
      );
      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('New Assignment', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(context))),
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator())
          else if (_sections.isEmpty)
            Text('No classes found — set your teacher initials in Settings first.',
                style: TextStyle(color: AppColors.textSecondaryOf(context)))
          else ...[
            DropdownButtonFormField<Map<String, String>>(
                initialValue: _selectedSection, isExpanded: true,
                decoration: const InputDecoration(hintText: 'Class'),
                items: _sections.map((s) => DropdownMenuItem(value: s,
                    child: Text('${s['subjectCode']} — Batch ${s['batch']} Sec ${s['section']}'))).toList(),
                onChanged: (v) => setState(() => _selectedSection = v)),
            const SizedBox(height: 12),
            AfosTextField(hint: 'Title', controller: _titleCtrl),
            const SizedBox(height: 12),
            AfosTextField(hint: 'Description / question', controller: _descCtrl, maxLines: 3),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: _pickDeadline, icon: const Icon(Icons.event_outlined),
                label: Text(_deadline == null ? 'Pick deadline' : AppFormatters.dateTime(_deadline!))),
            const SizedBox(height: 20),
            AfosButton(label: 'Post Assignment', loading: _saving, onTap: _submit),
          ],
        ]));
  }
}

class _TeacherAssignmentsTab extends StatefulWidget {
  final AssignmentsRepository repo;
  const _TeacherAssignmentsTab({required this.repo});
  @override State<_TeacherAssignmentsTab> createState() => _TeacherAssignmentsTabState();
}

class _TeacherAssignmentsTabState extends State<_TeacherAssignmentsTab> {
  List<Map<String, dynamic>> _assignments = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final res = await widget.repo.getMyAssignments();
    if (mounted) setState(() { _assignments = res; _loading = false; });
  }

  Future<void> _delete(String id) async {
    try {
      await widget.repo.deleteAssignment(id);
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_assignments.isEmpty) return EmptyState(icon: AppIcons.assignments,
        title: 'No assignments yet', subtitle: 'Tap + to post one to a class you teach');
    return RefreshIndicator(onRefresh: _load, color: AppColors.blue,
        child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: _assignments.length,
            itemBuilder: (ctx, i) {
              final a = _assignments[i];
              final deadline = DateTime.tryParse(a['deadline'] ?? '');
              final expired = deadline != null && deadline.isBefore(DateTime.now());
              final count = ((a['assignment_submissions'] as List?)?.firstOrNull as Map?)?['count'] ?? 0;
              return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(a['title'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context)))),
                      if (!expired) IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.red),
                          onPressed: () => _delete(a['id'])),
                    ]),
                    Text('${a['course_code']} · Batch ${a['batch']} Sec ${a['section']}',
                        style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
                    const SizedBox(height: 6),
                    Text('$count submission(s) · ${expired ? "Closed" : "Due"} ${deadline != null ? AppFormatters.dateTime(deadline) : ''}',
                        style: TextStyle(color: expired ? AppColors.red : AppColors.green, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]));
            }));
  }
}

class _StudentAssignmentsTab extends StatefulWidget {
  final AssignmentsRepository repo;
  const _StudentAssignmentsTab({required this.repo});
  @override State<_StudentAssignmentsTab> createState() => _StudentAssignmentsTabState();
}

class _StudentAssignmentsTabState extends State<_StudentAssignmentsTab> {
  List<Map<String, dynamic>> _assignments = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final res = await widget.repo.getMyClassAssignments();
    if (mounted) setState(() { _assignments = res; _loading = false; });
  }

  Future<void> _submit(BuildContext context, Map<String, dynamic> a) async {
    final ctrl = TextEditingController();
    await showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: AppColors.surfaceOf(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetCtx) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Submit: ${a['title']}', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 16),
              AfosTextField(hint: 'Your answer / notes', controller: ctrl, maxLines: 5),
              const SizedBox(height: 20),
              AfosButton(label: 'Submit', onTap: () async {
                if (ctrl.text.trim().isEmpty) return;
                Navigator.pop(sheetCtx);
                await widget.repo.submitAssignment(a['id'], ctrl.text.trim());
                _load();
              }),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_assignments.isEmpty) return EmptyState(icon: AppIcons.assignments,
        title: 'No assignments yet', subtitle: 'Assignments from your teachers will show up here');
    return RefreshIndicator(onRefresh: _load, color: AppColors.blue,
        child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: _assignments.length,
            itemBuilder: (ctx, i) {
              final a = _assignments[i];
              final deadline = DateTime.tryParse(a['deadline'] ?? '');
              final expired = deadline != null && deadline.isBefore(DateTime.now());
              final submitted = a['has_submitted'] == true;
              return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a['title'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                    Text('${a['course_code']} · ${a['course_title'] ?? ''}',
                        style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
                    const SizedBox(height: 6),
                    if ((a['description'] as String?)?.isNotEmpty == true)
                      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(a['description'],
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)))),
                    Text(submitted ? 'Submitted ✓' : expired ? 'Deadline passed' : 'Due ${deadline != null ? AppFormatters.dateTime(deadline) : ''}',
                        style: TextStyle(color: submitted ? AppColors.green : expired ? AppColors.red : AppColors.amber,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    if (!submitted && !expired) Padding(padding: const EdgeInsets.only(top: 8),
                        child: SizedBox(width: double.infinity, child: OutlinedButton(
                            onPressed: () => _submit(context, a), child: const Text('Submit')))),
                  ]));
            }));
  }
}

class _ObserveTab extends StatefulWidget {
  @override State<_ObserveTab> createState() => _ObserveTabState();
}

class _ObserveTabState extends State<_ObserveTab> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final res = await SupabaseConfig.client.from('assignments')
        .select('*, profiles!teacher_id(full_name)').order('deadline', ascending: false) as List;
    if (mounted) setState(() { _all = res.cast(); _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_all.isEmpty) return EmptyState(icon: AppIcons.assignments, title: 'No assignments yet', subtitle: 'System-wide assignments will show up here');
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: _all.length,
        itemBuilder: (ctx, i) {
          final a = _all[i];
          final teacher = a['profiles'] as Map<String, dynamic>? ?? {};
          return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a['title'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                Text('${a['course_code']} · Batch ${a['batch']} Sec ${a['section']} · by ${teacher['full_name'] ?? 'Unknown'}',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
              ]));
        });
  }
}
