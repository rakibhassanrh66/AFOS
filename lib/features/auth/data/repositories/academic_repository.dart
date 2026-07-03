import '../../../../config/supabase_config.dart';

class DepartmentOption {
  final String id, name, code;
  const DepartmentOption({required this.id, required this.name, required this.code});
  factory DepartmentOption.fromJson(Map<String, dynamic> j) =>
      DepartmentOption(id: j['id'] as String, name: j['name'] as String, code: j['code'] as String);
}

class ProgramOption {
  final String id, name;
  final int? totalSemesters;
  final String? semesterSystem; // 'bi' | 'tri'
  const ProgramOption({required this.id, required this.name, this.totalSemesters, this.semesterSystem});
  factory ProgramOption.fromJson(Map<String, dynamic> j) => ProgramOption(
        id: j['id'] as String,
        name: j['name'] as String,
        totalSemesters: j['total_semesters'] as int?,
        semesterSystem: j['semester_system'] as String?,
      );
  /// Falls back to a generic 1-12 range until an admin sets the real
  /// per-program figure in the `programs` table.
  int get semesterRange => totalSemesters ?? 12;
}

class AcademicRepository {
  final _client = SupabaseConfig.client;

  Future<List<DepartmentOption>> fetchDepartments() async {
    final res = await _client.from('departments').select('id,name,code').order('name');
    return (res as List).map((e) => DepartmentOption.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ProgramOption>> fetchPrograms(String departmentId) async {
    final res = await _client
        .from('programs')
        .select('id,name,total_semesters,semester_system')
        .eq('department_id', departmentId)
        .order('name');
    return (res as List).map((e) => ProgramOption.fromJson(e as Map<String, dynamic>)).toList();
  }
}
