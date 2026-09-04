/// Models for advising and final-year-project supervision.
///
/// Both are the same database row with a different [LinkKind], which is why
/// there is one model here and not two. The only thing that differs between
/// them is how much of the student the teacher may read, and that decision is
/// made in `student_profile_for_link` on the server — by the time a
/// [LinkedStudent] reaches this file the restricted fields are already null.
library;

/// Which kind of pairing this is.
enum LinkKind {
  advisor,
  fydp;

  static LinkKind parse(String? raw) =>
      raw == 'fydp' ? LinkKind.fydp : LinkKind.advisor;

  String get wire => name;

  /// What to call the teacher on this side of the link, in copy.
  String get teacherNoun => this == LinkKind.fydp ? 'Supervisor' : 'Advisor';

  /// What to call the whole thing, in a heading.
  String get title =>
      this == LinkKind.fydp ? 'Final Year Design Project' : 'Academic Advisor';
}

/// Where a pairing has got to.
///
/// `declined` and `ended` are both terminal, and deliberately distinct: a
/// student who was declined needs to see a reason, and a student whose link
/// simply ended does not.
enum LinkStatus {
  pending,
  active,
  declined,
  ended;

  static LinkStatus parse(String? raw) => switch (raw) {
        'active' => LinkStatus.active,
        'declined' => LinkStatus.declined,
        'ended' => LinkStatus.ended,
        _ => LinkStatus.pending,
      };

  bool get isLive => this == LinkStatus.pending || this == LinkStatus.active;
}

/// A teacher as `resolve_teacher_initial` returns them — the card a student
/// sees while typing, BEFORE any link exists.
///
/// Deliberately small. This is the only view of a teacher a student who has
/// asked for nobody can obtain, so it carries what the university already
/// publishes about a member of faculty and nothing else.
class TeacherCard {
  final String teacherId;
  final String fullName;
  final String? initial;
  final String? designation;
  final String? department;
  final String? avatarUrl;
  final String? email;
  final String? phone;

  /// True when today falls inside a row of `teacher_leave`. The card says so
  /// rather than letting a student write into silence.
  final bool onLeave;

  const TeacherCard({
    required this.teacherId,
    required this.fullName,
    this.initial,
    this.designation,
    this.department,
    this.avatarUrl,
    this.email,
    this.phone,
    this.onLeave = false,
  });

  factory TeacherCard.fromJson(Map<String, dynamic> j) => TeacherCard(
        teacherId: j['teacher_id'] as String,
        fullName: (j['full_name'] as String?) ?? 'Unnamed',
        initial: _clean(j['teacher_initial']),
        designation: _clean(j['designation']),
        department: _clean(j['department']),
        avatarUrl: _clean(j['avatar_url']),
        email: _clean(j['email']),
        phone: _clean(j['phone']),
        onLeave: j['on_leave'] == true,
      );
}

/// One pairing, as the student's own row.
class TeacherLink {
  final String id;
  final LinkKind kind;
  final LinkStatus status;
  final String teacherId;
  final String studentId;
  final String? declineReason;
  final DateTime? requestedAt;

  const TeacherLink({
    required this.id,
    required this.kind,
    required this.status,
    required this.teacherId,
    required this.studentId,
    this.declineReason,
    this.requestedAt,
  });

  factory TeacherLink.fromJson(Map<String, dynamic> j) => TeacherLink(
        id: j['id'] as String,
        kind: LinkKind.parse(j['kind'] as String?),
        status: LinkStatus.parse(j['status'] as String?),
        teacherId: j['teacher_id'] as String,
        studentId: j['student_id'] as String,
        declineReason: _clean(j['decline_reason']),
        requestedAt: DateTime.tryParse('${j['requested_at'] ?? ''}'),
      );
}

/// A student as their teacher may read them, already scoped by the server.
///
/// [emergencyContact] and the three address fields are null for an FYDP
/// supervisor by design — not hidden by this class, absent from the row.
/// [advisorName] is the mirror of that: populated only for FYDP, so a
/// supervisor knows who to escalate to without gaining the advisor's access.
class LinkedStudent {
  final String studentId;
  final String fullName;
  final String? universityId;
  final String? batch;
  final String? section;
  final int? semester;
  final double? cgpa;
  final String? phone;
  final String? email;
  final String? avatarUrl;
  final String? gender;
  final String? emergencyContact;
  final String? division;
  final String? district;
  final String? upazila;
  final String? advisorName;
  final String? advisorInitial;

  const LinkedStudent({
    required this.studentId,
    required this.fullName,
    this.universityId,
    this.batch,
    this.section,
    this.semester,
    this.cgpa,
    this.phone,
    this.email,
    this.avatarUrl,
    this.gender,
    this.emergencyContact,
    this.division,
    this.district,
    this.upazila,
    this.advisorName,
    this.advisorInitial,
  });

  factory LinkedStudent.fromJson(Map<String, dynamic> j) => LinkedStudent(
        studentId: j['student_id'] as String,
        fullName: (j['full_name'] as String?) ?? 'Unnamed',
        universityId: _clean(j['university_id']),
        batch: _clean(j['batch']),
        section: _clean(j['section']),
        semester: j['semester'] as int?,
        cgpa: (j['cgpa'] as num?)?.toDouble(),
        phone: _clean(j['phone']),
        email: _clean(j['email']),
        avatarUrl: _clean(j['avatar_url']),
        gender: _clean(j['gender']),
        emergencyContact: _clean(j['emergency_contact']),
        division: _clean(j['permanent_division']),
        district: _clean(j['permanent_district']),
        upazila: _clean(j['permanent_upazila']),
        advisorName: _clean(j['advisor_name']),
        advisorInitial: _clean(j['advisor_initial']),
      );

  /// 'Dhaka, Savar' — the parts that exist, in the order an address reads.
  /// Empty when the supervisor scope stripped them, which the UI renders as
  /// "not shared" rather than as a blank row.
  String get address =>
      [upazila, district, division].where((v) => (v ?? '').isNotEmpty).join(', ');
}

/// A blank string is not a value. This is the same normalisation the rest of
/// the app applies at its boundaries — `department = ''` once defeated a
/// `?? 'default'` and rendered an empty chip.
String? _clean(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}
