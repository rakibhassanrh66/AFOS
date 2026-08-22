@Tags(['tool'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Lists every date row, batch token and course code per page with their
/// coordinates, so a block that straddles a page break can be reasoned about
/// from the document instead of from assumptions.
///
///   flutter test tool/inspect_routine_dates_test.dart
void main() {
  test('dates and batches per page', () {
    const path =
        r'C:\Users\Rakib Hassan\Downloads\Documents\Updated CSE Exam Routine Final Semester Summer 2026_2.pdf';
    final doc = PdfDocument(inputBytes: File(path).readAsBytesSync());
    final date = RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$');
    final batch = RegExp(r'^Batch\s*[-–—]\s*\d+$', caseSensitive: false);
    final code = RegExp(r'([A-Z]{2,4})\s*(\d{3})');

    for (var p = 0; p < doc.pages.count; p++) {
      final lines =
          PdfTextExtractor(doc).extractTextLines(startPageIndex: p, endPageIndex: p);
      final rows = <String>[];
      for (final l in lines) {
        for (final w in l.wordCollection) {
          final t = w.text.trim();
          if (t.isEmpty) continue;
          final kind = date.hasMatch(t)
              ? 'DATE'
              : batch.hasMatch(t)
                  ? 'BATCH'
                  : code.hasMatch(t.toUpperCase())
                      ? 'CODE'
                      : null;
          if (kind == null) continue;
          rows.add('  $kind y=${w.bounds.top.round()} x=${w.bounds.left.round()} "$t"');
        }
      }
      // ignore: avoid_print
      print('=== PAGE $p (${rows.length} markers) ===');
      for (final r in rows) {
        // ignore: avoid_print
        print(r);
      }
    }
    doc.dispose();
  });
}
