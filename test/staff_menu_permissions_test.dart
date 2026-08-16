import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/features/shell/presentation/slide_menu.dart';

/// What a staff member or officer can reach.
///
/// The old staff branch was `[..._commonItems, _conferenceRoomItem,
/// _libraryAdminItem, _sosAdminItem, _feedbackItem]` — which handed every
/// employee Class Schedule, Clubs, Results, Assignments, Mentorship, Dept Chat,
/// Manage Library and Manage SOS Alerts simply for having the job title. These
/// tests exist so that cannot quietly come back: the interesting property is
/// what is ABSENT with no grants, and absence is exactly what nobody notices
/// regressing.
void main() {
  _delegationIsRoleAgnostic();
  _decisionGrantsReachTheMenu();

  group('staff menu with no delegated permissions', () {
    final routes = staffMenuRoutes(const {});

    test('is just the employee baseline', () {
      expect(routes, [
        '/home',
        '/transport',
        '/lost-found',
        '/sos/nearby',
        '/notifications',
        '/settings',
        '/feedback',
      ]);
    });

    test('contains no administrative screen at all', () {
      for (final admin in const [
        '/admin/upload',
        '/admin/course-offerings',
        '/admin/hall',
        '/admin/library',
        '/admin/sos',
        '/manage-notices',
        '/manage-exam-seats',
        '/conference-room',
      ]) {
        expect(routes, isNot(contains(admin)),
            reason: '$admin must be delegated, never granted by job title');
      }
    });

    test('drops the student/teacher screens a staff member has no use for', () {
      // A Registrar has no class routine, no club membership, no results, no
      // assignments and no mentor. These came in via _commonItems.
      for (final academic in const [
        '/schedule',
        '/clubs',
        '/grades',
        '/assignments',
        '/mentorship',
        '/dept-chat',
      ]) {
        expect(routes, isNot(contains(academic)));
      }
    });
  });

  group('a delegated permission adds exactly its own screen', () {
    test('library:manage', () {
      final r = staffMenuRoutes(const {'library:manage'});
      expect(r, contains('/admin/library'));
      expect(r, isNot(contains('/admin/hall')));
      expect(r, isNot(contains('/admin/sos')));
    });

    test('sos:manage', () {
      expect(staffMenuRoutes(const {'sos:manage'}), contains('/admin/sos'));
    });

    test('notice:publish', () {
      expect(staffMenuRoutes(const {'notice:publish'}), contains('/manage-notices'));
    });

    test('hall:manage', () {
      expect(staffMenuRoutes(const {'hall:manage'}), contains('/admin/hall'));
    });

    test('conference:manage', () {
      expect(staffMenuRoutes(const {'conference:manage'}), contains('/conference-room'));
    });

    test('course_offerings:manage', () {
      expect(staffMenuRoutes(const {'course_offerings:manage'}),
          contains('/admin/course-offerings'));
    });
  });

  group('/admin/upload — one screen behind three grants', () {
    // app_router.dart admits this route on ANY of routine:upload,
    // transport:upload or exam_seat:upload. The menu has to agree with all
    // three, or a user is granted access to a screen with no way to reach it.
    for (final grant in const ['routine:upload', 'transport:upload', 'exam_seat:upload']) {
      test('$grant alone reveals it', () {
        expect(staffMenuRoutes({grant}), contains('/admin/upload'));
      });
    }

    test('appears once when several of them are granted together', () {
      final r = staffMenuRoutes(const {'routine:upload', 'transport:upload', 'exam_seat:upload'});
      expect(r.where((x) => x == '/admin/upload').length, 1);
    });

    test('exam_seat:upload also reveals the exam seat screen, routine:upload does not', () {
      expect(staffMenuRoutes(const {'exam_seat:upload'}), contains('/manage-exam-seats'));
      expect(staffMenuRoutes(const {'routine:upload'}), isNot(contains('/manage-exam-seats')));
    });
  });

  group('ordering and shape', () {
    test('Feedback stays last however many permissions are granted', () {
      final all = staffMenuRoutes(const {
        'routine:upload', 'transport:upload', 'exam_seat:upload',
        'course_offerings:manage', 'hall:manage', 'library:manage',
        'conference:manage', 'sos:manage', 'notice:publish',
      });
      expect(all.last, '/feedback');
    });

    test('a fully delegated staff member has no duplicate entries', () {
      final all = staffMenuRoutes(const {
        'routine:upload', 'transport:upload', 'exam_seat:upload',
        'course_offerings:manage', 'hall:manage', 'library:manage',
        'conference:manage', 'sos:manage', 'notice:publish',
      });
      expect(all.toSet().length, all.length);
    });

    test('an unrelated grant changes nothing', () {
      expect(staffMenuRoutes(const {'marks:insert', 'students:select'}),
          staffMenuRoutes(const {}));
    });
  });
}

/// Delegation is not a staff-only feature.
///
/// THE BUG THESE PIN. `delegatedRoutes` used to be inlined inside
/// `staffMenuRoutes`, so only `staff` gained anything from a grant. Grant
/// `library:manage` to a TEACHER, or `routine:upload` to a STUDENT, and:
///   * RLS allowed the work,
///   * app_router allowed the screen (it asks PermissionSession),
///   * and the menu showed nothing — reachable only by typing the URL.
///
/// It is the same defect that was found and fixed for staff, left in place for
/// every other role. These tests are about the shared list, so a future edit
/// cannot quietly re-inline it and strand the other roles again.
void _delegationIsRoleAgnostic() {
  group('delegated routes are independent of role', () {
    test('no grants unlocks nothing', () {
      expect(delegatedRoutes(const {}), isEmpty);
    });

    test('one grant unlocks exactly one screen', () {
      expect(delegatedRoutes(const {'library:manage'}), ['/admin/library']);
      expect(delegatedRoutes(const {'hall:manage'}), ['/admin/hall']);
      expect(delegatedRoutes(const {'notice:publish'}), ['/manage-notices']);
    });

    test('the upload screen answers to any of its three grants, once', () {
      const each = ['routine:upload', 'transport:upload', 'exam_seat:upload'];
      for (final g in each) {
        expect(delegatedRoutes({g}), contains('/admin/upload'),
            reason: '$g must reveal the upload screen');
      }
      // All three together must not list it three times.
      final all = delegatedRoutes(each.toSet());
      expect(all.where((r) => r == '/admin/upload').length, 1);
    });

    test('permissions:delegate reveals the assign-work screen', () {
      // A senior manager needs Manage Users, because that is where the
      // permission sheet lives. The router opens it for them too.
      expect(delegatedRoutes(const {'permissions:delegate'}),
          contains('/admin/users'));
      expect(delegatedRoutes(const {'library:manage'}),
          isNot(contains('/admin/users')),
          reason: 'holding an unrelated area must not expose Manage Users');
    });

    test('an unknown grant unlocks nothing', () {
      expect(delegatedRoutes(const {'nonsense:action'}), isEmpty);
    });

    test('staffMenuRoutes is its baseline plus exactly these', () {
      // The one that stops the two drifting apart again: whatever staff gets
      // beyond the employee baseline must BE the delegated list.
      const grants = {'library:manage', 'hall:manage'};
      final staff = staffMenuRoutes(grants);
      final baseline = staffMenuRoutes(const {});
      final extra = staff.where((r) => !baseline.contains(r)).toList();
      expect(extra, delegatedRoutes(grants));
    });
  });
}

/// Decisions are delegable now, not just work.
///
/// The gap these pin: every approval in the app used to resolve to
/// `get_my_profile_role() = 'super_admin'`. An officer running a department
/// had to be made super_admin — which hands them account deletion — or wait
/// for the owner. `cr:approve`, `users:approve`, `roles:assign`,
/// `feedback:triage` and `audit:read` are ordinary grants, so the menu has to
/// treat them like every other one.
void _decisionGrantsReachTheMenu() {
  group('decision permissions unlock their screens', () {
    test('audit:read reveals the activity log, and nothing else does', () {
      expect(delegatedRoutes(const {'audit:read'}), ['/admin/activity']);
      expect(delegatedRoutes(const {'library:manage'}),
          isNot(contains('/admin/activity')));
    });

    test('feedback:triage reveals feedback triage', () {
      expect(delegatedRoutes(const {'feedback:triage'}), ['/admin/feedback']);
    });

    test('four separate jobs all open Manage Users', () {
      // They are four different reasons to need one screen, and the router
      // admits the same four. A holder of any one must get the menu entry.
      for (final g in ['permissions:delegate', 'users:approve', 'cr:approve',
                       'roles:assign']) {
        expect(delegatedRoutes({g}), contains('/admin/users'),
            reason: '\$g must reveal Manage Users');
      }
    });

    test('holding several of them lists Manage Users once', () {
      final all = delegatedRoutes(const {
        'permissions:delegate', 'users:approve', 'cr:approve', 'roles:assign',
      });
      expect(all.where((r) => r == '/admin/users').length, 1);
    });

    test('a decision grant does not leak a work screen', () {
      // cr:approve is authority over a decision, not a licence to upload
      // routines. Nothing but the four Manage Users grants may widen it.
      expect(delegatedRoutes(const {'cr:approve'}), ['/admin/users']);
    });

    test('staff get decision screens through the same shared list', () {
      const grants = {'cr:approve', 'audit:read'};
      final staff = staffMenuRoutes(grants);
      expect(staff, containsAll(['/admin/users', '/admin/activity']));
      // and still ends with Feedback
      expect(staff.last, '/feedback');
    });
  });
}
