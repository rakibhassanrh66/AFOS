@Tags(['tool'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Dumps the routine PDF's words with coordinates around a target token, so a
/// silently-dropped exam can be diagnosed against the document rather than
/// guessed at.
///
///   flutter test tool/inspect_routine_region_test.dart --dart-define=NEEDLE=CSE431
void main() {
  test('dump region', () {
    const needle = String.fromEnvironment('NEEDLE', defaultValue: 'CSE431');
    const path =
        r'C:\Users\Rakib Hassan\Downloads\Documents\Updated CSE Exam Routine Final Semester Summer 2026_2.pdf';
    final doc = PdfDocument(inputBytes: File(path).readAsBytesSync());
    for (var p = 0; p < doc.pages.count; p++) {
      final lines =
          PdfTextExtractor(doc).extractTextLines(startPageIndex: p, endPageIndex: p);
      final words = [
        for (final l in lines)
          for (final w in l.wordCollection)
            if (w.text.trim().isNotEmpty)
              (t: w.text, x: w.bounds.left, y: w.bounds.top)
      ];
      final hit = words.where((w) => w.t.contains(needle)).toList();
      if (hit.isEmpty) continue;
      // ignore: avoid_print
      print('=== PAGE $p — $needle at ${hit.map((h) => 'x=${h.x.round()},y=${h.y.round()}')} ===');
      final y0 = hit.first.y;
      final near = words.where((w) => (w.y - y0).abs() < 60).toList()
        ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
      for (final w in near) {
        // ignore: avoid_print
        print('  y=${w.y.round()} x=${w.x.round()} "${w.t}"');
      }
    }
    doc.dispose();
  });
}
