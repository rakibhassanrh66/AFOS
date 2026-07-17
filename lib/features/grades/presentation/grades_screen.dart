import 'package:flutter/material.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/grades_repository.dart';

const _publisherRoles = ['admin', 'dept_admin', 'super_admin', 'exam_controller'];
const _gradeLetters = ['A+', 'A', 'A-', 'B+', 'B', 'B-', 'C+', 'C', 'D', 'F'];

class GradesScreen extends StatefulWidget {
  const GradesScreen({super.key});
  @override State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  final _repo = GradesRepository();
  bool get _isTeacher => RoleSession.role == 'teacher';
  bool get _isPublisher => _publisherRoles.contains(RoleSession.role);

  Widget _header({required String title, required String subtitle, required IconData icon}) {
    return FeatureHeader(
      title: title,
      subtitle: subtitle,
      icon: icon,
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [AppColors.blue, AppColors.indigo]),
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isPublisher) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: const AfosAppBar(title: 'Publish Results'),
        body: Column(children: [
          _header(title: 'Publish Results', icon: Icons.publish_rounded,
              subtitle: 'Review teacher-uploaded grades and release them to students'),
          Expanded(child: _PublishTab(repo: _repo)),
        ]),
      );
    }
    if (_isTeacher) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: const AfosAppBar(title: 'Upload Grades'),
        body: Column(children: [
          _header(title: 'Upload Grades', icon: Icons.grade_rounded,
              subtitle: 'Enter grades for your sections, then submit for department publish'),
          Expanded(child: _TeacherUploadTab(repo: _repo)),
        ]),
      );
    }
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'My Results'),
      body: Column(children: [
        _header(title: 'My Results', icon: Icons.school_rounded,
            subtitle: 'Your published grades, organized by semester'),
        Expanded(child: _StudentResultsTab(repo: _repo)),
      ]),
    );
  }
}

class _StudentResultsTab extends StatefulWidget {
  final GradesRepository repo;
  const _StudentResultsTab({required this.repo});
  @override State<_StudentResultsTab> createState() => _StudentResultsTabState();
}

class _StudentResultsTabState extends State<_StudentResultsTab> {
  List<Map<String, dynamic>> _results = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final res = await widget.repo.getMyResults();
    if (mounted) setState(() { _results = res; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_results.isEmpty) {
      return const EmptyState(icon: Icons.assignment_turned_in_outlined,
        title: 'No published results yet', subtitle: 'Results appear here once your department publishes them');
    }
    final bySemester = <int, List<Map<String, dynamic>>>{};
    for (final r in _results) {
      (bySemester[r['semester'] as int? ?? 0] ??= []).add(r);
    }
    final semesters = bySemester.keys.toList()..sort((a, b) => b.compareTo(a));
    return RefreshIndicator(onRefresh: _load, color: AppColors.blue,
        child: ListView(padding: const EdgeInsets.all(16), children: semesters.expand((sem) sync* {
          yield Padding(padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('Semester $sem', style: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimaryOf(context))));
          for (final g in bySemester[sem]!) {
            yield Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(g['course_title'] ?? g['course_code'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                    Text(g['course_code'] ?? '', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
                  ])),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                              colors: [AppColors.blue, AppColors.indigo]),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))]),
                      child: Text(g['grade_letter'] ?? '',
                          textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                          style: const TextStyle(color: Colors.white, height: 1.0, fontWeight: FontWeight.w800, fontSize: 16))),
                ]));
          }
        }).toList()));
  }
}

class _TeacherUploadTab extends StatefulWidget {
  final GradesRepository repo;
  const _TeacherUploadTab({required this.repo});
  @override State<_TeacherUploadTab> createState() => _TeacherUploadTabState();
}

class _TeacherUploadTabState extends State<_TeacherUploadTab> {
  List<Map<String, String>> _sections = [];
  Map<String, String>? _selectedSection;
  List<Map<String, dynamic>> _students = [];
  final Map<String, String> _grades = {};
  bool _loading = true, _saving = false;

  @override
  void initState() { super.initState(); _init(); }

  Future<void> _init() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    final profile = await SupabaseConfig.client.from('profiles').select('teacher_initial').eq('id', uid).maybeSingle();
    final initial = profile?['teacher_initial'] as String?;
    if (initial == null || initial.isEmpty) { setState(() => _loading = false); return; }
    final sections = await widget.repo.getMyTaughtSections(initial);
    if (mounted) setState(() { _sections = sections; _loading = false; });
  }

  Future<void> _selectSection(Map<String, String> section) async {
    setState(() { _selectedSection = section; _students = []; _grades.clear(); });
    final students = await widget.repo.listSectionStudents(section['department']!, section['batch']!, section['section']!);
    if (mounted) setState(() => _students = students);
  }

  Future<void> _submit() async {
    if (_selectedSection == null) return;
    setState(() => _saving = true);
    try {
      for (final s in _students) {
        final grade = _grades[s['id']];
        if (grade == null || grade.isEmpty) continue;
        await widget.repo.upsertGrade(
          studentId: s['id'] as String,
          courseCode: _selectedSection!['subjectCode']!,
          courseTitle: _selectedSection!['subject']!,
          semester: int.tryParse(_selectedSection!['semester'] ?? '') ?? 1,
          batch: _selectedSection!['batch']!,
          section: _selectedSection!['section']!,
          gradeLetter: grade,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Grades submitted — waiting for department publish ✓'), backgroundColor: AppColors.green));
      }
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
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_sections.isEmpty) {
      return const EmptyState(icon: Icons.class_outlined,
        title: 'No classes found', subtitle: 'Set your teacher initials in Settings so we can find your sections');
    }
    return Column(children: [
      Padding(padding: const EdgeInsets.all(16), child: DropdownButtonFormField<Map<String, String>>(
          initialValue: _selectedSection,
          isExpanded: true,
          decoration: InputDecoration(hintText: 'Select a class', filled: true, fillColor: AppColors.glassFill(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.borderOf(context)))),
          dropdownColor: AppColors.surfaceOf(context),
          style: TextStyle(color: AppColors.textPrimaryOf(context)),
          items: _sections.map((s) => DropdownMenuItem(value: s,
              child: Text('${s['subjectCode']} — Batch ${s['batch']} Sec ${s['section']}', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) { if (v != null) _selectSection(v); })),
      if (_selectedSection != null)
        Expanded(child: _students.isEmpty
            ? const EmptyState(icon: Icons.people_outline, title: 'No students found', subtitle: 'No students are set to this batch/section yet')
            : Column(children: [
                Expanded(child: ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _students.length,
                    itemBuilder: (ctx, i) {
                      final s = _students[i];
                      return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
                        Expanded(child: Text('${s['full_name']} (${s['university_id'] ?? ''})',
                            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimaryOf(context)),
                            maxLines: 1, overflow: TextOverflow.ellipsis)),
                        DropdownButton<String>(
                            value: _grades[s['id']],
                            hint: const Text('Grade'),
                            items: _gradeLetters.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                            onChanged: (v) => setState(() => _grades[s['id'] as String] = v ?? '')),
                      ]));
                    })),
                Padding(padding: const EdgeInsets.all(16), child: AfosButton(label: 'Submit Grades', loading: _saving, onTap: _submit)),
              ])),
    ]);
  }
}

class _PublishTab extends StatefulWidget {
  final GradesRepository repo;
  const _PublishTab({required this.repo});
  @override State<_PublishTab> createState() => _PublishTabState();
}

class _PublishTabState extends State<_PublishTab> {
  List<Map<String, dynamic>> _pending = [];
  final Set<String> _selected = {};
  bool _loading = true, _publishing = false;

  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final res = await widget.repo.getPendingPublish();
    if (mounted) setState(() { _pending = res; _loading = false; _selected.clear(); });
  }

  Future<void> _publish() async {
    if (_selected.isEmpty) return;
    setState(() => _publishing = true);
    try {
      await widget.repo.publishGrades(_selected.toList());
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Results published ✓'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
    if (mounted) setState(() => _publishing = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_pending.isEmpty) return const EmptyState(icon: Icons.publish_outlined, title: 'Nothing waiting to publish', subtitle: 'Teacher-uploaded results will show up here');
    return Column(children: [
      Expanded(child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: _pending.length,
          itemBuilder: (ctx, i) {
            final g = _pending[i];
            final student = g['profiles'] as Map<String, dynamic>? ?? {};
            final teacher = g['teacher'] as Map<String, dynamic>? ?? {};
            final id = g['id'] as String;
            final sel = _selected.contains(id);
            return CheckboxListTile(
                value: sel,
                onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
                title: Text('${student['full_name'] ?? ''} — ${g['course_code']} (${g['grade_letter']})',
                    style: TextStyle(color: AppColors.textPrimaryOf(context))),
                subtitle: Text('Sem ${g['semester']} · Batch ${g['batch']} Sec ${g['section']} · by ${teacher['full_name'] ?? 'Unknown'}',
                    style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12)));
          })),
      Padding(padding: const EdgeInsets.all(16), child: AfosButton(
          label: 'Publish Selected (${_selected.length})', loading: _publishing,
          onTap: _selected.isEmpty ? () {} : _publish)),
    ]);
  }
}
