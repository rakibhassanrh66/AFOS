@Tags(['tool'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:afos_v7/features/exam_seat/data/exam_room_pdf_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Runs the app's OWN seat-plan parser over the real Summer-2026 final
/// documents and dumps what it read, so the import is verified against the
/// same code the upload screen runs rather than a throwaway reimplementation.
///
/// A test file rather than a script because syncfusion_flutter_pdf needs
/// dart:ui — `dart run` cannot load it. Not under test/ because it depends on
/// PDFs that live on one machine; run it explicitly:
///
///   flutter test tool/parse_seat_plans_test.dart --dart-define=OUT=<dir>
void main() {
  test('parse the Summer 2026 final seat plans', () {
    const outDir = String.fromEnvironment('OUT', defaultValue: '.');
    const dir = r'C:\Users\Rakib Hassan\Downloads\Documents';
    final files = [
      '19.08.26_Seat Details_Merged.pdf',
      '20.08.26_Seat Details_Merged.pdf',
      '22.08.26_Seat Details_Merged.pdf',
      '23.08.26_Seat Details_Merged.pdf',
      '24.08.26_Seat Details_Merged.pdf',
      '25.08.26_Seat Details_Merged.pdf',
      '27.08.26_Seat Details_Merged.pdf',
    ];

    final all = <Map<String, dynamic>>[];
    final summary = StringBuffer();

    for (final name in files) {
      final f = File('$dir\\$name');
      if (!f.existsSync()) {
        summary.writeln('MISSING: $name');
        continue;
      }
      List<ExamRoomAllocationRow> rows;
      try {
        rows = ExamRoomPdfParser.parse(f.readAsBytesSync());
      } catch (e) {
        summary.writeln('FAILED: $name -> $e');
        continue;
      }
      final maps = rows.map((r) => r.toRow()).toList();
      all.addAll(maps);

      // What matters for trusting the import: which dates, which courses, how
      // many sections and seats. A parser that silently drops a block shows up
      // here as a course list that does not match the routine.
      final dates = maps.map((m) => m['exam_date']).toSet().toList()..sort();
      final codes = maps
          .map((m) => m['course_code'])
          .where((c) => c != null)
          .toSet()
          .toList()
        ..sort();
      final nullCodes = maps.where((m) => m['course_code'] == null).length;
      final sections = maps.map((m) => '${m['batch']}_${m['section']}').toSet().length;
      final seats = maps.fold<int>(0, (a, m) => a + ((m['seats'] as int?) ?? 0));
      summary.writeln(name);
      summary.writeln('  rows=${maps.length} dates=$dates sections=$sections seats=$seats');
      summary.writeln('  courses(${codes.length})=$codes');
      if (nullCodes > 0) summary.writeln('  ROWS WITH NO COURSE CODE: $nullCodes');
      final slots = maps.map((m) => m['slot_label']).toSet().toList();
      summary.writeln('  slots=$slots times='
          '${maps.map((m) => '${m['slot_start']}-${m['slot_end']}').toSet().toList()}');
    }

    File('$outDir/seat_rows.json').writeAsStringSync(jsonEncode(all));
    File('$outDir/seat_summary.txt').writeAsStringSync(summary.toString());
    // ignore: avoid_print
    print(summary);
    // ignore: avoid_print
    print('TOTAL ROWS: ${all.length}');
  });
}
