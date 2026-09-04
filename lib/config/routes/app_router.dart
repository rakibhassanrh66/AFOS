import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';

import '../../features/admin/presentation/manage_clubs_screen.dart';
import '../../features/admin/presentation/manage_conference_rooms_screen.dart';
import '../../features/admin/presentation/manage_course_offerings_admin_screen.dart';
import '../../features/admin/presentation/activity_log_screen.dart';
import '../../features/admin/presentation/manage_feedback_screen.dart';
import '../../features/admin/presentation/manage_users_screen.dart';
import '../../features/admin/presentation/profile_inspection_screen.dart';
import '../../features/admin/presentation/user_directory_screen.dart';
import '../../features/assignments/presentation/assignments_screen.dart';
import '../../features/attendance/presentation/attendance_screen.dart';
import '../../features/attendance/presentation/my_attendance_screen.dart';
import '../../features/auth/presentation/complete_profile_screen.dart';
import '../../features/auth/presentation/pending_approval_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/presentation/reset_with_code_screen.dart';
import '../../features/auth/presentation/verify_email_screen.dart';
import '../../features/auth/presentation/unlock_screen.dart';
import '../../features/clubs/presentation/clubs_screen.dart';
import '../../features/conference_room/presentation/conference_room_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/dept_chat/presentation/dept_chat_screen.dart';
import '../../features/dept_chat/presentation/manage_dept_chat_screen.dart';
import '../../features/exam_seat/presentation/exam_seat_screen.dart';
import '../../features/exam_seat/presentation/manage_exam_seats_screen.dart';
import '../../features/grades/presentation/grades_screen.dart';
import '../../features/hall/presentation/hall_screen.dart';
import '../../features/hall/presentation/manage_hall_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/library/presentation/manage_library_screen.dart';
import '../../features/lost_found/presentation/lost_found_screen.dart';
import '../../features/advising/presentation/my_students_screen.dart';
import '../../features/mentorship/presentation/mentorship_screen.dart';
import '../../features/notifications/presentation/notification_center_screen.dart';
import '../../features/portal/presentation/diu_portal_hub_screen.dart';
import '../../features/portal/presentation/diu_portal_screen.dart';
import '../../features/payment/presentation/payment_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/search/presentation/global_search_screen.dart';
import '../../features/registry/presentation/manage_notices_screen.dart';
import '../../features/registry/presentation/notices_screen.dart';
import '../../features/registry/presentation/registry_list_screen.dart';
import '../../features/schedule/presentation/schedule_screen.dart';
import '../../features/schedule/presentation/admin_upload_routine_screen.dart';
import '../../features/uploads/presentation/exam_routine_upload_screen.dart';
import '../../features/uploads/presentation/uploads_hub_screen.dart';
import '../../features/schedule/presentation/browse_courses_screen.dart';
import '../../features/schedule/presentation/manage_course_offerings_screen.dart';
import '../../features/schedule/presentation/join_requests_screen.dart';
import '../../features/schedule/presentation/module_leader_screen.dart';
import '../../features/schedule/presentation/room_availability_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/releases_screen.dart';
import '../../features/feedback/presentation/feedback_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/sos/presentation/manage_sos_screen.dart';
import '../../features/sos/presentation/nearby_sos_screen.dart';
import '../../features/sos/presentation/sos_alert_detail_screen.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/transport/presentation/transport_screen.dart';
import '../../features/vr_id/presentation/vr_id_screen.dart';
import '../../shared/animations/page_transitions.dart';
import '../app_config.dart';
import '../../core/auth/permission_session.dart';
import '../../core/auth/role_session.dart';
import '../../core/navigation/back_press_tracker.dart';
import '../../core/utils/last_route.dart';

const _adminRoles = ['admin', 'super_admin', 'dept_admin'];

class AppRouter {
  AppRouter._();
  static final _root  = GlobalKey<NavigatorState>();
  static final _shell = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _root,
    initialLocation: '/splash',
    redirect: (context, state) async {
      final session = Supabase.instance.client.auth.currentSession;
      final loc = state.matchedLocation;
      if (loc == '/splash') return null;
      // Reachable regardless of session/profile/verification state -- a
      // Supabase password-recovery link establishes a real session (so the
      // `session == null` branch below wouldn't apply), but this route
      // sits outside the /auth prefix specifically so the "already logged
      // in, /auth/* bounces to /home" rule two lines down doesn't also
      // catch it and skip the password-reset step entirely.
      if (loc == '/reset-password') return null;
      // Biometric lock: reachable even with a live session (it gates access to
      // that already-valid session), so it must be exempt from the
      // "logged-in, /auth/* bounces to /home" rule below — same reasoning as
      // /reset-password above.
      if (loc == '/auth/unlock') return null;
      // The two routes the EMAILED buttons land on. Same reasoning as the two
      // exemptions above, and they were missed for the same reason both of
      // those needed writing down: the rule below is about a signed-in user
      // wandering back to the login screen, and these are not that.
      //
      // A live session is not evidence the link is unwanted. Someone signed in
      // on this browser can still be holding a reset link for the account they
      // have forgotten the password to, and register-verify's token is proof
      // in its own right — the account it confirms need not be the one the
      // session belongs to. Bouncing to /home threw the token away in
      // silence: no error, no screen, nothing to retry, and the mail was
      // single-use.
      //
      // Gated on the token actually being present so the original rule still
      // holds for plain navigation: a signed-in user who opens /auth/verify
      // with nothing in the query string still goes home. `state.uri` rather
      // than `loc`, because matchedLocation drops the query — the same
      // distinction the route builders below rely on.
      if ((loc == '/auth/verify' || loc == '/auth/reset') &&
          (state.uri.queryParameters['token'] ?? '').isNotEmpty) {
        return null;
      }
      if (session == null) {
        RoleSession.clear();
        PermissionSession.clear();
        return loc.startsWith('/auth') ? null : '/auth/login';
      }
      if (loc.startsWith('/auth')) return '/home';
      if (loc == '/complete-profile') return null;
      // Mandatory fields were skippable on an older signup path (or an
      // admin-created account) — force completion before anything else,
      // rather than letting the app run with a half-filled profile.
      final completed = await RoleSession.ensureProfileCompletedLoaded();
      if (!completed) return '/complete-profile';
      // New signups need super_admin approval before "full active mode" —
      // accounts that existed before this gate was introduced were
      // grandfathered to verified=true, so this only ever blocks brand new
      // accounts, never anyone already using the app.
      if (loc == '/pending-approval') return null;
      final verified = await RoleSession.ensureVerifiedLoaded();
      if (!verified) return '/pending-approval';
      if (loc.startsWith('/admin')) {
        final role = await RoleSession.ensureLoaded();
        // Library checkout is a real front-desk task, not admin-tier
        // oversight — staff need it same as they need Conference Room and
        // SOS oversight (staff should be able to run and help too).
        var allowed = _adminRoles.contains(role)
            || (role == 'staff' && (loc == '/admin/library' || loc == '/admin/sos'));
        // Distributed admin roles ("Manage Users" > a user's Permissions):
        // a super_admin can delegate ONE specific admin area to a non-admin
        // user without making them a full admin. RLS on the underlying
        // tables already honours the same grant via caller_can(resource,
        // action) — this is the router-side half, so a delegated user
        // actually REACHES the screen instead of being bounced here first.
        // /admin/upload is the Uploads hub and everything under it — class
        // routine, exam routine, transport, and the ledger of what was
        // loaded. Any one of the three upload grants opens the section; the
        // hub itself then shows only the kinds that grant actually covers, so
        // a transport-only delegate does not see a routine importer they
        // cannot use.
        if (!allowed) {
          allowed = switch (loc) {
            // exam_controller is admitted BY ROLE, not only by grant.
            // uploadKindsFor() already hands that role the exam routine, seat
            // plan and notice kinds — but this guard only ever checked the
            // three grants, so an exam_controller was bounced from the hub
            // that was built to contain their work. They reached seat plans
            // solely through a separate "Manage Exam Seats" tile, which is why
            // the same job appeared twice in the app. The tile is gone now, so
            // this is the way in and it has to open.
            _ when loc == '/admin/upload' || loc.startsWith('/admin/upload/') =>
              role == 'exam_controller'
                || await PermissionSession.ensureHas('transport', 'upload')
                || await PermissionSession.ensureHas('routine', 'upload')
                || await PermissionSession.ensureHas('exam_seat', 'upload'),
            '/admin/hall' => await PermissionSession.ensureHas('hall', 'manage'),
            '/admin/library' => await PermissionSession.ensureHas('library', 'manage'),
            '/admin/sos' => await PermissionSession.ensureHas('sos', 'manage'),
            '/admin/conference-rooms' => await PermissionSession.ensureHas('conference', 'manage'),
            '/admin/course-offerings' => await PermissionSession.ensureHas('course_offerings', 'manage'),
            _ => false,
          };
        }
        if (!allowed) return '/home';
      }
      // User management (approve/reject signups, delete accounts entirely)
      // is the single most destructive tool in the app — super_admin only,
      // not the broader admin/dept_admin set the rest of /admin allows, and
      // NOT delegable via the permissions catalog (there is no "users"
      // resource in it, deliberately). Clubs/Feedback moderation are the
      // same tier. Conference Rooms moved to the /admin block above: RLS
      // there already allows a caller_can('conference','manage') grant, not
      // just super_admin, so the router now matches that instead of being
      // stricter than the data layer.
      //
      // Feedback moved OUT of this pair: `feedback:triage` now exists and RLS
      // honours it, so keeping the router at super_admin-only would be
      // stricter than the data layer — the mistake Conference Rooms made. It
      // is handled below. Clubs has no equivalent grant and stays here.
      if (loc == '/admin/clubs') {
        final role = await RoleSession.ensureLoaded();
        if (role != 'super_admin') return '/home';
      }
      // Manage Users is super_admin's tool, with ONE exception: a delegate
      // (`permissions:delegate`) needs this screen to distribute work, because
      // it is where the permission sheet lives.
      //
      // Letting them THROUGH the door is not letting them do everything behind
      // it. The screen itself hides role changes, approvals and deletion for a
      // non-super_admin, and the database refuses those independently — a
      // delegate can only grant areas they already hold, and never to
      // themselves. The guard here matches the data layer rather than being
      // stricter than it, which is the same correction Conference Rooms got.
      //
      // FOUR grants now open it, not one. Manage Users is where work is
      // distributed (`permissions:delegate`), signups are approved
      // (`users:approve`), CR requests are decided (`cr:approve`) and roles are
      // set (`roles:assign`). Each is a separate job that happens to live on
      // the same screen, and the screen shows only the tabs and controls the
      // holder can use — so admitting any one of them is correct, and refusing
      // three of them at the door would hide a tool the database allows.
      // Broadened to /admin/users/:role (Phase B) -- a per-role directory page
      // is reached from this same screen and needs the identical grant set,
      // not a narrower one.
      if (loc == '/admin/users' || loc.startsWith('/admin/users/') || loc == '/admin/inspection') {
        final role = await RoleSession.ensureLoaded();
        if (role != 'super_admin') {
          final grants = await PermissionSession.ensureLoaded();
          const opensManageUsers = [
            'permissions:delegate', 'users:approve', 'cr:approve', 'roles:assign',
          ];
          if (!opensManageUsers.any(grants.contains)) return '/home';
        }
      }
      // The oversight screen. Deliberately NOT open to admin/dept_admin by
      // role: reading who did what to whom is a specific authority, granted on
      // purpose, not a side effect of being an admin.
      if (loc == '/admin/activity') {
        final role = await RoleSession.ensureLoaded();
        if (role != 'super_admin' &&
            !await PermissionSession.ensureHas('audit', 'read')) {
          return '/home';
        }
      }
      // Feedback triage — the IT-staff loop.
      if (loc == '/admin/feedback') {
        final role = await RoleSession.ensureLoaded();
        if (role != 'super_admin' &&
            !await PermissionSession.ensureHas('feedback', 'triage')) {
          return '/home';
        }
      }
      // Notices/rules can be authored by teachers too (course notices),
      // not just admin roles — kept outside the /admin prefix so it isn't
      // caught by the admin-only guard above.
      if (loc == '/manage-notices') {
        final role = await RoleSession.ensureLoaded();
        if (!_adminRoles.contains(role) && role != 'teacher'
            && !(await PermissionSession.ensureHas('notice', 'publish'))) {
          return '/home';
        }
      }
      // Exam seat assignment is done by exam_controller too, which isn't
      // in _adminRoles and isn't under /admin — same reasoning as notices.
      if (loc == '/manage-exam-seats') {
        final role = await RoleSession.ensureLoaded();
        if (!_adminRoles.contains(role) && role != 'exam_controller'
            && !(await PermissionSession.ensureHas('exam_seat', 'upload'))) {
          return '/home';
        }
      }
      // Hall allocation, exam seating, and payment are personal student
      // records — a teacher has none of their own, so hide these routes
      // for them at the navigation layer too (defense in depth beyond the
      // menu simply not showing the entries; RLS is still the real gate
      // on the underlying data either way).
      const teacherHiddenRoutes = ['/hall', '/exam-seat', '/payment'];
      if (teacherHiddenRoutes.any(loc.startsWith)) {
        final role = await RoleSession.ensureLoaded();
        if (role == 'teacher') return '/home';
      }
      // Fire-and-forget: remembers where the user actually is so a force-
      // close (not a real logout) resumes here instead of always dropping
      // back to the dashboard — see splash_screen.dart's cold-start read.
      //
      // ONLY IF THE ROUTE ACTUALLY EXISTS. This redirect also runs for
      // locations that matched NOTHING — go_router logs the error and still
      // calls the top-level redirect — so an unmatched path used to be saved
      // as the resume target like any other.
      //
      // That bricks the app on launch, permanently. Open a stale shared link
      // like /#/exam-seats (the route is /manage-exam-seats), see "Page not
      // found", tap Go Home — and /exam-seats is now in Hive. Every cold start
      // from then on reads it, routes there, and lands back on the 404. There
      // is no way out from inside the app; only clearing storage or
      // reinstalling fixes it. A stale link somebody pasted in a group chat
      // should not be able to do that.
      if (state.topRoute != null) saveLastRoute(loc);
      return null;
    },

    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/auth/login',
        pageBuilder: (c, s) => fadeScalePage(const LoginScreen(), s)),
      GoRoute(path: '/auth/unlock',
        pageBuilder: (c, s) => fadeScalePage(const UnlockScreen(), s)),
      GoRoute(path: '/auth/register',
        pageBuilder: (c, s) => slideUpPage(const RegisterScreen(), s)),
      GoRoute(path: '/auth/forgot-password',
        pageBuilder: (c, s) => slideUpPage(const ForgotPasswordScreen(), s)),
      // Mailbox proof. Reached from the signup wizard (email in `extra`) or
      // from the emailed button (`?token=`). Both redeem the same server-side
      // row; see verify_email_screen.dart.
      GoRoute(path: '/auth/verify',
        pageBuilder: (c, s) {
          final extra = s.extra is Map ? Map<String, dynamic>.from(s.extra as Map) : null;
          return slideUpPage(VerifyEmailScreen(
            email: extra?['email'] as String?,
            token: s.uri.queryParameters['token'],
            resendAfterSeconds: (extra?['resendAfterSeconds'] as num?)?.toInt() ?? 60,
            lane: extra?['lane'] as String? ?? 'inline',
            manualFallback: extra?['manualFallback'] as bool? ?? true,
            mailFailed: extra?['mailFailed'] as bool? ?? false,
            mailReason: extra?['mailReason'] as String?,
            supportEmail: extra?['supportEmail'] as String?,
            supportTelegram: extra?['supportTelegram'] as String?,
            expiresInSeconds: (extra?['expiresInSeconds'] as num?)?.toInt() ?? 600,
          ), s);
        }),
      // Code-first password reset. Distinct from /reset-password below, which
      // is the legacy Supabase recovery-session screen kept for links already
      // in people's inboxes.
      GoRoute(path: '/auth/reset',
        pageBuilder: (c, s) {
          final extra = s.extra is Map ? Map<String, dynamic>.from(s.extra as Map) : null;
          return slideUpPage(ResetWithCodeScreen(
            email: extra?['email'] as String?,
            token: s.uri.queryParameters['token'],
          ), s);
        }),
      GoRoute(path: '/reset-password',
        pageBuilder: (c, s) => slideUpPage(const ResetPasswordScreen(), s)),
      GoRoute(path: '/complete-profile',
        pageBuilder: (c, s) => fadeScalePage(const CompleteProfileScreen(), s)),
      GoRoute(path: '/pending-approval',
        pageBuilder: (c, s) => fadeScalePage(const PendingApprovalScreen(), s)),
      ShellRoute(
        navigatorKey: _shell,
        observers: [BackPressTracker.instance],
        builder: (c, s, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home',          pageBuilder: (c,s) => slideRightPage(const DashboardScreen(), s)),
          GoRoute(path: '/profile',       pageBuilder: (c,s) => slideRightPage(const ProfileScreen(), s)),
          // `?focus=1` opens the field already focused, with the keyboard up.
          // Set by a DOUBLE tap on the Search tab; a single tap opens the
          // screen the way it always did.
          GoRoute(path: '/search',        pageBuilder: (c,s) => slideRightPage(
              GlobalSearchScreen(autofocus: s.uri.queryParameters['focus'] == '1'), s)),
          GoRoute(path: '/schedule',      pageBuilder: (c,s) => slideRightPage(const ScheduleScreen(), s)),
          GoRoute(path: '/hall',          pageBuilder: (c,s) => slideRightPage(const HallScreen(), s)),
          GoRoute(path: '/transport',     pageBuilder: (c,s) => slideRightPage(const TransportScreen(), s)),
          GoRoute(path: '/payment',       pageBuilder: (c,s) => slideRightPage(const PaymentScreen(), s)),
          GoRoute(path: '/library',       pageBuilder: (c,s) => slideRightPage(const LibraryScreen(), s)),
          GoRoute(path: '/lost-found',    pageBuilder: (c,s) => slideRightPage(const LostFoundScreen(), s)),
          GoRoute(path: '/clubs',         pageBuilder: (c,s) => slideRightPage(const ClubsScreen(), s)),
          GoRoute(path: '/mentorship',    pageBuilder: (c,s) => slideRightPage(const MentorshipScreen(), s)),
          GoRoute(path: '/my-students',   pageBuilder: (c,s) => slideRightPage(const MyStudentsScreen(), s)),
          GoRoute(path: '/exam-seat',     pageBuilder: (c,s) => slideRightPage(const ExamSeatScreen(), s)),
          GoRoute(path: '/grades',        pageBuilder: (c,s) => slideRightPage(const GradesScreen(), s)),
          GoRoute(path: '/assignments',   pageBuilder: (c,s) => slideRightPage(const AssignmentsScreen(), s)),
          GoRoute(path: '/attendance',    pageBuilder: (c,s) => slideRightPage(const AttendanceScreen(), s)),
          GoRoute(path: '/my-attendance', pageBuilder: (c,s) => slideRightPage(const MyAttendanceScreen(), s)),
          GoRoute(path: '/dept-chat',     pageBuilder: (c,s) => slideRightPage(const DeptChatScreen(), s)),
          GoRoute(path: '/vr-id',         pageBuilder: (c,s) => slideRightPage(const VrIdScreen(), s)),
          GoRoute(path: '/notifications', pageBuilder: (c,s) => slideRightPage(const NotificationCenterScreen(), s)),
          GoRoute(path: '/settings',      pageBuilder: (c,s) => slideRightPage(const SettingsScreen(), s)),
          GoRoute(path: '/releases',      pageBuilder: (c,s) => slideRightPage(const ReleasesScreen(), s)),
          GoRoute(path: '/feedback',      pageBuilder: (c,s) => slideRightPage(const FeedbackScreen(), s)),
          // The hub keeps the historical path so every delegated grant, menu
          // entry and deep link that already pointed at "the upload screen"
          // still lands somewhere correct. The file-based importer it used to
          // be now sits one level down.
          GoRoute(path: '/admin/upload',  pageBuilder: (c,s) => slideRightPage(const UploadsHubScreen(), s)),
          GoRoute(path: '/admin/upload/files', pageBuilder: (c,s) => slideRightPage(const AdminUploadRoutineScreen(), s)),
          GoRoute(path: '/admin/upload/exam-routine', pageBuilder: (c,s) => slideRightPage(const ExamRoutineUploadScreen(), s)),
          GoRoute(path: '/room-availability', pageBuilder: (c,s) => slideRightPage(const RoomAvailabilityScreen(), s)),
          GoRoute(path: '/schedule/my-offerings', pageBuilder: (c,s) => slideRightPage(const ManageCourseOfferingsScreen(), s)),
          GoRoute(path: '/schedule/teaching-load', pageBuilder: (c,s) => slideRightPage(const ModuleLeaderScreen(), s)),
          GoRoute(path: '/schedule/join-requests', pageBuilder: (c,s) => slideRightPage(const JoinRequestsScreen(), s)),
          GoRoute(path: '/schedule/browse-courses', pageBuilder: (c,s) => slideRightPage(const BrowseCoursesScreen(), s)),
          GoRoute(path: '/admin/course-offerings', pageBuilder: (c,s) => slideRightPage(const ManageCourseOfferingsAdminScreen(), s)),
          GoRoute(path: '/admin/hall',    pageBuilder: (c,s) => slideRightPage(const ManageHallScreen(), s)),
          GoRoute(path: '/admin/library', pageBuilder: (c,s) => slideRightPage(const ManageLibraryScreen(), s)),
          GoRoute(path: '/admin/users',   pageBuilder: (c,s) => slideRightPage(const ManageUsersScreen(), s)),
          // One role's own page (Phase B) -- 'all' (the "Total Users" tile)
          // and 'management' are the two synthetic values UserDirectoryScreen
          // has always understood alongside every real profiles.role.
          GoRoute(path: '/admin/users/:role', pageBuilder: (c,s) =>
              slideRightPage(UserDirectoryScreen(role: s.pathParameters['role']!), s)),
          // A DIFFERENT screen, not a third synthetic UserDirectoryScreen
          // role -- it lists whoever fails profile_is_complete(), not people
          // grouped by profiles.role, and needs columns that RPC's frozen
          // 17-column shape does not carry. Shares the same permission gate
          // (below) as everything else this screen's tile sits beside.
          GoRoute(path: '/admin/inspection', pageBuilder: (c,s) =>
              slideRightPage(const ProfileInspectionScreen(), s)),
          GoRoute(path: '/admin/feedback', pageBuilder: (c,s) => slideRightPage(const ManageFeedbackScreen(), s)),
          GoRoute(path: '/admin/activity', pageBuilder: (c,s) => slideRightPage(const ActivityLogScreen(), s)),
          GoRoute(path: '/admin/clubs',   pageBuilder: (c,s) => slideRightPage(const ManageClubsScreen(), s)),
          GoRoute(path: '/admin/conference-rooms', pageBuilder: (c,s) => slideRightPage(const ManageConferenceRoomsScreen(), s)),
          GoRoute(path: '/conference-room', pageBuilder: (c,s) => slideRightPage(const ConferenceRoomScreen(), s)),
          GoRoute(path: '/admin/dept-chat', pageBuilder: (c,s) => slideRightPage(const ManageDeptChatScreen(), s)),
          GoRoute(path: '/admin/sos', pageBuilder: (c,s) => slideRightPage(const ManageSosScreen(), s)),
          GoRoute(path: '/sos/nearby', pageBuilder: (c,s) => slideRightPage(const NearbySosScreen(), s)),
          GoRoute(path: '/sos/:id', pageBuilder: (c,s) => slideRightPage(
              SosAlertDetailScreen(alertId: s.pathParameters['id']!), s)),
          GoRoute(path: '/manage-notices', pageBuilder: (c,s) => slideRightPage(const ManageNoticesScreen(), s)),
          // The reading half. Authoring has existed since the notices
          // table did; there was never a screen that listed them.
          GoRoute(path: '/notices', pageBuilder: (c,s) => slideRightPage(const NoticesScreen(), s)),
          GoRoute(path: '/manage-exam-seats', pageBuilder: (c,s) => slideRightPage(const ManageExamSeatsScreen(), s)),
          // Single entry point for all the DIU portal links — one slide-menu
          // item opens this hub, rather than nine entries cluttering the menu.
          GoRoute(path: '/portal', pageBuilder: (c,s) => slideRightPage(
              const DiuPortalHubScreen(), s)),
          // DIU student-portal pages, shown in an in-app browser inside the
          // shell (so the bottom nav, header and back behaviour are the app's,
          // not a browser's). They are NOT scraped: the portal is behind a
          // Cloudflare bot challenge that 403s every non-browser client, so a
          // server-side scraper cannot read them at all — see DiuPortalScreen.
          GoRoute(path: '/portal/dashboard', pageBuilder: (c,s) => slideRightPage(
              const DiuPortalScreen(title: 'Student Portal', url: AppConfig.diuPortalDashboard), s)),
          GoRoute(path: '/portal/ledger', pageBuilder: (c,s) => slideRightPage(
              const DiuPortalScreen(title: 'Payment Ledger', url: AppConfig.diuPortalLedger), s)),
          GoRoute(path: '/portal/scholarship', pageBuilder: (c,s) => slideRightPage(
              const DiuPortalScreen(title: 'Scholarship Circular', url: AppConfig.diuPortalScholarship), s)),
          GoRoute(path: '/portal/waiver', pageBuilder: (c,s) => slideRightPage(
              const DiuPortalScreen(title: 'Waiver', url: AppConfig.diuPortalWaiver), s)),
          GoRoute(path: '/portal/career', pageBuilder: (c,s) => slideRightPage(
              const DiuPortalScreen(title: 'Career Development', url: AppConfig.diuPortalCareer), s)),
          GoRoute(path: '/portal/notices', pageBuilder: (c,s) => slideRightPage(
              const DiuPortalScreen(title: 'DIU Notice Board', url: AppConfig.diuPortalNoticeBoard), s)),
          GoRoute(path: '/portal/facilities', pageBuilder: (c,s) => slideRightPage(
              const DiuPortalScreen(title: 'Student Benefits', url: AppConfig.diuPortalFacilities), s)),
          GoRoute(path: '/portal/transport-card', pageBuilder: (c,s) => slideRightPage(
              const DiuPortalScreen(title: 'Transport Card', url: AppConfig.diuTransportCardApply), s)),
          GoRoute(path: '/portal/hall', pageBuilder: (c,s) => slideRightPage(
              const DiuPortalScreen(title: 'Hall Management', url: AppConfig.diuHallLogin), s)),
          // Registry Module Routes — same slide transition as their shell siblings.
          GoRoute(path: '/admin/faculties',
              pageBuilder: (c, s) => slideRightPage(const RegistryListScreen(tableName: 'faculties', title: 'Faculties'), s)),
          GoRoute(path: '/admin/departments',
              pageBuilder: (c, s) => slideRightPage(const RegistryListScreen(tableName: 'departments', title: 'Departments', displayFields: ['name', 'code']), s)),
        ],
      ),
    ],
    // The 404. It was the last screen in the app painting its own raw hex —
    // a hardcoded dark slab with white text, so in LIGHT mode a mistyped link
    // handed the user a black rectangle that looked nothing like the app. It
    // now takes the Scaffold's themed background and themed text, so it has no
    // opinion about the canvas colour at all.
    errorBuilder: (c, s) => Scaffold(
      body: Center(child: Column(mainAxisSize:MainAxisSize.min, children:[
        const Icon(Icons.error_outline, color: AppColors.red, size: 48),
        const SizedBox(height:16),
        Text('Page not found', style: TextStyle(color: AppColors.textSecondaryOf(c))),
        const SizedBox(height:16),
        // Padding, because the app theme sets a button `minimumSize` of
        // `Size(double.infinity, 52)` — so an unconstrained ElevatedButton here
        // ran the full width of the screen and touched both bezels. Seen on
        // device, not in a test: nothing overflows, it just looks broken.
        //
        // The padding alone was a PHONE-shaped fix. On web at 1440px it still
        // left a 1376px-wide button spanning the whole viewport — seen in the
        // browser, again not in a test, because nothing overflows there either.
        // The cap is what makes it a button at any width; the padding is what
        // keeps it off the bezels below 384px.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: ElevatedButton(
                onPressed:()=>GoRouter.of(c).go('/home'), child:const Text('Go Home')),
          ),
        ),
      ])),
    ),
  );
}
