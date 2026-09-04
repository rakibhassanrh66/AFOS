import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/spacing.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/data/bd_geography.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/location_helper.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/supernova_loader.dart';
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
  final _initialCtrl = TextEditingController();

  bool _isTeacher = false;
  bool _isStaff = false;
  bool _isAdminTier = false;
  String? _gender;
  double _sem = 1;
  bool _loading = true, _saving = false;
  List<DepartmentOption> _departments = [];
  DepartmentOption? _selectedDept;
  String? _avatarUrl;
  String? _avatarPendingUrl;
  String? _avatarReviewStatus;
  String? _avatarReviewReason;
  DateTime? _verifiedAt;

  /// Whether the 48-hour grace period for adding a photo has already passed
  /// with nothing submitted or an earlier photo rejected.
  ///
  /// This MIRRORS the photo clause in `profile_is_complete()` — the database
  /// is the authority, and the same three escapes apply: not yet verified (the
  /// clock has not started), still inside the window, or a photo already
  /// pending/approved. It exists only to EXPLAIN a restriction that is already
  /// in force; it never decides anything.
  bool get _photoWindowClosed {
    final at = _verifiedAt;
    if (at == null) return false;
    if (DateTime.now().difference(at) < const Duration(hours: 48)) return false;
    return _avatarReviewStatus != 'pending' && _avatarReviewStatus != 'approved';
  }
  String _studentId = '';
  String _email = '';

  bool _loadingStaffDesignations = true;
  List<StaffDesignationOption> _staffDesignations = [];
  StaffDesignationOption? _selectedStaffDesignation;

  String? _division;
  String? _district;
  String? _upazila;
  String? _thana;

  /// The intake term a student was admitted in, and the date printed on their
  /// ID card (for a teacher or officer, the date they joined). There was no
  /// column for either until 2026-08-22, and no way to derive them: the
  /// student IDs in the table are inconsistent, so no term code can be parsed
  /// out of them. They have to be asked for.
  String? _admissionSeason;
  final _admissionYearCtrl = TextEditingController();
  DateTime? _joinedOn;
  String? _joinedOnError;

  // Mandatory live-GPS capture -- separate from (and in addition to) the
  // registered permanent address above. A student's registered home
  // district might be far from where they actually are day to day; this is
  // what makes "nearest bus stop"/"who's actually nearby" features and the
  // SOS proximity layer work from first login, not just after the user
  // happens to open Transport or Settings later.
  Position? _capturedPosition;
  bool _capturingLocation = false;
  // Web-only escape hatch: browser geolocation permission prompts are
  // meaningfully less reliable than native (users reflexively click "Block",
  // and some browser/geolocator-web combinations could leave the request
  // hanging before the timeout above existed) -- and since profile_completed
  // now fails closed, a denied/unavailable location on web used to mean
  // permanently stuck on this screen with no way into the app at all. Native
  // GPS stays mandatory: permission handling there is reliable, and the
  // SOS/proximity guarantee should hold on phones. This flag is only ever
  // settable when kIsWeb is true, so native behavior is unchanged.
  bool _locationSkippedOnWeb = false;
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
    _initialCtrl.dispose();
    _admissionYearCtrl.dispose();
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
            _initialCtrl.text = (p['teacher_initial'] as String?) ?? '';
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
          try {
            _avatarPendingUrl = p['avatar_pending_url'] as String?;
            _avatarReviewStatus = p['avatar_review_status'] as String?;
            _avatarReviewReason = p['avatar_review_reason'] as String?;
          } catch (_) {}
          // Read so this screen can tell someone WHY they are here when the
          // 48-hour photo window has already closed. See _photoWindowClosed.
          try {
            _verifiedAt = DateTime.tryParse('${p['verified_at'] ?? ''}');
          } catch (_) {}
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
            // Pre-fill, so somebody sent back here for ONE missing field does
            // not have to retype what they already gave us.
            _admissionSeason = p['admission_season'] as String?;
            final y = p['admission_year'] as int?;
            if (y != null) _admissionYearCtrl.text = '$y';
            final j = p['joined_on'] as String?;
            if (j != null && j.isNotEmpty) _joinedOn = DateTime.tryParse(j);
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
    // _JoinDateField is an InputDecorator, not a FormField, so validate()
    // above does not cover it. Checked here or it is not checked at all.
    if (!_isAdminTier && _joinedOn == null) {
      setState(() => _joinedOnError = 'Join date is required');
      return;
    }
    if (!_isStaff && _selectedDept == null) return;
    if (_isStaff && _selectedStaffDesignation == null) return;
    if (_division == null || _district == null || _upazila == null) return;
    if (BdGeography.isDhakaMahanagar(_division, _district, _upazila) && _thana == null) return;
    if (_capturedPosition == null &&
        !_hasExistingLocation &&
        !(kIsWeb && _locationSkippedOnWeb)) {
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
        // Staff can genuinely have no department picked (see the dropdown's
        // `if (!_isStaff)` guard above) — conditional, not the old
        // unconditional `!`, so a null here leaves the existing DB value
        // untouched instead of crashing on the force-unwrap.
        if (_selectedDept != null) 'department': _selectedDept!.code,
        if (_selectedDept != null) 'department_id': _selectedDept!.id,
        'semester': _sem.toInt(),
        // Still sent, and now DISCARDED: a BEFORE trigger on profiles
        // overwrites this with profile_is_complete(new). Left in place
        // deliberately -- the trigger overrules it, and a generated column
        // would have made this write throw instead.
        'profile_completed': true,
        if (!_isTeacher && !_isStaff && !_isAdminTier)
          'admission_season': _admissionSeason,
        if (!_isTeacher && !_isStaff && !_isAdminTier)
          'admission_year': int.tryParse(_admissionYearCtrl.text.trim()),
        // ONE source of truth. The trigger mirrors this into
        // teachers.joining_date / staff.joining_date -- never write those.
        if (!_isAdminTier && _joinedOn != null)
          'joined_on': _joinedOn!.toIso8601String().split('T').first,
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
        // The initial lives on profiles, where a UNIQUE constraint makes it
        // an identity rather than the free text schedule_slots carries.
        // Upper-cased on the way in so 'fnb' and 'FNB' cannot become two
        // different teachers. Guarded by isNotEmpty so revisiting this
        // screen cannot blank an initial students have already linked to.
        if (_isTeacher && _initialCtrl.text.trim().isNotEmpty)
          'teacher_initial': _initialCtrl.text.trim().toUpperCase(),
      }).eq('id', uid);

      if (_isTeacher) {
        await SupabaseConfig.client.from('teachers').update({
          'department_id': _selectedDept!.id,
          if (_designationCtrl.text.trim().isNotEmpty) 'designation': _designationCtrl.text.trim(),
        }).eq('profile_id', uid);
      } else if (_isStaff) {
        await SupabaseConfig.client.from('staff').update({
          if (_selectedDept != null) 'department_id': _selectedDept!.id,
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
      AppHaptics.success();
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
          ? const Center(child: SupernovaBusy(label: 'Loading your details'))
          : SingleChildScrollView(
              padding: const EdgeInsetsDirectional.fromSTEB(24, 24, 24, 24),
              child: GlassCard(
                glowColor: AppColors.holoBlue,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Complete your profile', style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
                    const SizedBox(height: 6),
                    Text('A few required details are missing before you can continue.',
                        style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                    // Says out loud what the app has been doing SILENTLY. An
                    // account past the photo window already fails
                    // profile_is_complete(), so the router has been sending
                    // this person back here on every launch with no
                    // explanation of why, or of what ends it. The restriction
                    // is not new; being told about it is.
                    //
                    // Deliberately plain and unthreatening: this is mostly
                    // students who have not got around to it, not wrongdoing.
                    // It names the one thing to do and promises the outcome,
                    // and it never says "suspended" or "blocked" — words that
                    // read as an accusation for what is usually forgetfulness.
                    if (_photoWindowClosed) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.10),
                          borderRadius: AppDepth.radius(1),
                          border: Border.all(
                              color: AppColors.amber.withValues(alpha: 0.35)),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.info_outline, color: AppColors.amber, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Your account is limited for now',
                                      style: AppTextStyles.bodyMedium.copyWith(
                                          color: textPrimary,
                                          fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 2),
                                  Text(
                                      'Please add your profile photo below and finish '
                                      'the details. An admin checks each photo, and '
                                      'your account opens back up once it is approved.',
                                      style: AppTextStyles.labelSmall
                                          .copyWith(color: textSecondary)),
                                ]),
                          ),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Center(child: AvatarPicker(
                        avatarUrl: _avatarUrl,
                        initials: UserModel(id: '', email: '', fullName: _nameCtrl.text, role: 'student').initials,
                        pendingUrl: _avatarPendingUrl,
                        reviewStatus: _avatarReviewStatus,
                        reviewReason: _avatarReviewReason,
                        // my_submit_avatar() stages the photo as pending review --
                        // it does not become the live avatar_url yet, so this
                        // updates the pending state, never _avatarUrl directly.
                        onChanged: (url) => setState(() {
                          _avatarPendingUrl = url;
                          _avatarReviewStatus = url == null ? 'none' : 'pending';
                          _avatarReviewReason = null;
                        }))),
                    const SizedBox(height: 12),
                    // Future tense, same doctrine as the phone/address notice
                    // below: state the requirement, never fake a check that
                    // has not happened. A real admin looks at every photo.
                    if (_avatarReviewStatus != 'approved')
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceOf(context),
                          borderRadius: AppDepth.radius(1),
                          border: Border.all(color: AppColors.borderOf(context)),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.photo_camera_outlined, size: 16,
                              color: AppColors.textSecondaryOf(context)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(
                            'Upload a real, formal photo of yourself within 48 hours of '
                            'your account being approved — an administrator reviews it '
                            'before it appears anywhere else in AFOS.',
                            style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.textSecondaryOf(context)))),
                        ]),
                      ),
                    const SizedBox(height: 16),
                    if (_studentId.isNotEmpty) _ReadOnlyRow(label: 'Student/University ID', value: _studentId),
                    if (_email.isNotEmpty) _ReadOnlyRow(label: 'Email', value: _email),
                    const SizedBox(height: 8),
                    AfosTextField(hint: 'Full name', controller: _nameCtrl,
                        validator: (v) => AppValidators.required(v, f: 'Full name')),
                    const SizedBox(height: 16),
                    // The check is NOT built. This is written in the FUTURE
                    // tense on purpose: a mock that pretended to verify would
                    // be a false claim shown to a real person, and the
                    // deterrent comes from believing it will be checked, not
                    // from a fake tick appearing now.
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceOf(context),
                        borderRadius: AppDepth.radius(1),
                        border: Border.all(color: AppColors.borderOf(context)),
                      ),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.verified_user_outlined, size: 16,
                            color: AppColors.textSecondaryOf(context)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          'These details will be checked later — by a code sent to '
                          'your number, and by a direct call from the university. '
                          'Please enter the number and address you actually use.',
                          style: AppTextStyles.labelSmall.copyWith(
                              color: AppColors.textSecondaryOf(context)))),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    AfosTextField(hint: 'Phone number', controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        validator: (v) => AppValidators.required(v, f: 'Phone')),
                    const SizedBox(height: 16),
                    // Required now. It was optional, and 3 of 14 people had
                    // one -- an emergency contact nobody filled in is not an
                    // emergency contact.
                    AfosTextField(hint: 'Emergency contact (name + phone)',
                        controller: _emergencyCtrl,
                        validator: (v) => AppValidators.required(v, f: 'Emergency contact')),
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
                    // Staff never sees this: `_departments` is the purely
                    // ACADEMIC list (CSE, EEE, BBA, ...) — a staff member (IT,
                    // accounts, admin, ...) has no correct answer in it. Their
                    // designation dropdown right below already answers "which
                    // unit are you in".
                    if (!_isStaff) ...[
                      DropdownButtonFormField<DepartmentOption>(
                        initialValue: _selectedDept,
                        isExpanded: true,
                        decoration: InputDecoration(hintText: 'Department', filled: true,
                            fillColor: AppColors.glassFill(context),
                            border: OutlineInputBorder(borderRadius: AppDepth.radius(1),
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
                    ],
                    if (_isTeacher) ...[
                      AfosTextField(
                        hint: 'Your initial (e.g. FNB)',
                        controller: _initialCtrl,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Students find you by this. Set it and they can name you '
                        'as their advisor or project supervisor.',
                        style: AppTextStyles.labelSmall.copyWith(
                            color: AppColors.textSecondaryOf(context)),
                      ),
                      const SizedBox(height: 12),
                    ],
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
                                  border: OutlineInputBorder(borderRadius: AppDepth.radius(1),
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
                            validator: AppValidators.batch)),
                        const SizedBox(width: 12),
                        Expanded(child: AfosTextField(hint: 'Section (e.g. A)', controller: _sectionCtrl,
                            validator: AppValidators.section)),
                      ]),
                      const SizedBox(height: 20),
                      Text('Semester: ${_sem.toInt()}', style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
                      Slider(value: _sem, min: 1, max: 12, divisions: 11,
                          activeColor: AppColors.holoBlue, label: '${_sem.toInt()}',
                          onChanged: (v) => setState(() => _sem = v)),
                      const SizedBox(height: 16),
                      // The term admitted in. There is no column this can be
                      // derived from -- the university IDs on file are not
                      // consistently formatted, so no term code can be parsed
                      // out of them. It has to be asked.
                      Row(children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _admissionSeason,
                            isExpanded: true,
                            decoration: InputDecoration(hintText: 'Admission season',
                                filled: true,
                                border: OutlineInputBorder(borderRadius: AppDepth.radius(1))),
                            items: const [
                              DropdownMenuItem(value: 'spring', child: Text('Spring')),
                              DropdownMenuItem(value: 'summer', child: Text('Summer')),
                              DropdownMenuItem(value: 'fall', child: Text('Fall')),
                            ],
                            onChanged: (v) => setState(() => _admissionSeason = v),
                            validator: (v) => v == null ? 'Admission season is required' : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AfosTextField(hint: 'Admission year',
                              controller: _admissionYearCtrl,
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                final y = int.tryParse((v ?? '').trim());
                                if (y == null) return 'Admission year is required';
                                if (y < 2000 || y > 2100) return 'Enter a 4-digit year';
                                return null;
                              }),
                        ),
                      ]),
                    ],
                    if (!_isAdminTier) ...[
                      const SizedBox(height: 16),
                      _JoinDateField(
                        value: _joinedOn,
                        errorText: _joinedOnError,
                        isStudent: !_isTeacher && !_isStaff && !_isAdminTier,
                        onPicked: (d) => setState(() { _joinedOn = d; _joinedOnError = null; }),
                      ),
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
                          borderRadius: AppDepth.radius(1),
                          border: Border.all(color: AppColors.green.withValues(alpha: 0.3)),
                        ),
                        child: Row(children: [
                          const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Location confirmed',
                              style: AppTextStyles.bodyMedium.copyWith(color: textPrimary))),
                          Flexible(
                            child: TextButton(
                                onPressed: _capturingLocation ? null : _confirmLocation,
                                child: const Text('Refresh', maxLines: 1)),
                          ),
                        ]),
                      )
                    else if (kIsWeb && _locationSkippedOnWeb)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceOf(context),
                          borderRadius: AppDepth.radius(1),
                          border: Border.all(color: AppColors.borderOf(context)),
                        ),
                        child: Row(children: [
                          Icon(Icons.info_outline_rounded, size: 18, color: textSecondary),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Location skipped — add it later from Transport.',
                              style: AppTextStyles.bodyMedium.copyWith(color: textSecondary))),
                          Flexible(
                            child: TextButton(
                                onPressed: _capturingLocation
                                    ? null
                                    : () {
                                        setState(() => _locationSkippedOnWeb = false);
                                        _confirmLocation();
                                      },
                                child: const Text('Add now', maxLines: 1)),
                          ),
                        ]),
                      )
                    else
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        OutlinedButton.icon(
                          onPressed: _capturingLocation ? null : _confirmLocation,
                          icon: _capturingLocation
                              ? const SizedBox(width: 16, height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.my_location_rounded),
                          label: Text(_capturingLocation ? 'Getting location…' : 'Confirm my location'),
                        ),
                        // Web only -- see the field's doc comment. Native GPS
                        // permission handling is reliable enough to stay a
                        // hard requirement; browser prompts are not.
                        if (kIsWeb) ...[
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: _capturingLocation
                                ? null
                                : () => setState(() => _locationSkippedOnWeb = true),
                            child: const Text('Skip for now'),
                          ),
                        ],
                      ]),
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
          child: Padding(padding: const EdgeInsetsDirectional.only(start: 8),
              child: Text(o.title, overflow: TextOverflow.ellipsis))));
    }
    return items;
  }
}

/// The join date, taken from the ID card. A picker rather than a text field:
/// a typed date is the most reliable way there is to get garbage into a date
/// column, and this one is about to become a grouping axis in the admin
/// directory, where a garbage year becomes a garbage section header.
class _JoinDateField extends StatelessWidget {
  final DateTime? value;
  final String? errorText;
  final bool isStudent;
  final ValueChanged<DateTime> onPicked;

  const _JoinDateField({
    required this.value,
    required this.errorText,
    required this.isStudent,
    required this.onPicked,
  });

  @override
  Widget build(BuildContext context) {
    final label = isStudent ? 'Join date (from your ID card)' : 'Joining date';
    return InkWell(
      borderRadius: AppDepth.radius(1),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime(now.year - 1, now.month, now.day),
          firstDate: DateTime(2000),
          lastDate: now,
          helpText: isStudent
              ? 'Date printed on your ID card'
              : 'Date you joined the university',
        );
        if (picked != null) onPicked(picked);
      },
      // 48dp floor: a tap target has to be reachable, and an InputDecorator
      // sizes to its text.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: InputDecorator(
          decoration: InputDecoration(
            filled: true,
            errorText: errorText,
            border: OutlineInputBorder(borderRadius: AppDepth.radius(1)),
          ),
          child: Row(children: [
            Icon(Icons.badge_outlined, size: 18,
                color: AppColors.textSecondaryOf(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value == null
                    ? label
                    : '$label: ${value!.day.toString().padLeft(2, '0')}'
                        '/${value!.month.toString().padLeft(2, '0')}/${value!.year}',
                style: AppTextStyles.bodyMedium.copyWith(
                    color: value == null
                        ? AppColors.textSecondaryOf(context)
                        : AppColors.textPrimaryOf(context)),
              ),
            ),
            Icon(Icons.calendar_today_outlined, size: 16,
                color: AppColors.textSecondaryOf(context)),
          ]),
        ),
      ),
    );
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
          border: OutlineInputBorder(borderRadius: AppDepth.radius(1),
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
      onTap: () { AppHaptics.selection(); onTap(); },
      // Vertical padding was 12 around 13px text — a ~37dp target.
      child: Container(padding: const EdgeInsets.symmetric(vertical: AppSpace.lg),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: selected ? AppColors.holoBlue : Colors.transparent,
              borderRadius: AppDepth.radius(1),
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
