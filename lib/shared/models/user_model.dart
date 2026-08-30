class UserModel {
  final String id, email, fullName;
  final String role;
  final String? avatarUrl, phone, emergencyContact;
  final bool profileCompleted;

  /// A submitted photo awaiting admin review, if any.
  final String? avatarPendingUrl;

  /// 'none' | 'pending' | 'approved' | 'rejected'.
  final String? avatarReviewStatus;
  final String? avatarReviewReason;

  /// Stamped the instant `is_verified` first became true — anchors the 48h
  /// mandatory-photo grace period.
  final DateTime? verifiedAt;

  final Map<String, dynamic>? studentData;
  final Map<String, dynamic>? teacherData;
  final Map<String, dynamic>? staffData;
  // Flat profiles-column fallbacks (populated even when v8 joins are null)
  final String? _rawStudentId;
  final String? _rawDepartment;
  final int? _rawSemester;

  const UserModel({
    required this.id, required this.email, required this.fullName,
    required this.role, this.avatarUrl, this.phone, this.emergencyContact,
    this.profileCompleted = true,
    this.avatarPendingUrl, this.avatarReviewStatus, this.avatarReviewReason, this.verifiedAt,
    this.studentData, this.teacherData, this.staffData,
    String? rawStudentId, String? rawDepartment, int? rawSemester,
  })  : _rawStudentId = rawStudentId,
        _rawDepartment = rawDepartment,
        _rawSemester = rawSemester;

  factory UserModel.fromJson(Map<String,dynamic> j) {
    // PostgREST returns reverse-FK embeds as arrays; take first element if present.
    Map<String, dynamic>? studentData;
    final rawStudents = j['students'];
    if (rawStudents is List && rawStudents.isNotEmpty) {
      studentData = rawStudents.first as Map<String, dynamic>?;
    } else if (rawStudents is Map<String, dynamic>) {
      studentData = rawStudents;
    }

    Map<String, dynamic>? teacherData;
    final rawTeachers = j['teachers'];
    if (rawTeachers is List && rawTeachers.isNotEmpty) {
      teacherData = rawTeachers.first as Map<String, dynamic>?;
    } else if (rawTeachers is Map<String, dynamic>) {
      teacherData = rawTeachers;
    }

    Map<String, dynamic>? staffData;
    final rawStaff = j['staff'];
    if (rawStaff is List && rawStaff.isNotEmpty) {
      staffData = rawStaff.first as Map<String, dynamic>?;
    } else if (rawStaff is Map<String, dynamic>) {
      staffData = rawStaff;
    }

    String? roleName;
    final rawRoles = j['roles'];
    if (rawRoles is List && rawRoles.isNotEmpty) {
      roleName = (rawRoles.first as Map<String, dynamic>?)?['name'] as String?;
    } else if (rawRoles is Map<String, dynamic>) {
      roleName = rawRoles['name'] as String?;
    }

    return UserModel(
      id: j['id'] as String,
      email: j['email'] as String? ?? '',
      fullName: j['full_name'] as String? ?? '',
      // Use joined roles.name first; fall back to flat profiles.role column.
      role: roleName ?? j['role'] as String? ?? 'student',
      avatarUrl: j['avatar_url'] as String?,
      phone: j['phone'] as String?,
      emergencyContact: j['emergency_contact'] as String?,
      profileCompleted: j['profile_completed'] as bool? ?? true,
      avatarPendingUrl: j['avatar_pending_url'] as String?,
      avatarReviewStatus: j['avatar_review_status'] as String?,
      avatarReviewReason: j['avatar_review_reason'] as String?,
      verifiedAt: j['verified_at'] != null ? DateTime.tryParse(j['verified_at'] as String) : null,
      studentData: studentData,
      teacherData: teacherData,
      staffData: staffData,
      // university_id is the v8 profiles column; fall back to flat student_id
      rawStudentId: j['university_id'] as String? ?? j['student_id'] as String?,
      rawDepartment: j['department'] as String?,
      rawSemester: j['semester'] as int?,
    );
  }

  String get studentId =>
      studentData?['university_id'] as String? ?? _rawStudentId ?? '';
  // _rawDepartment (profiles.department, e.g. "CSE") is the human-readable
  // code — students/teachers.department_id is a UUID foreign key and must
  // never be shown directly in the UI.
  String get department => _rawDepartment ?? '';
  int get semester =>
      studentData?['current_semester_no'] as int? ?? _rawSemester ?? 1;

  String get firstName => fullName.split(' ').first;
  String get initials {
    final p = fullName.trim().split(' ');
    return p.length >= 2
        ? '${p[0][0]}${p[1][0]}'.toUpperCase()
        : fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U';
  }

  bool get isAdmin => const ['admin', 'super_admin', 'dept_admin'].contains(role);
  bool get isSuperAdmin => role == 'super_admin';
  bool get isStudent => role == 'student';
  bool get isTeacher => role == 'teacher';
  bool get isStaff => role == 'staff';

  String? get batch => studentData?['batch_label'] as String?;
  String? get section => studentData?['section'] as String?;
  String? get designation => teacherData?['designation'] as String? ?? staffData?['designation'] as String?;
  String? get staffCategory => staffData?['category'] as String?;

  /// Free-text office/section for staff with no ACADEMIC department
  /// (Registrar, Accounts, IT). See staff.office.
  String? get office => staffData?['office'] as String?;

  /// Where this person belongs, for display: the academic department code when
  /// there is one, otherwise the office. Null when neither is recorded, so a
  /// caller can omit the field entirely rather than draw an empty one.
  ///
  /// Both halves are normalised through [_orNull] because a blank STRING is
  /// exactly what caused the bug this exists to fix — staff rows carried
  /// department = '' and the menu drew a chip with no text in it.
  String? get affiliation => _orNull(department) ?? _orNull(office);

  static String? _orNull(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}
