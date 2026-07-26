import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/features/attendance/data/repositories/attendance_repository.dart';

void main() {
  group('labGroupLabel', () {
    // The naming rule the university actually uses: a theory section 63M
    // splits into lab groups 63M1 and 63M2. Pinned because it is composed from
    // three separate columns and is easy to reorder into "1 63M" by accident.
    test('composes batch + section + subgroup', () {
      expect(labGroupLabel('63', 'M', 1), '63M1');
      expect(labGroupLabel('63', 'M', 2), '63M2');
    });

    test('drops the subgroup for a theory section', () {
      expect(labGroupLabel('63', 'M', null), '63M');
    });

    test('tolerates missing batch or section rather than printing null', () {
      expect(labGroupLabel(null, 'M', 1), 'M1');
      expect(labGroupLabel('63', null, 2), '632');
      expect(labGroupLabel(null, null, null), '');
    });
  });

  group('isLab', () {
    test('reads course_type off the embedded course row', () {
      expect(
          AttendanceRepository.isLab({
            'courses': {'course_type': 'lab'}
          }),
          isTrue);
      expect(
          AttendanceRepository.isLab({
            'courses': {'course_type': 'theory'}
          }),
          isFalse);
    });

    // A missing or unembedded course must not be treated as a lab: that would
    // hide the whole register behind a group selector with no groups.
    test('defaults to theory when the course is missing', () {
      expect(AttendanceRepository.isLab(const {}), isFalse);
      expect(AttendanceRepository.isLab(const {'courses': null}), isFalse);
    });
  });

  group('dateOnly', () {
    // Not toIso8601String(): that renders in UTC, which files an evening class
    // in Dhaka (UTC+6) under the following day.
    test('formats local Y-M-D zero-padded', () {
      expect(AttendanceRepository.dateOnly(DateTime(2026, 7, 26)), '2026-07-26');
      expect(AttendanceRepository.dateOnly(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('uses the local calendar day for a late-evening class', () {
      // 23:30 local on the 26th is already the 27th in UTC.
      expect(AttendanceRepository.dateOnly(DateTime(2026, 7, 26, 23, 30)),
          '2026-07-26');
    });
  });
}
