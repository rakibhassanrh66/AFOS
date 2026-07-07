/// Anonymized chat display names — a sender is never shown their real name
/// in dept/club chat. Dept-chat format: firstname_batch_last4universityid_
/// section_dept (e.g. rakib_68_1554_e_cse). Club-chat format (pass
/// [designation], the sender's club_members.role): firstname_batch_dept_
/// designation (e.g. rakib_68_cse_president). [profile] is a raw Supabase
/// row from a `profiles(...)` embed, optionally itself embedding
/// `students(batch_label,section)`.
String anonymizedChatName(Map<String, dynamic> profile, {String? designation}) {
  final fullName = profile['full_name'] as String? ?? '';
  final first = fullName.trim().isEmpty
      ? 'user' : fullName.trim().split(RegExp(r'\s+')).first.toLowerCase();
  final dept = (profile['department'] as String? ?? '').toLowerCase();
  final universityId = profile['university_id'] as String?;

  final rawStudents = profile['students'];
  Map<String, dynamic>? student;
  if (rawStudents is List && rawStudents.isNotEmpty) {
    student = rawStudents.first as Map<String, dynamic>?;
  } else if (rawStudents is Map<String, dynamic>) {
    student = rawStudents;
  }
  final batch = student?['batch_label'] as String?;
  final section = student?['section'] as String?;

  final parts = <String>[first];
  if (batch != null && batch.isNotEmpty) parts.add(batch);

  if (designation != null && designation.isNotEmpty) {
    if (dept.isNotEmpty) parts.add(dept);
    parts.add(designation.toLowerCase());
    return parts.join('_');
  }

  if (universityId != null && universityId.isNotEmpty) {
    parts.add(universityId.length >= 4
        ? universityId.substring(universityId.length - 4) : universityId);
  }
  if (section != null && section.isNotEmpty) parts.add(section);
  if (dept.isNotEmpty) parts.add(dept);
  return parts.join('_');
}
