import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/data/bd_geography.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/location_helper.dart';
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
  bool _isStaff = false;
  bool _isAdminTier = false;
  String? _gender;
  double _sem = 1;
  bool _loading = true, _saving = false;
  List<DepartmentOption> _departments = [];
  DepartmentOption? _selectedDept;
  String? _avatarUrl;
  String _studentId = '';
  String _email = '';

  bool _loadingStaffDesignations = true;
  List<StaffDesignationOption> _staffDesignations = [];
  StaffDesignationOption? _selectedStaffDesignation;

  String? _division;
  String? _district;
  String? _upazila;
  String? _thana;

  // Mandatory live-GPS capture -- separate from (and in addition to) the
  // registered permanent address above. A student's registered home
  // district might be far from where they actually are day to day; this is
  // what makes "nearest bus stop"/"who's actually nearby" features and the
  // SOS proximity layer work from first login, not just after the user
  // happens to open Transport or Settings later.
  Position? _capturedPosition;
  bool _capturingLocation = false;
  // True when this account already has a saved user_locations row from a
  // previous visit — the screen used to have no idea this had already
  // happened (only _capturedPosition, an in-memory Position object that's
  // never reconstructed from the database) so returning here after any
  // navigation away — even having successfully confirmed location moments
  // earlier — silently failed the mandatory-location gate in _save() again,
  // with no way to tell why "Save & Continue" appeared to do nothing.
  bool _hasExistingLocation = false;

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
    // The department list is a hard requirement -- _save() can never
    // succeed without it, and the dropdown itself silently refuses to even
    // open when its `items` is empty (no error, no visible sign why). It
    // used to be fetched deep inside one big try/catch alongside several
    // other, genuinely optional reads (profile row, location check) — ANY
    // of those throwing (a network hiccup, anything) aborted the whole
    // function before `_departments` was ever assigned, permanently
    // bricking the dropdown with zero feedback. Fetched and committed to
    // state on its own, first, so nothing downstream can take it out.
    List<DepartmentOption> depts = [];
    try {
      depts = await _academicRepo.fetchDepartments();
    } catch (_) { /* best-effort; _save() re-validates via the dropdown's own validator */ }
    if (mounted) setState(() => _departments = depts);

    List<StaffDesignationOption> staffDesignations = [];
    try {
      staffDesignations = await _academicRepo.fetchStaffDesignations();
      if (mounted) setState(() { _staffDesignations = staffDesignations; _loadingStaffDesignations = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingStaffDesignations = false);
    }

    try {
      if (uid != null) {
        // No embeds -- three simultaneous relationship joins
        // (teachers/staff/students) on one query previously fed the
        // batch/section fallback below, and despite matching the same
        // FK shape Settings' own (working) Routine Info query uses,
        // students.batch_label/section kept coming back empty here for at
        // least one real account, blocking save with fields that looked
        // blank even though the data was genuinely saved. Splitting the
        // students lookup into its own plain query removes whatever about
        // the combined embed was failing, and matches Settings' proven
        // pattern of reading columns directly.
        final p = await SupabaseConfig.client.from('profiles')
            .select().eq('id', uid).maybeSingle();
        if (p != null) {
          // Every field below is independently guarded -- this used to be
          // one unbroken run of assignments, so a single bad/unexpected
          // value (a null cast, a missing embed row) threw partway through
          // and silently left every field AFTER it at its blank default,
          // even though the fields before it (name/phone) had already been
          // set correctly. Confirmed live on a real completed account:
          // name+phone showed up, but emergency contact/gender/permanent
          // address/department all rendered blank despite every one of
          // those columns having real saved values in the database.
          try { _nameCtrl.text = (p['full_name'] as String? ?? '') == 'New User' ? '' : (p['full_name'] as String? ?? ''); } catch (_) {}
          try { _phoneCtrl.text = p['phone'] as String? ?? ''; } catch (_) {}
          try { _emergencyCtrl.text = p['emergency_contact'] as String? ?? ''; } catch (_) {}
          try {
            _isTeacher = p['role'] == 'teacher';
            _isStaff = p['role'] == 'staff';
            _isAdminTier = const ['admin', 'dept_admin', 'super_admin'].contains(p['role']);
          } catch (_) {}
          try { _sem = ((p['semester'] as int?) ?? 1).toDouble(); } catch (_) {}
          try {
            // profiles.batch/section are only ever populated once this exact
            // screen (or Settings' Routine Info) has been saved at least once
            // -- students.batch_label/section is set at signup and is the
            // reliable source, so fall back to it rather than showing blank
            // fields for a value that's genuinely already saved. A plain,
            // explicit query rather than an embed on the combined select --
            // see the comment above the profiles query itself.
            var batch = p['batch'] as String?;
            var section = p['section'] as String?;
            if ((batch == null || section == null) && !_isTeacher && !_isStaff && !_isAdminTier) {
              final studentRow = await SupabaseConfig.client.from('students')
                  .select('batch_label,section').eq('profile_id', uid).maybeSingle();
              batch ??= studentRow?['batch_label'] as String?;
              section ??= studentRow?['section'] as String?;
            }
            _batchCtrl.text = batch ?? '';
            _sectionCtrl.text = section ?? '';
          } catch (_) {}
          try { _avatarUrl = p['avatar_url'] as String?; } catch (_) {}
          try { _gender = p['gender'] as String?; } catch (_) {}
          try { _studentId = p['university_id'] as String? ?? p['student_id'] as String? ?? ''; } catch (_) {}
          try { _email = p['email'] as String? ?? ''; } catch (_) {}
          try {
            _division = p['permanent_division'] as String?;
            _district = p['permanent_district'] as String?;
            _upazila = p['permanent_upazila'] as String?;
            _thana = p['permanent_thana'] as String?;
          } catch (_) {}
          try {
            if (_isTeacher) {
              final teacherRow = await SupabaseConfig.client.from('teachers')
                  .select('designation').eq('profile_id', uid).maybeSingle();
              if (teacherRow?['designation'] != null) _designationCtrl.text = teacherRow!['designation'] as String;
            }
          } catch (_) {}
          try {
            if (_isStaff) {
              final staffRow = await SupabaseConfig.client.from('staff')
                  .select('designation,category').eq('profile_id', uid).maybeSingle();
              if (staffRow?['designation'] != null) {
                _selectedStaffDesignation = staffDesignations.where((d) => d.title == staffRow!['designation']).firstOrNull;
              }
            }
          } catch (_) {}
          try {
            final deptCode = p['department'] as String?;
            if (deptCode != null) {
              _selectedDept = depts.where((d) => d.code == deptCode).firstOrNull;
            }
          } catch (_) {}
        }
        // Isolated in its own try/catch, deliberately -- this is a nice-to-
        // have (skip re-confirming a location we already have), not a
        // required field. Sharing the outer try meant ANY failure here
        // (network hiccup, anything) silently aborted the whole _load()
        // before `_departments` was ever assigned, leaving the required
        // department dropdown permanently empty with zero error shown —
        // exactly the "department can't be selected" symptom this caused.
        try {
          final loc = await SupabaseConfig.client.from('user_locations')
              .select('user_id').eq('user_id', uid).maybeSingle();
          _hasExistingLocation = loc != null;
        } catch (_) {
          _hasExistingLocation = false;
        }
      }
      if (mounted) setState(() { _departments = depts; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmLocation() async {
    setState(() => _capturingLocation = true);
    final pos = await LocationHelper.getCurrentPosition(onError: (msg) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: AppColors.red));
      }
    });
    if (mounted) setState(() { _capturedPosition = pos; _capturingLocation = false; });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDept == null) return;
    if (_isStaff && _selectedStaffDesignation == null) return;
    if (_division == null || _district == null || _upazila == null) return;
    if (BdGeography.isDhakaMahanagar(_division, _district, _upazila) && _thana == null) return;
    if (_capturedPosition == null && !_hasExistingLocation) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Confirm your current location to continue'), backgroundColor: AppColors.red));
      return;
    }
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      // Only re-upsert if the user actually captured a fresh position this
      // visit — an already-confirmed location from a previous visit
      // (_hasExistingLocation) is left untouched rather than needing to be
      // re-captured just to satisfy this gate again.
      if (_capturedPosition != null) {
        await SupabaseConfig.client.from('user_locations').upsert({
          'user_id': uid,
          'latitude': _capturedPosition!.latitude,
          'longitude': _capturedPosition!.longitude,
          'accuracy_m': _capturedPosition!.accuracy,
          'sharing_enabled': true,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
      await SupabaseConfig.client.from('profiles').update({
        'full_name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'emergency_contact': _emergencyCtrl.text.trim(),
        'department': _selectedDept!.code,
        'department_id': _selectedDept!.id,
        'semester': _sem.toInt(),
        'profile_completed': true,
        'permanent_division': _division,
        'permanent_district': _district,
        'permanent_upazila': _upazila,
        'permanent_thana': BdGeography.isDhakaMahanagar(_division, _district, _upazila) ? _thana : null,
        if (_gender != null) 'gender': _gender,
        // Also mirrored onto students.batch_label/section below — the
        // schedule screen's "only my batch+section" routine filter reads
        // profiles.batch/section specifically (it matches the routine PDF's
        // raw text), so without this a student could complete the required
        // onboarding batch/section fields and still never see their
        // personalized class schedule. Guarded by isNotEmpty (matching the
        // students-table write below) so re-visiting this screen can never
        // blank out an already-saved value with an empty string.
        if (!_isTeacher && !_isStaff && !_isAdminTier && _batchCtrl.text.trim().isNotEmpty)
          'batch': _batchCtrl.text.trim(),
        if (!_isTeacher && !_isStaff && !_isAdminTier && _sectionCtrl.text.trim().isNotEmpty)
          'section': _sectionCtrl.text.trim(),
      }).eq('id', uid);

      if (_isTeacher) {
        await SupabaseConfig.client.from('teachers').update({
          'department_id': _selectedDept!.id,
          if (_designationCtrl.text.trim().isNotEmpty) 'designation': _designationCtrl.text.trim(),
        }).eq('profile_id', uid);
      } else if (_isStaff) {
        await SupabaseConfig.client.from('staff').update({
          'department_id': _selectedDept!.id,
          if (_selectedStaffDesignation != null) 'designation': _selectedStaffDesignation!.title,
          if (_selectedStaffDesignation != null) 'category': _selectedStaffDesignation!.category,
        }).eq('profile_id', uid);
      } else if (_isAdminTier) {
        // Admin/dept_admin/super_admin accounts have no teachers/staff/
        // students row at all (they're created via role promotion, not a
        // dedicated signup path) and no professional-designation concept
        // anywhere else in the app — nothing further to persist for them.
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
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
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
                    Text('Permanent address', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                    const SizedBox(height: 4),
                    Text('Used to alert nearby people if you ever need emergency help.',
                        style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
                    const SizedBox(height: 8),
                    _AddressDropdown(
                      hint: 'Division',
                      value: _division,
                      items: BdGeography.divisions,
                      onChanged: (v) => setState(() { _division = v; _district = null; _upazila = null; _thana = null; }),
                    ),
                    const SizedBox(height: 12),
                    _AddressDropdown(
                      hint: 'District',
                      value: _district,
                      items: BdGeography.districtsOf(_division),
                      onChanged: (v) => setState(() { _district = v; _upazila = null; _thana = null; }),
                    ),
                    const SizedBox(height: 12),
                    _AddressDropdown(
                      hint: 'Upazila',
                      value: _upazila,
                      items: BdGeography.upazilasOf(_division, _district),
                      onChanged: (v) => setState(() { _upazila = v; _thana = null; }),
                    ),
                    // Dhaka city proper isn't subdivided into upazilas --
                    // selecting the synthetic "Dhaka Mahanagar" entry above
                    // reveals the real DMP thana list as a 4th level instead
                    // of the address stopping one level short.
                    if (BdGeography.isDhakaMahanagar(_division, _district, _upazila)) ...[
                      const SizedBox(height: 12),
                      _AddressDropdown(
                        hint: 'Thana',
                        value: _thana,
                        items: BdGeography.dhakaThanas,
                        onChanged: (v) => setState(() => _thana = v),
                      ),
                    ],
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
                      initialValue: _selectedDept,
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
                      // Was the one required field on this whole screen with
                      // no validator at all -- _save()'s own "if (_selectedDept
                      // == null) return" guard then blocked the save with
                      // zero feedback, indistinguishable from the button
                      // simply not working.
                      validator: (v) => v == null ? 'Select a department' : null,
                    ),
                    const SizedBox(height: 16),
                    if (_isTeacher)
                      AfosTextField(hint: 'Designation (e.g. Lecturer)', controller: _designationCtrl,
                          validator: (v) => AppValidators.required(v, f: 'Designation'))
                    else if (_isStaff)
                      _loadingStaffDesignations
                          ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                          : DropdownButtonFormField<StaffDesignationOption>(
                              initialValue: _selectedStaffDesignation,
                              isExpanded: true,
                              decoration: InputDecoration(hintText: 'Designation / Job Title', filled: true,
                                  fillColor: AppColors.glassFill(context),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: AppColors.borderOf(context)))),
                              dropdownColor: AppColors.surfaceOf(context),
                              style: TextStyle(color: textPrimary),
                              validator: (v) => v == null ? 'Select a designation' : null,
                              items: _groupedStaffItems(_staffDesignations, AppColors.textSecondaryOf(context)),
                              onChanged: (v) => setState(() => _selectedStaffDesignation = v),
                            )
                    else if (_isAdminTier)
                      const SizedBox.shrink()
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
                    const SizedBox(height: 20),
                    Text('Current location', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                    const SizedBox(height: 4),
                    Text('Required so nearby bus stops and emergency alerts can find you.',
                        style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
                    const SizedBox(height: 8),
                    if (_capturedPosition != null || _hasExistingLocation)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Location confirmed',
                              style: AppTextStyles.bodyMedium.copyWith(color: textPrimary))),
                          TextButton(onPressed: _capturingLocation ? null : _confirmLocation,
                              child: const Text('Refresh')),
                        ]),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: _capturingLocation ? null : _confirmLocation,
                        icon: _capturingLocation
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.my_location_rounded),
                        label: Text(_capturingLocation ? 'Getting location…' : 'Confirm my location'),
                      ),
                    const SizedBox(height: 24),
                    AfosButton(label: 'Save & Continue', loading: _saving, onTap: _save),
                  ])),
                ),
              ),
            )),
    );
  }

  /// Same grouped-dropdown workaround as register_screen.dart's _Step2 —
  /// DropdownButtonFormField has no native optgroup support.
  List<DropdownMenuItem<StaffDesignationOption>> _groupedStaffItems(
      List<StaffDesignationOption> options, Color headerColor) {
    final items = <DropdownMenuItem<StaffDesignationOption>>[];
    String? lastCategory;
    for (final o in options) {
      if (o.category != lastCategory) {
        items.add(DropdownMenuItem(
            enabled: false,
            value: StaffDesignationOption(id: '__header_${o.category}', category: o.category, title: o.category),
            child: Text(o.category.toUpperCase(),
                style: TextStyle(color: headerColor, fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.4))));
        lastCategory = o.category;
      }
      items.add(DropdownMenuItem(value: o,
          child: Padding(padding: const EdgeInsets.only(left: 8),
              child: Text(o.title, overflow: TextOverflow.ellipsis))));
    }
    return items;
  }
}

class _AddressDropdown extends StatelessWidget {
  final String hint;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _AddressDropdown({required this.hint, required this.value, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    return DropdownButtonFormField<String>(
      initialValue: items.contains(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(hintText: hint, filled: true,
          fillColor: AppColors.glassFill(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.borderOf(context)))),
      dropdownColor: AppColors.surfaceOf(context),
      style: TextStyle(color: textPrimary),
      validator: (v) => v == null ? 'Select a $hint'.toLowerCase() : null,
      items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: items.isEmpty ? null : onChanged,
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
