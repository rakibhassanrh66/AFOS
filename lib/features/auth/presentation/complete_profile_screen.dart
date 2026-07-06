import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/avatar_picker.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../core/utils/validators.dart';
import '../data/repositories/academic_repository.dart';
import '../../../shared/models/user_model.dart';

/// Force-completion gate for accounts that skipped mandatory fields at
/// signup (an older/looser signup path, or an admin-created account) —
/// the router redirects here and won't let the user past it until saved.
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});
  @override State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _academicRepo = AcademicRepository();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emergencyCtrl = TextEditingController();
  final _batchCtrl = TextEditingController();
  final _sectionCtrl = TextEditingController();
  final _designationCtrl = TextEditingController();

  bool _isTeacher = false;
  String? _gender;
  double _sem = 1;
  bool _loading = true, _saving = false;
  List<DepartmentOption> _departments = [];
  DepartmentOption? _selectedDept;
  String? _avatarUrl;
  String _studentId = '';
  String _email = '';

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _emergencyCtrl.dispose();
    _batchCtrl.dispose(); _sectionCtrl.dispose(); _designationCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    try {
      final depts = await _academicRepo.fetchDepartments();
      if (uid != null) {
        final p = await SupabaseConfig.client.from('profiles').select().eq('id', uid).maybeSingle();
        if (p != null) {
          _nameCtrl.text = (p['full_name'] as String? ?? '') == 'New User' ? '' : (p['full_name'] as String? ?? '');
          _phoneCtrl.text = p['phone'] as String? ?? '';
          _isTeacher = const ['teacher', 'admin', 'dept_admin', 'super_admin'].contains(p['role']);
          _sem = ((p['semester'] as int?) ?? 1).toDouble();
          _avatarUrl = p['avatar_url'] as String?;
          _gender = p['gender'] as String?;
          _studentId = p['university_id'] as String? ?? p['student_id'] as String? ?? '';
          _email = p['email'] as String? ?? '';
          final deptCode = p['department'] as String?;
          if (deptCode != null) {
            _selectedDept = depts.where((d) => d.code == deptCode).firstOrNull;
          }
        }
      }
      if (mounted) setState(() { _departments = depts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDept == null) return;
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      await SupabaseConfig.client.from('profiles').update({
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'emergency_contact': _emergencyCtrl.text.trim(),
        'department': _selectedDept!.code,
        'department_id': _selectedDept!.id,
        'semester': _sem.toInt(),
        'profile_completed': true,
        if (_gender != null) 'gender': _gender,
        // Also mirrored onto students.batch_label/section below — the
        // schedule screen's "only my batch+section" routine filter reads
        // profiles.batch/section specifically (it matches the routine PDF's
        // raw text), so without this a student could complete the required
        // onboarding batch/section fields and still never see their
        // personalized class schedule.
        if (!_isTeacher) 'batch': _batchCtrl.text.trim(),
        if (!_isTeacher) 'section': _sectionCtrl.text.trim(),
      }).eq('id', uid);

      if (_isTeacher) {
        await SupabaseConfig.client.from('teachers').update({
          'department_id': _selectedDept!.id,
          if (_designationCtrl.text.trim().isNotEmpty) 'designation': _designationCtrl.text.trim(),
        }).eq('profile_id', uid);
      } else {
        await SupabaseConfig.client.from('students').update({
          'department_id': _selectedDept!.id,
          'current_semester_no': _sem.toInt(),
          if (_batchCtrl.text.trim().isNotEmpty) 'batch_label': _batchCtrl.text.trim(),
          if (_sectionCtrl.text.trim().isNotEmpty) 'section': _sectionCtrl.text.trim(),
        }).eq('profile_id', uid);
      }

      RoleSession.markProfileCompleted();
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: AppColors.surfaceOf(context),
      body: SafeArea(child: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: GlassCard(
                glowColor: AppColors.holoBlue,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Complete your profile', style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
                    const SizedBox(height: 6),
                    Text('A few required details are missing before you can continue.',
                        style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                    const SizedBox(height: 20),
                    Center(child: AvatarPicker(
                        avatarUrl: _avatarUrl,
                        initials: UserModel(id: '', email: '', fullName: _nameCtrl.text, role: 'student').initials,
                        onChanged: (url) => setState(() => _avatarUrl = url))),
                    const SizedBox(height: 16),
                    if (_studentId.isNotEmpty) _ReadOnlyRow(label: 'Student/University ID', value: _studentId),
                    if (_email.isNotEmpty) _ReadOnlyRow(label: 'Email', value: _email),
                    const SizedBox(height: 8),
                    AfosTextField(hint: 'Full name', controller: _nameCtrl,
                        validator: (v) => AppValidators.required(v, f: 'Full name')),
                    const SizedBox(height: 16),
                    AfosTextField(hint: 'Phone number', controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        validator: (v) => AppValidators.required(v, f: 'Phone')),
                    const SizedBox(height: 16),
                    AfosTextField(hint: 'Emergency contact (name + phone)', controller: _emergencyCtrl),
                    const SizedBox(height: 16),
                    Text('Gender', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: _GenderChip(label: 'Male', selected: _gender == 'male',
                          onTap: () => setState(() => _gender = 'male'))),
                      const SizedBox(width: 12),
                      Expanded(child: _GenderChip(label: 'Female', selected: _gender == 'female',
                          onTap: () => setState(() => _gender = 'female'))),
                    ]),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<DepartmentOption>(
                      value: _selectedDept,
                      isExpanded: true,
                      decoration: InputDecoration(hintText: 'Department', filled: true,
                          fillColor: AppColors.glassFill(context),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: AppColors.borderOf(context)))),
                      dropdownColor: AppColors.surfaceOf(context),
                      style: TextStyle(color: textPrimary),
                      items: _departments.map((d) => DropdownMenuItem(value: d,
                          child: Text(d.name, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() => _selectedDept = v),
                    ),
                    const SizedBox(height: 16),
                    if (_isTeacher)
                      AfosTextField(hint: 'Designation (e.g. Lecturer)', controller: _designationCtrl,
                          validator: (v) => AppValidators.required(v, f: 'Designation'))
                    else ...[
                      Row(children: [
                        Expanded(child: AfosTextField(hint: 'Batch (e.g. 61)', controller: _batchCtrl,
                            validator: (v) => AppValidators.required(v, f: 'Batch'))),
                        const SizedBox(width: 12),
                        Expanded(child: AfosTextField(hint: 'Section (e.g. A)', controller: _sectionCtrl,
                            validator: (v) => AppValidators.required(v, f: 'Section'))),
                      ]),
                      const SizedBox(height: 20),
                      Text('Semester: ${_sem.toInt()}', style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
                      Slider(value: _sem, min: 1, max: 12, divisions: 11,
                          activeColor: AppColors.holoBlue, label: '${_sem.toInt()}',
                          onChanged: (v) => setState(() => _sem = v)),
                    ],
                    const SizedBox(height: 24),
                    AfosButton(label: 'Save & Continue', loading: _saving, onTap: _save),
                  ])),
                ),
              ),
            )),
    );
  }
}

class _GenderChip extends StatelessWidget {
  final String label; final bool selected; final VoidCallback onTap;
  const _GenderChip({required this.label, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: selected ? AppColors.holoBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AppColors.holoBlue : AppColors.borderOf(context), width: 0.8)),
          child: Text(label, style: TextStyle(
              color: selected ? Colors.white : AppColors.textSecondaryOf(context),
              fontWeight: FontWeight.w600, fontSize: 13))));
}

class _ReadOnlyRow extends StatelessWidget {
  final String label, value;
  const _ReadOnlyRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(children: [
      Text('$label: ', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w600)),
      Expanded(child: Text(value, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimaryOf(context)),
          maxLines: 1, overflow: TextOverflow.ellipsis)),
    ]),
  );
}
