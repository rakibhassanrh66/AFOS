class UserModel {
  final String id, email, fullName;
  final String role;
  final String? avatarUrl, phone;
  final Map<String, dynamic>? studentData;
  final Map<String, dynamic>? teacherData;
  // Flat profiles-column fallbacks (populated even when v8 joins are null)
  final String? _rawStudentId;
  final String? _rawDepartment;
  final int? _rawSemester;

  const UserModel({
    required this.id, required this.email, required this.fullName,
    required this.role, this.avatarUrl, this.phone,
    this.studentData, this.teacherData,
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
      avatarUrl: j['photo_url'] as String? ?? j['avatar_url'] as String?,
      phone: j['phone'] as String?,
      studentData: studentData,
      teacherData: teacherData,
      // university_id is the v8 profiles column; fall back to flat student_id
      rawStudentId: j['university_id'] as String? ?? j['student_id'] as String?,
      rawDepartment: j['department'] as String?,
      rawSemester: j['semester'] as int?,
    );
  }

  String get studentId =>
      studentData?['university_id'] as String? ?? _rawStudentId ?? '';
  String get department =>
      studentData?['department_id'] as String? ??
      teacherData?['department_id'] as String? ??
      _rawDepartment ?? '';
  int get semester =>
      studentData?['current_semester_no'] as int? ?? _rawSemester ?? 1;

  String get firstName => fullName.split(' ').first;
  String get initials {
    final p = fullName.trim().split(' ');
    return p.length >= 2
        ? '${p[0][0]}${p[1][0]}'.toUpperCase()
        : fullName.isNotEmpty ? fullName[0].toUpperCase() : 'U';
  }

  bool get isAdmin => role == 'super_admin';
  bool get isStudent => role == 'student';
  bool get isTeacher => role == 'teacher';

  String? get batch => studentData?['batch_label'] as String?;
  String? get section => studentData?['section'] as String?;
  String? get designation => teacherData?['designation'] as String?;
}
