class Mark {
  final String id, enrollmentId;
  final double attendance, quiz, assignment, midterm, finalMarks;
  final double? totalMarks, gradePoint;
  final String? letterGrade;
  final bool isPublished;

  const Mark({
    required this.id, required this.enrollmentId,
    this.attendance=0, this.quiz=0, this.assignment=0,
    this.midterm=0, this.finalMarks=0,
    this.totalMarks, this.letterGrade, this.gradePoint,
    this.isPublished=false,
  });

  factory Mark.fromJson(Map<String, dynamic> j) => Mark(
    id: j['id'],
    enrollmentId: j['enrollment_id'],
    attendance: (j['attendance_marks'] as num).toDouble(),
    quiz: (j['quiz_marks'] as num).toDouble(),
    assignment: (j['assignment_marks'] as num).toDouble(),
    midterm: (j['midterm_marks'] as num).toDouble(),
    finalMarks: (j['final_marks'] as num).toDouble(),
    totalMarks: (j['total_marks'] as num?)?.toDouble(),
    letterGrade: j['letter_grade'],
    gradePoint: (j['grade_point'] as num?)?.toDouble(),
    isPublished: j['is_published'] ?? false,
  );
}
