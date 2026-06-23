class Course {
  final String id, code, title;
  final int creditHours;
  final String courseType;

  const Course({required this.id, required this.code, required this.title, required this.creditHours, required this.courseType});

  factory Course.fromJson(Map<String, dynamic> j) => Course(
    id: j['id'],
    code: j['code'],
    title: j['title'],
    creditHours: j['credit_hours'],
    courseType: j['course_type'],
  );
}
