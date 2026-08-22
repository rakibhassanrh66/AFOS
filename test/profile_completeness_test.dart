import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/core/auth/profile_completeness.dart';

/// Mirrors `profile_is_complete()` in Postgres. The database is the authority;
/// this pins the required-field matrix somewhere a reviewer can read without a
/// live connection, and lets the form grey out Save without a round trip.
///
/// Every value here is synthetic. This repo is PUBLIC and no real student
/// record belongs in it.
void main() {
  Map<String, dynamic> base(String role) => {
        'role': role,
        'full_name': 'A Name',
        'phone': '01700000000',
        'gender': 'male',
        'emergency_contact': 'Someone 01700000001',
        'permanent_division': 'Dhaka',
        'permanent_district': 'Dhaka',
        'permanent_upazila': 'Savar',
        'department_id': 'd0000000-0000-0000-0000-000000000000',
        'batch': '68',
        'section': 'D',
        'semester': 5,
        'admission_season': 'summer',
        'admission_year': 2026,
        'joined_on': '2026-01-15',
        'designation': 'Lecturer',
      };

  group('student', () {
    test('a fully filled student is complete', () {
      expect(isProfileComplete(base('student')), isTrue);
    });

    test('no intake season is NOT complete', () {
      expect(isProfileComplete(base('student')..['admission_season'] = null),
          isFalse);
    });

    test('no intake year is NOT complete', () {
      expect(
          isProfileComplete(base('student')..['admission_year'] = null), isFalse);
    });

    test('no ID-card join date is NOT complete', () {
      expect(isProfileComplete(base('student')..['joined_on'] = null), isFalse);
    });

    test('no emergency contact is NOT complete', () {
      expect(isProfileComplete(base('student')..['emergency_contact'] = null),
          isFalse);
    });

    test('a missing address level is NOT complete', () {
      expect(isProfileComplete(base('student')..['permanent_upazila'] = null),
          isFalse);
    });
  });

  group('the blank-string trap', () {
    // `department = ''` already defeated `?? 'default'` once in this project
    // and rendered an empty chip. A blank string is not a filled field.
    test('whitespace-only phone is not a phone', () {
      expect(isProfileComplete(base('student')..['phone'] = '   '), isFalse);
    });

    test('empty-string batch is not a batch', () {
      expect(isProfileComplete(base('student')..['batch'] = ''), isFalse);
    });
  });

  group('teacher', () {
    test('needs joined_on and designation but NOT batch or section', () {
      final p = base('teacher')
        ..['batch'] = null
        ..['section'] = null
        ..['semester'] = null
        ..['admission_season'] = null
        ..['admission_year'] = null;
      expect(isProfileComplete(p), isTrue);
    });

    test('without a joining date is NOT complete', () {
      expect(isProfileComplete(base('teacher')..['joined_on'] = null), isFalse);
    });

    test('without a designation is NOT complete', () {
      expect(
          isProfileComplete(base('teacher')..['designation'] = null), isFalse);
    });
  });

  group('staff', () {
    test('needs designation and joined_on, not a department', () {
      final p = base('staff')
        ..['department_id'] = null
        ..['batch'] = null
        ..['section'] = null;
      expect(isProfileComplete(p), isTrue);
    });

    test('without a joining date is NOT complete', () {
      expect(isProfileComplete(base('staff')..['joined_on'] = null), isFalse);
    });
  });

  group('the edges', () {
    test('thana is optional for everyone', () {
      expect(isProfileComplete(base('student')..['permanent_thana'] = null),
          isTrue);
    });

    test('an admin carries no academic identity', () {
      final p = base('super_admin')
        ..['batch'] = null
        ..['joined_on'] = null
        ..['department_id'] = null
        ..['designation'] = null;
      expect(isProfileComplete(p), isTrue);
    });

    test('a missing profile row is NOT treated as complete', () {
      // role_session falls back to this when the fetch fails. An unreadable
      // profile must not walk past the completion gate.
      expect(isProfileComplete(<String, dynamic>{}), isFalse);
    });
  });
}
