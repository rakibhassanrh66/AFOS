import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/register_screen.dart';
import '../../features/clubs/presentation/clubs_screen.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/dept_chat/presentation/dept_chat_screen.dart';
import '../../features/exam_seat/presentation/exam_seat_screen.dart';
import '../../features/hall/presentation/hall_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/lost_found/presentation/lost_found_screen.dart';
import '../../features/mentorship/presentation/mentorship_screen.dart';
import '../../features/notifications/presentation/notification_center_screen.dart';
import '../../features/payment/presentation/payment_screen.dart';
import '../../features/registry/presentation/registry_list_screen.dart';
import '../../features/schedule/presentation/schedule_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/presentation/app_shell.dart';
import '../../features/splash/presentation/splash_screen.dart';
import '../../features/transport/presentation/transport_screen.dart';
import '../../features/vr_id/presentation/vr_id_screen.dart';
import '../../shared/animations/page_transitions.dart';

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
      if (session == null && !loc.startsWith('/auth')) return '/auth/login';
      if (session != null && loc.startsWith('/auth')) {
        // Fetch role to redirect correctly
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('*, roles(name)')
            .eq('id', session.user.id)
            .single();
        final role = profile['roles']['name'];
        if (role == 'super_admin') return '/admin-dashboard';
        return '/home';
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
          GoRoute(path: '/dept-chat',     pageBuilder: (c,s) => slideRightPage(const DeptChatScreen(), s)),
          GoRoute(path: '/vr-id',         pageBuilder: (c,s) => slideRightPage(const VrIdScreen(), s)),
          GoRoute(path: '/notifications', pageBuilder: (c,s) => slideRightPage(const NotificationCenterScreen(), s)),
          GoRoute(path: '/settings',      pageBuilder: (c,s) => slideRightPage(const SettingsScreen(), s)),
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
