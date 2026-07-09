import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:afos_v7/bootstrap.dart';
import 'package:afos_v7/config/routes/app_router.dart';
import 'package:afos_v7/core/auth/role_session.dart';
import 'package:afos_v7/features/auth/presentation/login_screen.dart';
import 'package:afos_v7/features/dashboard/presentation/dashboard_screen.dart';
import 'package:afos_v7/main.dart';

/// Walks every screen reachable by each real role and asserts zero
/// RenderFlex overflow / layout exceptions. Runs against the real
/// production Supabase project using 5 persistent QA accounts (see
/// C:\Users\Rakib Hassan\.claude\plans\breezy-purring-pebble.md for the
/// full design rationale) -- not a mocked/staged environment, since none
/// exists for this project. Navigation is programmatic
/// (`AppRouter.router.go(route)`), never a simulated tap into an in-screen
/// action button, so no real data gets mutated by running this.
///
/// Run with e.g.:
///   flutter test integration_test/overflow_smoke_test.dart -d <device> \
///     --dart-define=QA_STUDENT_PASSWORD=... --dart-define=QA_TEACHER_PASSWORD=... \
///     --dart-define=QA_STAFF_PASSWORD=... --dart-define=QA_ADMIN_PASSWORD=... \
///     --dart-define=QA_SUPER_ADMIN_PASSWORD=...
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const commonRoutes = [
    '/home', '/schedule', '/transport', '/lost-found', '/clubs', '/grades',
    '/assignments', '/mentorship', '/dept-chat', '/notifications', '/settings', '/vr-id',
  ];

  const roleExtraRoutes = {
    'student': ['/library', '/hall', '/payment', '/exam-seat'],
    'teacher': ['/manage-notices', '/conference-room'],
    'staff': ['/conference-room', '/admin/library', '/admin/sos'],
    'admin': [
      '/admin/upload', '/admin/hall', '/admin/library', '/admin/dept-chat',
      '/admin/faculties', '/admin/departments', '/manage-notices',
      '/manage-exam-seats', '/admin/sos',
    ],
    'super_admin': [
      '/admin/upload', '/admin/hall', '/admin/library', '/admin/dept-chat',
      '/admin/faculties', '/admin/departments', '/manage-notices',
      '/manage-exam-seats', '/admin/sos',
      '/admin/users', '/admin/clubs', '/admin/conference-rooms', '/admin/feedback',
    ],
  };

  const credentials = {
    'student': ('qa_student@afos.test', String.fromEnvironment('QA_STUDENT_PASSWORD')),
    'teacher': ('qa_teacher@afos.test', String.fromEnvironment('QA_TEACHER_PASSWORD')),
    'staff': ('qa_staff@afos.test', String.fromEnvironment('QA_STAFF_PASSWORD')),
    'admin': ('rakibhassan.rh68+qaadmin@gmail.com', String.fromEnvironment('QA_ADMIN_PASSWORD')),
    'super_admin': ('rakibhassan.rh68+qasuperadmin@gmail.com', String.fromEnvironment('QA_SUPER_ADMIN_PASSWORD')),
  };

  // Fixed pump loop instead of pumpAndSettle() -- several screens have
  // perpetually-repeating animations (notification bell badge pulse, SOS
  // button pulse, both `.animate(onPlay: (c) => c.repeat(reverse: true))`),
  // which would make pumpAndSettle() never return.
  Future<void> settle(WidgetTester tester, {int cycles = 10}) async {
    for (var i = 0; i < cycles; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> loginAs(WidgetTester tester, String email, String password) async {
    await tester.enterText(find.byType(TextFormField).at(0), email);
    await tester.enterText(find.byType(TextFormField).at(1), password);
    await tester.tap(find.widgetWithText(GestureDetector, 'Sign in to AFOS').first);
    // Real network round-trip (Supabase Auth sign-in) plus, on a session
    // that's never been cached yet, up to 3 sequential profile/role/
    // verification queries the router's redirect chain awaits before
    // allowing navigation to /home to actually settle -- needs more than
    // the default per-route budget.
    await settle(tester, cycles: 25);
  }

  Future<Object?> visitRoute(WidgetTester tester, String route) async {
    AppRouter.router.go(route);
    await settle(tester);
    return tester.takeException();
  }

  Future<void> runRoleSmoke(WidgetTester tester, String role) async {
    final (email, password) = credentials[role]!;
    if (password.isEmpty) {
      fail('QA_${role.toUpperCase()}_PASSWORD was not provided via --dart-define');
    }

    await bootstrap();
    // RoleSession is a static, process-wide cache -- every testWidgets
    // block in this file shares the same Dart VM, so stale role/verification
    // data from a previous role must be cleared before logging in as the
    // next one, or the router's redirect gates make decisions using the
    // wrong role.
    await Supabase.instance.client.auth.signOut();
    RoleSession.clear();

    await tester.pumpWidget(const AFOSApp());
    // SplashScreen's own _animate() waits a real ~4.5s (Future.delayed calls
    // for the logo/tagline reveal) before it ever navigates anywhere -- on
    // a real device this is real wall-clock time, not a fake test clock, so
    // this needs a longer budget than the per-route settle() below.
    await settle(tester, cycles: 30);
    expect(find.byType(LoginScreen), findsOneWidget, reason: 'expected to land on login screen');

    await loginAs(tester, email, password);
    expect(find.byType(DashboardScreen), findsOneWidget,
        reason: 'login as $role did not land on the dashboard -- check credentials/gates');

    final routes = [...commonRoutes, ...?roleExtraRoutes[role]];
    final failures = <String>[];
    for (final route in routes) {
      final exception = await visitRoute(tester, route);
      if (exception != null) failures.add('$route: $exception');
    }

    expect(failures, isEmpty, reason: failures.join('\n\n'));
  }

  testWidgets('student screens have no overflow', (tester) async => runRoleSmoke(tester, 'student'));
  testWidgets('teacher screens have no overflow', (tester) async => runRoleSmoke(tester, 'teacher'));
  testWidgets('staff screens have no overflow', (tester) async => runRoleSmoke(tester, 'staff'));
  testWidgets('admin screens have no overflow', (tester) async => runRoleSmoke(tester, 'admin'));
  testWidgets('super_admin screens have no overflow', (tester) async => runRoleSmoke(tester, 'super_admin'));
}
