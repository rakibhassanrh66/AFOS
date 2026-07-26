import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/features/schedule/presentation/join_requests_screen.dart';

/// The bulk admit on the Join Requests screen lets students into a course WITHOUT
/// the teacher looking at them individually, so the rule deciding who qualifies
/// is the one piece of that screen that must not drift silently.
void main() {
  Map<String, dynamic> request({
    String status = 'pending',
    String? studentBatch = '68',
    String? studentSection = 'D',
    String offeringBatch = '68',
    String offeringSection = 'D',
  }) =>
      {
        'status': status,
        'profiles': {'batch': studentBatch, 'section': studentSection},
        'course_offerings': {'batch': offeringBatch, 'section': offeringSection},
      };

  group('joinRequestMatchesSection', () {
    test('matches a student already in the offering\'s batch and section', () {
      expect(joinRequestMatchesSection(request()), isTrue);
    });

    test('is case- and whitespace-insensitive', () {
      // Section is typed by hand in several places; ' d ' and 'D' are the same
      // section and must not become a false mismatch a teacher has to clear.
      expect(
          joinRequestMatchesSection(
              request(studentSection: ' d ', offeringSection: 'D')),
          isTrue);
    });

    test('rejects a different section', () {
      expect(joinRequestMatchesSection(request(studentSection: 'C')), isFalse);
    });

    test('rejects a different batch', () {
      expect(joinRequestMatchesSection(request(studentBatch: '67')), isFalse);
    });

    test('rejects anything not pending', () {
      // Guards against a bulk run re-approving rows it already handled.
      for (final s in ['approved', 'rejected']) {
        expect(joinRequestMatchesSection(request(status: s)), isFalse,
            reason: '$s must not be swept into a bulk admit');
      }
    });

    // The conservative cases. An incomplete profile must fall through to manual
    // review rather than be admitted by an empty-string comparison — which is
    // what a naive `student.batch == offering.batch` would do when both sides
    // are missing.
    test('rejects a student with no batch or section recorded', () {
      expect(joinRequestMatchesSection(request(studentBatch: null)), isFalse);
      expect(joinRequestMatchesSection(request(studentSection: null)), isFalse);
      expect(joinRequestMatchesSection(request(studentBatch: '')), isFalse);
      expect(joinRequestMatchesSection(request(studentSection: '  ')), isFalse);
    });

    test('rejects when the embedded profile or offering is missing entirely', () {
      expect(joinRequestMatchesSection({'status': 'pending'}), isFalse);
      expect(
          joinRequestMatchesSection({
            'status': 'pending',
            'profiles': {'batch': '68', 'section': 'D'},
          }),
          isFalse);
    });
  });
}
