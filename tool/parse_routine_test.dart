@Tags(['tool'])
library;

import 'dart:io';

import 'package:afos_v7/features/exam_seat/data/exam_routine_pdf_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the routine parser over the real Summer-2026 final routine and prints
/// every entry, so its coverage can be checked against the seat plans (which
/// are a second, independent document for the same exams).
///
///   flutter test tool/parse_routine_test.dart
void main() {
  test('parse the Summer 2026 final exam routine', () {
    const path =
        r'C:\Users\Rakib Hassan\Downloads\Documents\Updated CSE Exam Routine Final Semester Summer 2026_2.pdf';
    final res = ExamRoutinePdfParser.parse(File(path).readAsBytesSync());

    // ignore: avoid_print
    print('HEADER: type=${res.header.examType} season=${res.header.season} '
        'year=${res.header.year} dept=${res.header.department}');
    // ignore: avoid_print
    print('ENTRIES: ${res.entries.length}  '
        'window=${res.startsOn} .. ${res.endsOn}');

    final byDate = <String, List<String>>{};
    for (final e in res.entries) {
      final d = e.date.toIso8601String().split('T').first;
      (byDate[d] ??= []).add('${e.courseCode}/${e.batch}@${e.slotLabel}');
    }
    for (final d in byDate.keys.toList()..sort()) {
      // ignore: avoid_print
      print('$d (${byDate[d]!.length}): ${(byDate[d]!..sort()).join(' ')}');
    }
    for (final w in res.warnings) {
      // ignore: avoid_print
      print('WARNING: $w');
    }
  });
}
