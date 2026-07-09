class ClassSlot {
  final String id, subject, teacherName, roomNumber, building, department;
  final int dayOfWeek, creditHours, semester;
  final String startTime, endTime;
  final bool isCancelled;
  final String? cancelledReason, subjectCode, batch, section, teacherInitial;
  final String? roomType;
  final bool isLab, isRetake;
  final int? labSubgroup;

  const ClassSlot({
    required this.id, required this.subject, required this.teacherName,
    required this.roomNumber, required this.building, required this.department,
    required this.dayOfWeek, required this.creditHours, required this.semester,
    required this.startTime, required this.endTime, required this.isCancelled,
    this.cancelledReason, this.subjectCode, this.batch, this.section, this.teacherInitial,
    this.roomType, this.isLab = false, this.isRetake = false, this.labSubgroup,
  });

  factory ClassSlot.fromJson(Map<String,dynamic> j) => ClassSlot(
    id: j['id'] as String,
    subject: j['subject'] as String? ?? '',
    subjectCode: j['subject_code'] as String?,
    teacherName: j['teacher_name'] as String? ?? '',
    roomNumber: j['room_number'] as String? ?? '',
    building: j['building'] as String? ?? '',
    department: j['department'] as String? ?? '',
    dayOfWeek: j['day_of_week'] as int? ?? 0,
    creditHours: j['credit_hours'] as int? ?? 3,
    semester: j['semester'] as int? ?? 1,
    startTime: j['start_time'] as String? ?? '08:00',
    endTime: j['end_time'] as String? ?? '09:30',
    isCancelled: j['is_cancelled'] as bool? ?? false,
    cancelledReason: j['cancelled_reason'] as String?,
    batch: j['batch'] as String?,
    section: j['section'] as String?,
    teacherInitial: j['teacher_initial'] as String?,
    roomType: j['room_type'] as String?,
    isLab: j['is_lab'] as bool? ?? false,
    isRetake: j['is_retake'] as bool? ?? false,
    labSubgroup: j['lab_subgroup'] as int?,
  );

  /// True if [other] overlaps this slot on the same day (used for the
  /// retake-vs-regular-class conflict warning).
  bool overlaps(ClassSlot other) =>
      dayOfWeek == other.dayOfWeek && startTime.compareTo(other.endTime) < 0 && other.startTime.compareTo(endTime) < 0;
}
