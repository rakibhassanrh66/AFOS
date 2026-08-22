import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_icons.dart';

/// What a person can actually do, in one place.
///
/// WHY THIS EXISTS. Until now the app answered "what can this person do" in two
/// places that did not agree.
///
/// `slide_menu.dart` answered it correctly: a per-role base list plus
/// `delegatedRoutes(grants)`, pinned by 29 tests. The dashboard answered it by
/// subtracting four tiles:
///
///     static const _studentOnlyModules = {'Hall','Payment','Exam Seats','Library'};
///     _user?.role == 'student' ? _allModules
///                              : _allModules.where((m) => !_studentOnlyModules...)
///
/// — and never read `PermissionSession` at all. So a staff member, a delegated
/// officer, a teacher and an exam controller all landed on the SAME eight
/// student-facing tiles. Routine upload, hall management, CR approval, marks
/// entry, the activity log: invisible. Not because the permission was missing,
/// but because the home screen had never been told roles exist.
///
/// This file is that answer, once. The menu, the web sidebar, the role consoles
/// and the command palette all read it, so a newly granted area appears in
/// every one of them without anyone remembering to edit a second list.
///
/// A NOTE ON WHERE CAPABILITY COMES FROM. It is not purely permissions.
/// Measured against the live database, `role_permissions` has rows for only
/// three roles — super_admin (23), admin (4), dept_admin (4). `teacher`,
/// `staff`, `student` and `exam_controller` hold ZERO role-derived permissions.
/// A teacher's register, marks entry and offerings are gated by role checks in
/// RLS and the router, not by a permission row. So capability = what the role
/// does + what has been delegated, and any model built on grants alone would
/// show a teacher an empty app.
enum CapabilityGroup {
  /// The person's own record and account.
  personal,

  /// Teaching and study: timetable, offerings, attendance, marks.
  academics,

  /// Shared campus services anyone may use.
  campus,

  /// Running something on behalf of the university.
  operations,

  /// Watching what other people did with the authority they were given.
  oversight,
}

extension CapabilityGroupLabel on CapabilityGroup {
  String get label => switch (this) {
        CapabilityGroup.personal => 'You',
        CapabilityGroup.academics => 'Academics',
        CapabilityGroup.campus => 'Campus',
        CapabilityGroup.operations => 'Operations',
        CapabilityGroup.oversight => 'Oversight',
      };

  /// Ordering for sidebars and consoles: what you own, then what you study or
  /// teach, then shared services, then what you run, then what you watch.
  int get order => switch (this) {
        CapabilityGroup.personal => 0,
        CapabilityGroup.academics => 1,
        CapabilityGroup.campus => 2,
        CapabilityGroup.operations => 3,
        CapabilityGroup.oversight => 4,
      };
}

@immutable
class AppCapability {
  final String label;
  final String route;
  final IconData icon;
  final Color accent;
  final CapabilityGroup group;

  /// True when this arrived through `user_permissions` rather than through the
  /// role. Surfaced in the UI because "you were given this" is a different
  /// fact from "this comes with your job", and a delegate who cannot tell them
  /// apart cannot tell what they would lose if the grant were revoked.
  final bool delegated;

  /// One line describing what the screen is for. The mobile dashboard tiles
  /// already carried these; they are worth keeping because a grid of twelve
  /// unlabelled icons is a memory test.
  final String? hint;

  const AppCapability({
    required this.label,
    required this.route,
    required this.icon,
    required this.accent,
    required this.group,
    this.delegated = false,
    this.hint,
  });

  AppCapability asDelegated() => AppCapability(
        label: label, route: route, icon: icon, accent: accent,
        group: group, delegated: true, hint: hint,
      );
}

// ---------------------------------------------------------------------------
// The catalogue. One definition per screen, referenced by every list below, so
// a route, icon or colour cannot drift between the menu and the dashboard the
// way Mentorship's did (a stray Color(0xFF60A5FA) in the menu that disagreed
// with AppColors.moduleColors['mentorship']).
// ---------------------------------------------------------------------------

class Caps {
  Caps._();

  // -- personal ------------------------------------------------------------
  static const dashboard = AppCapability(
      label: 'Dashboard', route: '/home', icon: AppIcons.dashboard,
      accent: AppColors.blue, group: CapabilityGroup.personal);
  static const profile = AppCapability(
      label: 'Profile', route: '/profile', icon: Icons.person_rounded,
      accent: AppColors.holoBlue, group: CapabilityGroup.personal);
  static const settings = AppCapability(
      label: 'Settings', route: '/settings', icon: AppIcons.settings,
      accent: AppColors.textSecondary, group: CapabilityGroup.personal);
  static const notifications = AppCapability(
      label: 'Notifications', route: '/notifications', icon: AppIcons.notifications,
      accent: AppColors.red, group: CapabilityGroup.personal, hint: 'Latest notices');
  static const feedback = AppCapability(
      label: 'Feedback & Ideas', route: '/feedback',
      icon: Icons.lightbulb_outline_rounded, accent: AppColors.teal,
      group: CapabilityGroup.personal);
  static const vrId = AppCapability(
      label: 'VR-ID', route: '/vr-id', icon: AppIcons.vrId,
      accent: AppColors.green, group: CapabilityGroup.personal, hint: 'Campus identity');
  static const portal = AppCapability(
      label: 'DIU Portal', route: '/portal', icon: Icons.language_rounded,
      accent: AppColors.holoBlue, group: CapabilityGroup.personal, hint: 'Ledger, waiver, cards');
  static const library = AppCapability(
      label: 'Library', route: '/library', icon: AppIcons.library,
      accent: AppColors.indigo, group: CapabilityGroup.personal, hint: 'Borrowed books');
  static const hall = AppCapability(
      label: 'Hall Allocation', route: '/hall', icon: AppIcons.hall,
      accent: AppColors.amber, group: CapabilityGroup.personal, hint: 'Application status');
  static const payment = AppCapability(
      label: 'Payment', route: '/payment', icon: AppIcons.payment,
      accent: AppColors.gold, group: CapabilityGroup.personal, hint: 'Check dues');
  static const examSeat = AppCapability(
      label: 'Exam Seat Plan', route: '/exam-seat', icon: AppIcons.examSeat,
      accent: AppColors.orange, group: CapabilityGroup.personal, hint: 'View seat plan');
  static const myAttendance = AppCapability(
      label: 'My Attendance', route: '/my-attendance',
      icon: Icons.fact_check_outlined, accent: AppColors.green,
      group: CapabilityGroup.personal, hint: 'Your own record');
  static const results = AppCapability(
      label: 'Results', route: '/grades', icon: AppIcons.results,
      accent: AppColors.gold, group: CapabilityGroup.personal, hint: 'CGPA and grades');
  static const assignments = AppCapability(
      label: 'Assignments', route: '/assignments', icon: AppIcons.assignments,
      accent: AppColors.holoTeal, group: CapabilityGroup.personal, hint: 'Due and submitted');

  // -- academics -----------------------------------------------------------
  static const schedule = AppCapability(
      label: 'Class Schedule', route: '/schedule', icon: AppIcons.schedule,
      accent: AppColors.blue, group: CapabilityGroup.academics, hint: "Today's classes");
  static const myOfferings = AppCapability(
      label: 'My Course Offerings', route: '/schedule/my-offerings',
      icon: AppIcons.schedule, accent: AppColors.blue,
      group: CapabilityGroup.academics, hint: 'Courses you teach');
  static const attendance = AppCapability(
      label: 'Attendance', route: '/attendance', icon: Icons.how_to_reg_rounded,
      accent: AppColors.green, group: CapabilityGroup.academics, hint: 'Take the register');
  static const joinRequests = AppCapability(
      label: 'Join Requests', route: '/schedule/join-requests',
      icon: Icons.how_to_reg_rounded, accent: AppColors.green,
      group: CapabilityGroup.academics, hint: 'Students waiting');
  static const teachingLoad = AppCapability(
      label: 'Teaching Load', route: '/schedule/teaching-load',
      icon: Icons.assignment_ind_rounded, accent: AppColors.indigo,
      group: CapabilityGroup.academics);
  static const browseCourses = AppCapability(
      label: 'Browse Courses', route: '/schedule/browse-courses',
      icon: Icons.menu_book_rounded, accent: AppColors.blue,
      group: CapabilityGroup.academics);
  static const roomAvailability = AppCapability(
      label: 'Room Availability', route: '/room-availability',
      icon: AppIcons.schedule, accent: AppColors.holoTeal,
      group: CapabilityGroup.academics, hint: 'Find a free room');

  // -- campus --------------------------------------------------------------
  static const transport = AppCapability(
      label: 'Transport', route: '/transport', icon: AppIcons.transport,
      accent: AppColors.teal, group: CapabilityGroup.campus, hint: 'Next departure');
  static const lostFound = AppCapability(
      label: 'Lost & Found', route: '/lost-found', icon: AppIcons.lostFound,
      accent: AppColors.coral, group: CapabilityGroup.campus, hint: 'New found items');
  static const clubs = AppCapability(
      label: 'Clubs', route: '/clubs', icon: AppIcons.clubs,
      accent: AppColors.pink, group: CapabilityGroup.campus, hint: 'Upcoming events');
  static const mentorship = AppCapability(
      label: 'Mentorship', route: '/mentorship', icon: AppIcons.mentorship,
      accent: AppColors.blueLight, group: CapabilityGroup.campus, hint: 'Book a session');
  static const deptChat = AppCapability(
      label: 'Dept Chat', route: '/dept-chat', icon: AppIcons.deptChat,
      accent: AppColors.indigo, group: CapabilityGroup.campus, hint: 'Department channel');
  static const nearbySos = AppCapability(
      label: 'Nearby SOS Alerts', route: '/sos/nearby', icon: Icons.sos_rounded,
      accent: AppColors.red, group: CapabilityGroup.campus);
  static const conferenceRoom = AppCapability(
      label: 'Conference Room', route: '/conference-room',
      icon: AppIcons.conferenceRoom, accent: AppColors.holoTeal,
      group: CapabilityGroup.campus, hint: 'Book a room');

  // -- operations ----------------------------------------------------------
  /// The whole Uploads section, not one importer.
  ///
  /// It was called "Upload Routine/Transport" while it was exactly that. The
  /// route is unchanged on purpose: it is the path three delegated grants and
  /// several tests already point at, and the hub behind it now covers class
  /// routine, exam routine, transport, seat plans and notices — showing each
  /// person only the kinds their grant actually covers.
  static const uploadRoutine = AppCapability(
      label: 'Uploads', route: '/admin/upload',
      icon: AppIcons.uploadRoutine, accent: AppColors.holoBlue,
      group: CapabilityGroup.operations,
      hint: 'Routines, transport, seat plans, notices');
  static const courseOfferingsAdmin = AppCapability(
      label: 'Course Offerings', route: '/admin/course-offerings',
      icon: AppIcons.schedule, accent: AppColors.blue,
      group: CapabilityGroup.operations, hint: 'Approve and archive');
  static const hallAdmin = AppCapability(
      label: 'Manage Hall', route: '/admin/hall', icon: AppIcons.hall,
      accent: AppColors.amber, group: CapabilityGroup.operations, hint: 'Allocations');
  static const libraryAdmin = AppCapability(
      label: 'Manage Library', route: '/admin/library', icon: AppIcons.library,
      accent: AppColors.purple, group: CapabilityGroup.operations, hint: 'Catalogue and loans');
  static const deptChatAdmin = AppCapability(
      label: 'Moderate Dept Chats', route: '/admin/dept-chat',
      icon: AppIcons.moderateChat, accent: AppColors.indigo,
      group: CapabilityGroup.operations);
  static const faculties = AppCapability(
      label: 'Manage Faculties', route: '/admin/faculties', icon: AppIcons.faculties,
      accent: AppColors.holoviolet, group: CapabilityGroup.operations);
  static const departments = AppCapability(
      label: 'Manage Departments', route: '/admin/departments', icon: AppIcons.hall,
      accent: AppColors.holoTeal, group: CapabilityGroup.operations);
  static const notices = AppCapability(
      label: 'Notices & Rules', route: '/manage-notices', icon: AppIcons.notices,
      accent: AppColors.red, group: CapabilityGroup.operations, hint: 'Publish to campus');
  static const examSeatsAdmin = AppCapability(
      label: 'Manage Exam Seats', route: '/manage-exam-seats', icon: AppIcons.examSeat,
      accent: AppColors.orange, group: CapabilityGroup.operations);
  static const sosAdmin = AppCapability(
      label: 'Manage SOS Alerts', route: '/admin/sos', icon: Icons.sos_rounded,
      accent: AppColors.red, group: CapabilityGroup.operations, hint: 'Live alerts');

  // -- oversight -----------------------------------------------------------
  static const manageUsers = AppCapability(
      label: 'Manage Users', route: '/admin/users', icon: AppIcons.manageUsers,
      accent: AppColors.holoviolet, group: CapabilityGroup.oversight,
      hint: 'Roles, areas, approvals');
  static const manageClubs = AppCapability(
      label: 'Manage Clubs', route: '/admin/clubs', icon: AppIcons.manageClubs,
      accent: AppColors.holoviolet, group: CapabilityGroup.oversight);
  static const conferenceRoomsAdmin = AppCapability(
      label: 'Conference Rooms', route: '/admin/conference-rooms',
      icon: AppIcons.conferenceRoom, accent: AppColors.holoviolet,
      group: CapabilityGroup.oversight);
  static const feedbackTriage = AppCapability(
      label: 'Feedback & Contributions', route: '/admin/feedback',
      icon: Icons.feedback_outlined, accent: AppColors.holoviolet,
      group: CapabilityGroup.oversight, hint: 'What people are asking for');
  static const activityLog = AppCapability(
      label: 'Activity Log', route: '/admin/activity', icon: Icons.history_rounded,
      accent: AppColors.holoviolet, group: CapabilityGroup.oversight,
      hint: 'Who did what');

  /// The delegated entry to Manage Users. Same route, different label on
  /// purpose: a delegate opens it to distribute work they already hold, and
  /// calling it "Manage Users" would promise a tool they do not have.
  static const assignWorkAreas = AppCapability(
      label: 'Assign Work Areas', route: '/admin/users', icon: AppIcons.manageUsers,
      accent: AppColors.holoviolet, group: CapabilityGroup.oversight,
      hint: 'Hand out your own areas');
}

// ---------------------------------------------------------------------------
// Composition
// ---------------------------------------------------------------------------

/// Capabilities unlocked by an individual grant, in menu order.
///
/// Kept as a route list rather than an `AppCapability` list because
/// `delegatedRoutes` is pinned by `test/staff_menu_permissions_test.dart` and
/// its signature must not move. [delegatedCapabilities] is the richer view.
List<AppCapability> _delegated(Set<String> grants) {
  bool can(String resource, String action) => grants.contains('$resource:$action');
  return [
    // One screen, three grants that each unlock it — mirrors the router, which
    // admits any one of them.
    if (can('routine', 'upload') || can('transport', 'upload') || can('exam_seat', 'upload'))
      Caps.uploadRoutine,
    if (can('course_offerings', 'manage')) Caps.courseOfferingsAdmin,
    if (can('hall', 'manage')) Caps.hallAdmin,
    if (can('library', 'manage')) Caps.libraryAdmin,
    if (can('conference', 'manage')) Caps.conferenceRoom,
    if (can('sos', 'manage')) Caps.sosAdmin,
    if (can('notice', 'publish')) Caps.notices,
    if (can('exam_seat', 'upload')) Caps.examSeatsAdmin,
    // Four different jobs, one screen. Manage Users is where work is
    // distributed, signups are approved, CR requests are decided and roles are
    // set; the router admits the same four, and the screen shows only the tabs
    // the holder can use.
    if (can('permissions', 'delegate') || can('users', 'approve') ||
        can('cr', 'approve') || can('roles', 'assign'))
      Caps.assignWorkAreas,
    if (can('audit', 'read')) Caps.activityLog,
    if (can('feedback', 'triage')) Caps.feedbackTriage,
  ];
}

/// The delegated half, marked as delegated so the UI can say where it came from.
List<AppCapability> delegatedCapabilities(Set<String> grants) =>
    _delegated(grants).map((c) => c.asDelegated()).toList();

/// Routes unlocked by an individual grant. Signature pinned by tests.
@visibleForTesting
List<String> delegatedRoutes(Set<String> grants) =>
    _delegated(grants).map((c) => c.route).toList();

/// The whole menu for a `staff` account. Signature pinned by tests.
///
/// Staff is the one role whose menu is built ENTIRELY from grants: what an
/// employee gets for being an employee is transport, lost & found, personal
/// safety and their own account. Nothing here is an administrative tool, so a
/// staff member with no grants correctly has no job in the app — which is why
/// the UI says so rather than showing a short menu that looks complete.
@visibleForTesting
List<String> staffMenuRoutes(Set<String> grants) =>
    capabilitiesFor(role: 'staff', grants: grants).map((c) => c.route).toList();

/// Everything this person can do, in display order.
///
/// The single answer. `role` decides the baseline, `grants` adds delegated
/// areas on top, and `isCr` is the one per-section flag that is not a role.
List<AppCapability> capabilitiesFor({
  required String? role,
  required Set<String> grants,
  bool isCr = false,
}) {
  final extras = delegatedCapabilities(grants);

  List<AppCapability> withExtras(List<AppCapability> base) {
    if (extras.isEmpty) return base;
    // Deduped by route: a teacher granted `conference:manage` already has the
    // Conference Room entry, and listing it twice reads as a bug.
    final have = base.map((c) => c.route).toSet();
    final add = extras.where((c) => !have.contains(c.route)).toList();
    if (add.isEmpty) return base;
    // Feedback stays last, as it always has.
    final i = base.indexWhere((c) => c.route == Caps.feedback.route);
    if (i < 0) return [...base, ...add];
    return [...base.sublist(0, i), ...add, ...base.sublist(i)];
  }

  const common = [
    Caps.dashboard, Caps.schedule, Caps.transport, Caps.lostFound, Caps.clubs,
    Caps.results, Caps.assignments, Caps.mentorship, Caps.deptChat,
    Caps.nearbySos, Caps.notifications, Caps.settings,
  ];
  const studentOnly = [
    Caps.portal, Caps.library, Caps.hall, Caps.payment, Caps.examSeat,
  ];
  const adminTools = [
    Caps.uploadRoutine, Caps.courseOfferingsAdmin, Caps.hallAdmin,
    Caps.libraryAdmin, Caps.deptChatAdmin, Caps.faculties, Caps.departments,
    Caps.notices, Caps.examSeatsAdmin, Caps.sosAdmin,
  ];
  const superAdminTools = [
    Caps.manageUsers, Caps.manageClubs, Caps.conferenceRoomsAdmin,
    Caps.feedbackTriage, Caps.activityLog,
  ];

  switch (role) {
    case 'super_admin':
      return withExtras([
        ...common, ...adminTools, Caps.teachingLoad, ...superAdminTools,
        Caps.feedback,
      ]);

    case 'admin':
    case 'dept_admin':
      return withExtras([
        ...common, ...adminTools, Caps.teachingLoad, Caps.feedback,
      ]);

    case 'teacher':
      // Teachers author course notices but do not get the rest of the admin
      // toolset (routine upload, faculty/department registry).
      return withExtras([
        ...common, Caps.myOfferings, Caps.joinRequests, Caps.attendance,
        Caps.teachingLoad, Caps.notices, Caps.conferenceRoom,
        Caps.roomAvailability, Caps.feedback,
      ]);

    case 'staff':
      // Built entirely from grants — see staffMenuRoutes above.
      return [
        Caps.dashboard, Caps.transport, Caps.lostFound, Caps.nearbySos,
        Caps.notifications, Caps.settings,
        ...extras,
        Caps.feedback,
      ];

    case 'exam_controller':
      return withExtras([
        ...common, Caps.examSeatsAdmin, Caps.notices, Caps.feedback,
      ]);

    default: // student, and anyone whose profile has not resolved yet
      return withExtras([
        ...common, ...studentOnly, Caps.browseCourses, Caps.myAttendance,
        if (isCr) Caps.roomAvailability,
        Caps.feedback,
      ]);
  }
}

/// Capabilities grouped for a sidebar or a console, in group order, with
/// empty groups dropped.
Map<CapabilityGroup, List<AppCapability>> groupCapabilities(
    List<AppCapability> caps) {
  final out = <CapabilityGroup, List<AppCapability>>{};
  for (final c in caps) {
    (out[c.group] ??= <AppCapability>[]).add(c);
  }
  final keys = out.keys.toList()..sort((a, b) => a.order.compareTo(b.order));
  return {for (final k in keys) k: out[k]!};
}
