import 'package:afos_v7/core/auth/capabilities.dart';
import 'package:flutter_test/flutter_test.dart';

/// The capability model is now the single answer to "what can this person do",
/// read by the slide menu, the web sidebar, the role console and the command
/// palette. `staff_menu_permissions_test.dart` already pins the staff and
/// delegation rules through the two re-exported functions; this file pins the
/// part those cannot see — every OTHER role, and the grouping the web UI is
/// built on.
///
/// THE BUG THIS EXISTS TO STOP COMING BACK. `dashboard_screen.dart` answered
/// the same question with a hardcoded twelve-tile grid whose only role logic
/// was subtracting four student-only tiles, and it never read
/// PermissionSession at all. A staff member, a delegated officer, a teacher and
/// an exam controller all got the same eight student-facing tiles. If anyone
/// ever reintroduces a second list, these tests will not catch it — but they
/// do guarantee the one model stays correct, which is what makes a second list
/// unnecessary.
void main() {
  Set<String> none() => const {};

  group('capability comes from role AND grants, not grants alone', () {
    // Measured against the live database: role_permissions has rows for only
    // super_admin (23), admin (4) and dept_admin (4). teacher, staff, student
    // and exam_controller hold ZERO role-derived permissions, so a model built
    // on grants alone would hand a teacher an empty app.
    test('a teacher with no grants still gets their teaching tools', () {
      final caps = capabilitiesFor(role: 'teacher', grants: none());
      final routes = caps.map((c) => c.route);
      expect(routes, containsAll([
        '/schedule/my-offerings',
        '/attendance',
        '/schedule/join-requests',
        '/schedule/teaching-load',
      ]));
    });

    test('a student with no grants still gets their own records', () {
      final routes =
          capabilitiesFor(role: 'student', grants: none()).map((c) => c.route);
      expect(routes, containsAll(['/hall', '/payment', '/library', '/exam-seat']));
    });

    test('a staff member with no grants gets no administrative tool at all',
        () {
      final routes =
          capabilitiesFor(role: 'staff', grants: none()).map((c) => c.route).toList();
      expect(routes.where((r) => r.startsWith('/admin')), isEmpty);
      expect(routes.where((r) => r.startsWith('/manage')), isEmpty);
      // What they DO get is what any employee gets: campus services and their
      // own account.
      expect(routes, containsAll(['/home', '/transport', '/lost-found', '/settings']));
    });
  });

  group('a grant reaches every role, not just staff', () {
    // The defect that was fixed for staff and left in place everywhere else:
    // the router and RLS both allowed the work, and the UI showed no door.
    for (final role in ['student', 'teacher', 'exam_controller', 'admin',
                        'dept_admin', 'super_admin']) {
      test('$role granted library:manage gets the library screen', () {
        final routes = capabilitiesFor(role: role, grants: const {'library:manage'})
            .map((c) => c.route);
        expect(routes, contains('/admin/library'));
      });
    }

    test('a granted entry is marked as delegated, a role entry is not', () {
      final caps = capabilitiesFor(role: 'student', grants: const {'library:manage'});
      final lib = caps.firstWhere((c) => c.route == '/admin/library');
      final home = caps.firstWhere((c) => c.route == '/home');
      // Provenance matters: a delegate who cannot tell "given to me" from
      // "comes with the job" cannot tell what they would lose if it were
      // revoked.
      expect(lib.delegated, isTrue);
      expect(home.delegated, isFalse);
    });

    test('a grant a role already covers is not listed twice', () {
      // A teacher already has Conference Room; granting conference:manage
      // must not produce a second entry.
      final routes = capabilitiesFor(
              role: 'teacher', grants: const {'conference:manage'})
          .map((c) => c.route)
          .toList();
      expect(routes.where((r) => r == '/conference-room').length, 1);
    });

    test('no role ever produces a duplicate route', () {
      for (final role in ['student', 'teacher', 'staff', 'admin', 'dept_admin',
                          'exam_controller', 'super_admin', null]) {
        final routes = capabilitiesFor(
          role: role,
          // Everything at once: the worst case for collisions.
          grants: const {
            'routine:upload', 'transport:upload', 'exam_seat:upload',
            'course_offerings:manage', 'hall:manage', 'library:manage',
            'conference:manage', 'sos:manage', 'notice:publish',
            'permissions:delegate', 'users:approve', 'cr:approve',
            'roles:assign', 'audit:read', 'feedback:triage',
          },
          isCr: true,
        ).map((c) => c.route).toList();
        expect(routes.toSet().length, routes.length,
            reason: 'role "$role" produced a duplicate route');
      }
    });
  });

  group('CR is a per-section flag, not a role', () {
    test('a CR gets room availability, a plain student does not', () {
      final cr = capabilitiesFor(role: 'student', grants: none(), isCr: true)
          .map((c) => c.route);
      final plain = capabilitiesFor(role: 'student', grants: none())
          .map((c) => c.route);
      expect(cr, contains('/room-availability'));
      expect(plain, isNot(contains('/room-availability')));
    });
  });

  group('grouping, which the web sidebar and console are built on', () {
    test('groups come back in reading order with none empty', () {
      final grouped =
          groupCapabilities(capabilitiesFor(role: 'super_admin', grants: none()));
      final order = grouped.keys.map((g) => g.order).toList();
      expect(order, equals([...order]..sort()));
      for (final entry in grouped.entries) {
        expect(entry.value, isNotEmpty,
            reason: '${entry.key} came back as an empty group');
      }
    });

    test('every capability lands in exactly one group', () {
      final caps = capabilitiesFor(role: 'super_admin', grants: none());
      final total =
          groupCapabilities(caps).values.fold<int>(0, (n, l) => n + l.length);
      expect(total, caps.length);
    });

    test('a super_admin has enough entries to need grouping at all', () {
      // The argument for the grouped sidebar: a flat list of this many rows is
      // a list, not navigation.
      final caps = capabilitiesFor(role: 'super_admin', grants: none());
      expect(caps.length, greaterThanOrEqualTo(20));
      expect(groupCapabilities(caps).length, greaterThanOrEqualTo(4));
    });
  });

  group('an unresolved profile falls back to the least privilege', () {
    test('a null role gets the student baseline and no admin tools', () {
      final routes =
          capabilitiesFor(role: null, grants: none()).map((c) => c.route).toList();
      expect(routes.where((r) => r.startsWith('/admin')), isEmpty);
      expect(routes, contains('/home'));
    });

    test('an unknown role does not silently gain anything', () {
      final routes = capabilitiesFor(role: 'chancellor', grants: none())
          .map((c) => c.route).toList();
      expect(routes.where((r) => r.startsWith('/admin')), isEmpty);
    });
  });
}
