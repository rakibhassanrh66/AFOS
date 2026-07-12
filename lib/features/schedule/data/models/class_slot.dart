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
    // schedule_slots.lab_subgroup is NOT NULL at the DB layer (0 is a real
    // "not a lab subgroup" sentinel, needed so the DB's own uniqueness check
    // works for non-lab rows) — translate that sentinel back to null here so
    // every existing `labSubgroup != null` "is this a subgroup" check above
    // this layer keeps working unchanged.
    labSubgroup: (j['lab_subgroup'] as int?) == 0 ? null : j['lab_subgroup'] as int?,
  );

  /// True if [other] overlaps this slot on the same day (used for the
  /// retake-vs-regular-class conflict warning).
  bool overlaps(ClassSlot other) =>
      dayOfWeek == other.dayOfWeek && startTime.compareTo(other.endTime) < 0 && other.startTime.compareTo(endTime) < 0;

  ClassSlot copyWith({String? endTime}) => ClassSlot(
    id: id, subject: subject, teacherName: teacherName, roomNumber: roomNumber,
    building: building, department: department, dayOfWeek: dayOfWeek,
    creditHours: creditHours, semester: semester, startTime: startTime,
    endTime: endTime ?? this.endTime, isCancelled: isCancelled,
    cancelledReason: cancelledReason, subjectCode: subjectCode, batch: batch,
    section: section, teacherInitial: teacherInitial, roomType: roomType,
    isLab: isLab, isRetake: isRetake, labSubgroup: labSubgroup,
  );
}

/// A real DIU class routine prints one row per room per day, but a lab that
/// runs 3 hours (a common length) spans TWO of the university's 1.5-hour
/// time-slot columns — stored as two separate consecutive rows (needed for
/// accurate per-slot conflict detection against retakes). Displaying both
/// as separate back-to-back cards reads as a duplicate/wrong-time error
/// (confirmed live: a real student mistook their own 8:30-11:30 lab, shown
/// as two cards, for a scheduling mistake). Merges runs of consecutive
/// same-course/teacher/room/subgroup slots into one card spanning the full
/// block — display-only, the underlying (unmerged) list is still what
/// conflict detection and pin/unpin operate on.
///
/// Scans the whole `merged` list for a continuation, not just its last
/// element — a plain "day view" list only ever holds one section's own
/// classes so the two halves of a lab are always list-adjacent, but the
/// course-code SEARCH results list mixes every section teaching that code,
/// and another section's row tied at the exact same start_time can land
/// between a lab's two halves after sorting. Confirmed live: CSE431's
/// batch 63/F Group 2 lab (14:30-16:00 + 16:00-17:30) failed to merge in
/// search results because 64/E and 64/H's own unrelated 14:30 rows sorted
/// in between, even though day_of_week/start_time were both correctly
/// ascending.
List<ClassSlot> mergeAdjacentSlots(List<ClassSlot> sorted) {
  final merged = <ClassSlot>[];
  for (final s in sorted) {
    final matchIndex = merged.indexWhere((m) =>
        m.dayOfWeek == s.dayOfWeek &&
        m.endTime == s.startTime &&
        m.subjectCode == s.subjectCode &&
        m.teacherName == s.teacherName &&
        m.building == s.building &&
        m.roomNumber == s.roomNumber &&
        m.batch == s.batch &&
        m.section == s.section &&
        m.labSubgroup == s.labSubgroup &&
        m.isRetake == s.isRetake &&
        m.isCancelled == s.isCancelled);
    if (matchIndex != -1) {
      merged[matchIndex] = merged[matchIndex].copyWith(endTime: s.endTime);
    } else {
      merged.add(s);
    }
  }
  return merged;
}
