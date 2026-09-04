import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/core/utils/validators.dart';

/// THE BUG THIS EXISTS FOR.
///
/// `AppValidators.studentId` demanded `^\d{3}-\d{2}-\d{4,6}$` — a four-digit
/// roll number — on the belief that a DIU ID is always batch-department-roll
/// in that exact shape. The registrar issues the ID and the roll is only as
/// long as the department is big, so a smaller or newer department produces
/// IDs like `253-33-105`, which the form rejected outright with "Invalid ID
/// format (e.g. 221-15-5678)". Those students could not create an account.
///
/// It left evidence in `profiles`: `25315550` is `253-15-550` with the dashes
/// taken out, and several 13-16 digit entries are phone or NID numbers —
/// people typing whatever would get them past the form. The rule is now a
/// sanity bound, and these cases are what it has to keep accepting.
void main() {
  group('accepts what the registrar actually issues', () {
    for (final id in const [
      '253-33-105', // the reported rejection: three-digit roll
      '221-15-5678', // the long-standing four-digit shape
      '253-15-550',
      '191-15-12345', // five-digit roll
      '25315550', // no dashes at all
      '0242220005101554', // long institutional number already in profiles
      'BBA-221-15-5678', // a department that prefixes with letters
      '221-15-5678-A', // a trailing section suffix
    ]) {
      test(id, () => expect(AppValidators.studentId(id), isNull));
    }
  });

  group('normalises before judging, and stores what it judged', () {
    test('spaces around the dashes are removed', () {
      expect(AppValidators.normalizeUniversityId(' 253 - 33 - 105 '), '253-33-105');
      expect(AppValidators.studentId('253 - 33 - 105'), isNull);
    });

    test('a soft-keyboard en dash becomes an ASCII hyphen', () {
      // U+2013. A student who long-presses '-' can produce this without ever
      // seeing the difference, and the ID would then fail to match every
      // other copy of itself.
      expect(AppValidators.normalizeUniversityId('253–33–105'), '253-33-105');
      expect(AppValidators.studentId('253–33–105'), isNull);
    });
  });

  group('still rejects what cannot be an ID', () {
    test('empty', () {
      expect(AppValidators.studentId(''), 'Student ID required');
      expect(AppValidators.studentId(null), 'Student ID required');
      expect(AppValidators.studentId('', type: AccountType.staff),
          'Employee ID required');
    });

    test('too short or too long', () {
      expect(AppValidators.studentId('12'), contains('too short'));
      expect(AppValidators.studentId('1' * 26), contains('too long'));
    });

    test('a name typed into the ID box', () {
      // No digit anywhere: the one shape that is never an issued ID.
      expect(AppValidators.studentId('Rakibul Islam'), isNotNull);
    });

    test('punctuation no registrar issues', () {
      expect(AppValidators.studentId('253/33/105'), isNotNull);
      expect(AppValidators.studentId('253--33-105'), isNotNull);
      expect(AppValidators.studentId('-253-33-105'), isNotNull);
      expect(AppValidators.studentId('253-33-105-'), isNotNull);
    });
  });

  test('employee IDs go through the same bound', () {
    expect(AppValidators.studentId('EMP-2291', type: AccountType.teacher), isNull);
    expect(AppValidators.studentId('710001234', type: AccountType.staff), isNull);
  });
}
