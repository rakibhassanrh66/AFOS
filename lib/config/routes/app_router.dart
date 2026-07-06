import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/admin/presentation/manage_clubs_screen.dart';
import '../../features/admin/presentation/manage_conference_rooms_screen.dart';
import '../../features/admin/presentation/manage_users_screen.dart';
import '../../features/assignments/presentation/assignments_screen.dart';
import '../../features/auth/presentation/complete_profile_screen.dart';
import '../../features/auth/presentation/pending_approval_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
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
import '../../features/lost_found/presentation/lost_found_screen.dart';
import '../../features/mentorship/presentation/mentorship_screen.dart';
import '../../features/notifications/presentation/notification_center_screen.dart';
import '../../features/payment/presentation/payment_screen.dart';
import '../../features/registry/presentation/manage_notices_screen.dart';
import '../../features/registry/presentation/registry_list_screen.dart';
import '../../features/schedule/presentation/schedule_screen.dart';
import '../../features/schedule/presentation/admin_upload_routine_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/transport/presentation/transport_screen.dart';
import '../../features/vr_id/presentation/vr_id_screen.dart';
import '../../shared/animations/page_transitions.dart';
import '../../core/auth/role_session.dart';

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
      if (session == null) {
        RoleSession.clear();
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
        if (!_adminRoles.contains(role)) return '/home';
      }
      // User management (approve/reject signups, delete accounts entirely)
      // is the single most destructive tool in the app — super_admin only,
      // not the broader admin/dept_admin set the rest of /admin allows.
      if (loc == '/admin/users' || loc == '/admin/clubs' || loc == '/admin/conference-rooms') {
        final role = await RoleSession.ensureLoaded();
        if (role != 'super_admin') return '/home';
      }
      // Notices/rules can be authored by teachers too (course notices),
      // not just admin roles — kept outside the /admin prefix so it isn't
      // caught by the admin-only guard above.
      if (loc == '/manage-notices') {
        final role = await RoleSession.ensureLoaded();
        if (!_adminRoles.contains(role) && role != 'teacher') return '/home';
      }
      // Exam seat assignment is done by exam_controller too, which isn't
      // in _adminRoles and isn't under /admin — same reasoning as notices.
      if (loc == '/manage-exam-seats') {
        final role = await RoleSession.ensureLoaded();
        if (!_adminRoles.contains(role) && role != 'exam_controller') return '/home';
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
      return null;
    },

    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/auth/login',
        pageBuilder: (c, s) => fadeScalePage(const LoginScreen(), s)),
      GoRoute(path: '/auth/register',
        pageBuilder: (c, s) => slideUpPage(const RegisterScreen(), s)),
      GoRoute(path: '/auth/forgot-password',
        pageBuilder: (c, s) => slideUpPage(const ForgotPasswordScreen(), s)),
      GoRoute(path: '/complete-profile',
        pageBuilder: (c, s) => fadeScalePage(const CompleteProfileScreen(), s)),
      GoRoute(path: '/pending-approval',
        pageBuilder: (c, s) => fadeScalePage(const PendingApprovalScreen(), s)),
      ShellRoute(
        navigatorKey: _shell,
        builder: (c, s, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home',          pageBuilder: (c,s) => slideRightPage(const DashboardScreen(), s)),
          GoRoute(path: '/schedule',      pageBuilder: (c,s) => slideRightPage(const ScheduleScreen(), s)),
          GoRoute(path: '/hall',          pageBuilder: (c,s) => slideRightPage(const HallScreen(), s)),
          GoRoute(path: '/transport',     pageBuilder: (c,s) => slideRightPage(const TransportScreen(), s)),
          GoRoute(path: '/payment',       pageBuilder: (c,s) => slideRightPage(const PaymentScreen(), s)),
          GoRoute(path: '/library',       pageBuilder: (c,s) => slideRightPage(const LibraryScreen(), s)),
          GoRoute(path: '/lost-found',    pageBuilder: (c,s) => slideRightPage(const LostFoundScreen(), s)),
          GoRoute(path: '/clubs',         pageBuilder: (c,s) => slideRightPage(const ClubsScreen(), s)),
          GoRoute(path: '/mentorship',    pageBuilder: (c,s) => slideRightPage(const MentorshipScreen(), s)),
          GoRoute(path: '/exam-seat',     pageBuilder: (c,s) => slideRightPage(const ExamSeatScreen(), s)),
          GoRoute(path: '/grades',        pageBuilder: (c,s) => slideRightPage(const GradesScreen(), s)),
          GoRoute(path: '/assignments',   pageBuilder: (c,s) => slideRightPage(const AssignmentsScreen(), s)),
          GoRoute(path: '/dept-chat',     pageBuilder: (c,s) => slideRightPage(const DeptChatScreen(), s)),
          GoRoute(path: '/vr-id',         pageBuilder: (c,s) => slideRightPage(const VrIdScreen(), s)),
          GoRoute(path: '/notifications', pageBuilder: (c,s) => slideRightPage(const NotificationCenterScreen(), s)),
          GoRoute(path: '/settings',      pageBuilder: (c,s) => slideRightPage(const SettingsScreen(), s)),
          GoRoute(path: '/admin/upload',  pageBuilder: (c,s) => slideRightPage(const AdminUploadRoutineScreen(), s)),
          GoRoute(path: '/admin/hall',    pageBuilder: (c,s) => slideRightPage(const ManageHallScreen(), s)),
          GoRoute(path: '/admin/users',   pageBuilder: (c,s) => slideRightPage(const ManageUsersScreen(), s)),
          GoRoute(path: '/admin/clubs',   pageBuilder: (c,s) => slideRightPage(const ManageClubsScreen(), s)),
          GoRoute(path: '/admin/conference-rooms', pageBuilder: (c,s) => slideRightPage(const ManageConferenceRoomsScreen(), s)),
          GoRoute(path: '/conference-room', pageBuilder: (c,s) => slideRightPage(const ConferenceRoomScreen(), s)),
          GoRoute(path: '/admin/dept-chat', pageBuilder: (c,s) => slideRightPage(const ManageDeptChatScreen(), s)),
          GoRoute(path: '/manage-notices', pageBuilder: (c,s) => slideRightPage(const ManageNoticesScreen(), s)),
          GoRoute(path: '/manage-exam-seats', pageBuilder: (c,s) => slideRightPage(const ManageExamSeatsScreen(), s)),
          // Registry Module Routes
          GoRoute(path: '/admin/faculties', builder: (c, s) => const RegistryListScreen(tableName: 'faculties', title: 'Faculties')),
          GoRoute(path: '/admin/departments', builder: (c, s) => const RegistryListScreen(tableName: 'departments', title: 'Departments', displayFields: ['name', 'code'])),
        ],
      ),
    ],
    errorBuilder: (c, s) => Scaffold(
      backgroundColor: const Color(0xFF060D1F),
      body: Center(child: Column(mainAxisSize:MainAxisSize.min, children:[
        const Icon(Icons.error_outline, color: Color(0xFFFF4D6A), size: 48),
        const SizedBox(height:16),
        Text('Page not found', style: const TextStyle(color:Colors.white70)),
        const SizedBox(height:16),
        ElevatedButton(onPressed:()=>GoRouter.of(c).go('/home'), child:const Text('Go Home')),
      ])),
    ),
  );
}
