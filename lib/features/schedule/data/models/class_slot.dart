class ClassSlot {
  final String id, subject, teacherName, roomNumber, building, department;
  final int dayOfWeek, creditHours, semester;
  final String startTime, endTime;
  final bool isCancelled;
  final String? cancelledReason, subjectCode;

  const ClassSlot({
    required this.id, required this.subject, required this.teacherName,
    required this.roomNumber, required this.building, required this.department,
    required this.dayOfWeek, required this.creditHours, required this.semester,
    required this.startTime, required this.endTime, required this.isCancelled,
    this.cancelledReason, this.subjectCode,
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
  );
}
