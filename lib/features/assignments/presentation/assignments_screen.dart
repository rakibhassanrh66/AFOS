import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/supernova_loader.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../grades/data/repositories/grades_repository.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/assignments_repository.dart';
import 'assignment_submissions_screen.dart';

import '../../../core/layout/nav_insets.dart';
import '../../web/presentation/widgets/adaptive_list.dart';
class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({super.key});
  @override State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen> {
  final _repo = AssignmentsRepository();
  bool get _isTeacher => RoleSession.role == 'teacher';
  bool get _isSuperAdmin => RoleSession.role == 'super_admin';
  bool get _isStudent => RoleSession.role == 'student';

  @override
  Widget build(BuildContext context) {
    final subtitle = _isTeacher ? 'Post and track assignments for your classes'
        : _isSuperAdmin ? 'System-wide assignment activity'
        : _isStudent ? 'Assignments from your teachers'
        : 'Not applicable for your role';
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: 'Assignments', actions: _isTeacher
          ? [IconButton(icon: const Icon(Icons.add_circle_outline_rounded), onPressed: () => _openCreate(context))]
          : null),
      body: Column(children: [
        FeatureHeader(
          title: 'Assignments',
          subtitle: subtitle,
          icon: AppIcons.assignments,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.blue, AppColors.indigo]),
          margin: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
        ),
        Expanded(child: _isTeacher
            ? _TeacherAssignmentsTab(repo: _repo)
            : _isSuperAdmin
                ? _ObserveTab()
                : _isStudent
                    ? _StudentAssignmentsTab(repo: _repo)
                    // admin/dept_admin/staff/exam_controller previously fell
                    // through to the student tab (always empty, confusing) —
                    // assignments are only ever relevant to students/teachers,
                    // matching schedule_screen.dart's not-applicable pattern.
                    : const EmptyState(icon: AppIcons.assignments, title: 'Not applicable for your role',
                        subtitle: 'Assignments are for students and teachers only')),
      ]),
    );
  }

  void _openCreate(BuildContext context) {
    showGlassModal(context,
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
  final _maxMarksCtrl = TextEditingController(text: '10');
  List<Map<String, String>> _sections = [];
  Map<String, String>? _selectedSection;
  DateTime? _deadline;
  bool _loading = true, _saving = false;

  @override
  void initState() { super.initState(); _init(); }

  @override
  void dispose() { _titleCtrl.dispose(); _descCtrl.dispose(); _maxMarksCtrl.dispose(); super.dispose(); }

  Future<void> _init() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    // Sourced from course_offerings.teacher_id, not the routine's scraped
    // initials — which is what previously let a teacher post an assignment to
    // a section belonging to someone who shares their initials.
    // Guarded so a failed lookup falls through to the "no approved course
    // offerings" copy below instead of leaving the sheet on its spinner.
    try {
      _sections = await _gradesRepo.getMyTaughtSections();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 7)),
        firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 23, minute: 59));
    // `!mounted` here too, not just after the date picker above: this is a
    // SECOND dialog the user can sit in, and guarding only the first await of
    // a two-dialog flow leaves exactly the same hole it was meant to close.
    if (time == null || !mounted) return;
    setState(() => _deadline = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (_selectedSection == null || _titleCtrl.text.trim().isEmpty || _deadline == null) return;
    final maxMarks = double.tryParse(_maxMarksCtrl.text.trim());
    if (maxMarks == null || maxMarks <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Marks must be a number above 0'), backgroundColor: AppColors.amber));
      return;
    }
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
        maxMarks: maxMarks,
      );
      widget.onCreated();
      AppHaptics.success();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('New Assignment', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(context))),
          const SizedBox(height: 16),
          if (_loading) const Center(child: SupernovaBusy(label: 'Loading your classes'))
          else if (_sections.isEmpty)
            // Classes come from approved course_offerings now, not the
            // self-typed initials the old copy told teachers to go and set.
            Text('No approved course offerings yet — create one and get it '
                'approved before posting assignments.',
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
            // The mark ceiling is per-assignment because a weekly problem sheet
            // and a term paper are not worth the same; a DB trigger rejects a
            // mark above whatever is set here.
            AfosTextField(
                hint: 'Marks this assignment is out of',
                controller: _maxMarksCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true)),
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
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  /// The try/catch is load-bearing: without it a dropped request left
  /// `_loading` true forever, so the tab sat on its shimmer with no error and
  /// no way to retry.
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await widget.repo.getMyAssignments();
      if (mounted) setState(() => _assignments = res);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _delete(String id) async {
    try {
      await widget.repo.deleteAssignment(id);
      AppHaptics.warning();
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_assignments.isEmpty) {
      return const EmptyState(icon: AppIcons.assignments,
        title: 'No assignments yet', subtitle: 'Tap + to post one to a class you teach');
    }
    return RefreshIndicator(onRefresh: _load, color: AppColors.blue,
        child: AdaptiveList(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: _assignments.length,
            // Guarded by the `if (_assignments.isEmpty) return EmptyState(...)`
            // early-return above, so .first is safe. The delete icon is
            // conditional (`if (!expired)`) but doesn't change row height.
            prototypeItem: _buildAssignmentRow(context, _assignments.first),
            itemBuilder: (ctx, i) => _buildAssignmentRow(ctx, _assignments[i])));
  }

  Future<void> _openSubmissions(BuildContext ctx, Map<String, dynamic> a) async {
    await Navigator.of(ctx).push(MaterialPageRoute(
        builder: (_) => AssignmentSubmissionsScreen(assignment: a)));
    // Marking changes nothing on this row today, but reloading keeps the
    // submission count honest if students hand in while the list is open.
    _load();
  }

  Widget _buildAssignmentRow(BuildContext ctx, Map<String, dynamic> a) {
    final deadline = DateTime.tryParse(a['deadline'] ?? '');
    final expired = deadline != null && deadline.isBefore(DateTime.now());
    final count = ((a['assignment_submissions'] as List?)?.firstOrNull as Map?)?['count'] ?? 0;
    final maxMarks = ((a['max_marks'] as num?) ?? 10).toDouble();
    return Container(margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: AppColors.surfaceOf(ctx), borderRadius: AppDepth.radius(1),
            border: Border.all(color: AppColors.borderOf(ctx), width: 0.5)),
        // The card previously showed a submission count and did nothing when
        // tapped — getSubmissions() existed in the repository from day one and
        // was never called from anywhere. This is the way in to marking.
        child: InkWell(
          onTap: () { AppHaptics.selection(); _openSubmissions(ctx, a); },
          // Must match the Container above, or the ink splash spills past the
          // card's corners.
          borderRadius: AppDepth.radius(1),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(a['title'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(ctx)))),
                if (!expired) IconButton(icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.red),
                    onPressed: () => _delete(a['id'])),
                Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textSecondaryOf(ctx)),
              ]),
              Text('${a['course_code']} · Batch ${a['batch']} Sec ${a['section']} · out of ${maxMarks.toStringAsFixed(0)}',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(ctx))),
              const SizedBox(height: 6),
              Text('$count submission(s) · ${expired ? "Closed" : "Due"} ${deadline != null ? AppFormatters.dateTime(deadline) : ''}',
                  style: TextStyle(color: expired ? AppColors.red : AppColors.green, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ));
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
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  /// See the note on the teacher tab's _load: an unguarded failure here left
  /// the shimmer up permanently.
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await widget.repo.getMyClassAssignments();
      if (mounted) setState(() => _assignments = res);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _submit(BuildContext context, Map<String, dynamic> a) async {
    final existing = a['my_submission'] as Map<String, dynamic>?;
    final ctrl = TextEditingController(text: existing?['content'] as String? ?? '');
    PlatformFile? attachment;
    var saving = false;

    await showGlassModal(context, builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) => SingleChildScrollView(
            padding: EdgeInsetsDirectional.fromSTEB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${existing == null ? 'Submit' : 'Update'}: ${a['title']}',
                  style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 16),
              AfosTextField(hint: 'Your answer / notes', controller: ctrl, maxLines: 5),
              const SizedBox(height: 12),
              // Coursework is usually a file, not a paragraph typed on a phone.
              // Same picker config the feedback sheet already uses.
              OutlinedButton.icon(
                onPressed: saving ? null : () async {
                  final res = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: const ['pdf', 'doc', 'docx', 'png', 'jpg', 'jpeg', 'zip', 'txt'],
                      withData: true);
                  if (res != null) setSheetState(() => attachment = res.files.first);
                },
                icon: const Icon(Icons.attach_file_rounded, size: 16),
                label: Text(
                    attachment?.name
                        ?? (existing?['attachment_url'] != null ? 'Replace attached file' : 'Attach a file (optional)'),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(height: 20),
              AfosButton(label: existing == null ? 'Submit' : 'Update submission', loading: saving, onTap: () async {
                if (ctrl.text.trim().isEmpty && attachment == null && existing == null) return;
                setSheetState(() => saving = true);
                try {
                  String? path;
                  final file = attachment;
                  if (file?.bytes != null) {
                    path = await widget.repo.uploadSubmissionFile(
                        assignmentId: a['id'] as String,
                        filename: file!.name,
                        bytes: file.bytes!);
                  }
                  await widget.repo.submitAssignment(
                      a['id'] as String, ctrl.text.trim(), attachmentPath: path);
                  AppHaptics.success();
                  if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                  _load();
                } catch (e) {
                  setSheetState(() => saving = false);
                  if (sheetCtx.mounted) {
                    ScaffoldMessenger.of(sheetCtx).showSnackBar(
                        SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
                  }
                }
              }),
            ]))));
    ctrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_assignments.isEmpty) {
      return const EmptyState(icon: AppIcons.assignments,
        title: 'No assignments yet', subtitle: 'Assignments from your teachers will show up here');
    }
    return RefreshIndicator(onRefresh: _load, color: AppColors.blue,
        child: AdaptiveList(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: _assignments.length,
            itemBuilder: (ctx, i) {
              final a = _assignments[i];
              final deadline = DateTime.tryParse(a['deadline'] ?? '');
              final expired = deadline != null && deadline.isBefore(DateTime.now());
              final submitted = a['has_submitted'] == true;
              final mine = a['my_submission'] as Map<String, dynamic>?;
              final marks = (mine?['marks'] as num?)?.toDouble();
              final maxMarks = ((a['max_marks'] as num?) ?? 10).toDouble();
              final feedback = mine?['feedback'] as String?;
              return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(1),
                      border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(a['title'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                    Text('${a['course_code']} · ${a['course_title'] ?? ''} · out of ${maxMarks.toStringAsFixed(0)}',
                        style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
                    const SizedBox(height: 6),
                    if ((a['description'] as String?)?.isNotEmpty == true)
                      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(a['description'],
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)))),
                    Text(submitted ? 'Submitted' : expired ? 'Deadline passed' : 'Due ${deadline != null ? AppFormatters.dateTime(deadline) : ''}',
                        style: TextStyle(color: submitted ? AppColors.green : expired ? AppColors.red : AppColors.amber,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    // The mark and the teacher's comments are the whole point of
                    // handing work in, and until now a student could only ever
                    // see that a submission existed.
                    if (marks != null) Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _MarkResult(marks: marks, maxMarks: maxMarks, feedback: feedback),
                    ),
                    // Editable until the deadline, and only until it is marked —
                    // both enforced in RLS, mirrored here so the button is not
                    // offered when the write would be rejected.
                    if (!expired && marks == null) Padding(padding: const EdgeInsets.only(top: 8),
                        child: SizedBox(width: double.infinity, child: OutlinedButton(
                            onPressed: () => _submit(context, a),
                            child: Text(submitted ? 'Update submission' : 'Submit')))),
                  ]));
            }));
  }
}

/// A student's mark and the teacher's comments on one submission.
class _MarkResult extends StatelessWidget {
  final double marks, maxMarks;
  final String? feedback;
  const _MarkResult({required this.marks, required this.maxMarks, required this.feedback});

  @override
  Widget build(BuildContext context) {
    final ratio = maxMarks <= 0 ? 0.0 : (marks / maxMarks).clamp(0.0, 1.0);
    final color = ratio >= 0.5 ? AppColors.green : AppColors.amber;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppDepth.radius(1),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.grading_rounded, size: 15, color: color),
          const SizedBox(width: 6),
          // A mark out of a maximum — the tabular case, same as the grades
          // breakdown rows.
          Text('${marks.toStringAsFixed(marks % 1 == 0 ? 0 : 1)} / ${maxMarks.toStringAsFixed(0)}',
              style: AppTextStyles.numericSmall.copyWith(
                  color: color, fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        if (feedback != null && feedback!.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(feedback!,
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
        ],
      ]),
    );
  }
}

class _ObserveTab extends StatefulWidget {
  @override State<_ObserveTab> createState() => _ObserveTabState();
}

class _ObserveTabState extends State<_ObserveTab> {
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  /// Same guard as the other two tabs — an unguarded throw here stranded the
  /// shimmer with no error and no retry.
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await SupabaseConfig.client.from('assignments')
          .select('id, title, course_code, batch, section, profiles!teacher_id(full_name)')
          .order('deadline', ascending: false).limit(100) as List;
      if (mounted) setState(() => _all = res.cast());
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_all.isEmpty) return const EmptyState(icon: AppIcons.assignments, title: 'No assignments yet', subtitle: 'System-wide assignments will show up here');
    // Pull-to-refresh was missing here alone, so a super_admin had no way to
    // re-read the list short of leaving the screen.
    return RefreshIndicator(onRefresh: _load, color: AppColors.blue,
        child: AdaptiveList(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), itemCount: _all.length,
        itemBuilder: (ctx, i) {
          final a = _all[i];
          final teacher = a['profiles'] as Map<String, dynamic>? ?? {};
          return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(1),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a['title'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                Text('${a['course_code']} · Batch ${a['batch']} Sec ${a['section']} · by ${teacher['full_name'] ?? 'Unknown'}',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
              ]));
        }));
  }
}
