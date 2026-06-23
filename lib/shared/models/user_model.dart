class UserModel {
  final String id, email, fullName;
  final String role; // Role name (e.g., 'student', 'super_admin')
  final String? avatarUrl, phone;
  final Map<String, dynamic>? studentData; // Holds student-specific fields
  final Map<String, dynamic>? teacherData; // Holds teacher-specific fields

  const UserModel({
    required this.id, required this.email, required this.fullName,
    required this.role, this.avatarUrl, this.phone,
    this.studentData, this.teacherData,
  });

  factory UserModel.fromJson(Map<String,dynamic> j) => UserModel(
    id: j['id'] as String,
    email: j['email'] as String? ?? '',
    fullName: j['full_name'] as String? ?? '',
    role: j['roles']?['name'] as String? ?? 'student',
    avatarUrl: j['photo_url'] as String?,
    phone: j['phone'] as String?,
    studentData: j['students'] as Map<String, dynamic>?,
    teacherData: j['teachers'] as Map<String, dynamic>?,
  );
  
  // Helpers to safely access nested data
  String get studentId => studentData?['university_id'] ?? '';
  String get department => studentData?['department_id'] ?? teacherData?['department_id'] ?? '';
  int get semester => studentData?['current_semester_no'] ?? 1;
  
  String get firstName => fullName.split(' ').first;
  String get initials {
    final p = fullName.trim().split(' ');
    return p.length>=2?'${p[0][0]}${p[1][0]}'.toUpperCase():fullName.isNotEmpty?fullName[0].toUpperCase():'U';
  }
  
  bool get isAdmin => role == 'super_admin';
  bool get isStudent => role == 'student';
}
