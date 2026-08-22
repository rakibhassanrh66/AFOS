@Tags(['tool'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Dumps word positions from one seat-plan PDF so a parse that returns
/// nothing can be diagnosed against what the document actually contains,
/// rather than by reasoning about it.
///
///   flutter test tool/inspect_seat_pdf_test.dart --dart-define=PDF=<path>
void main() {
  test('dump', () {
    const path = String.fromEnvironment('PDF');
    final doc = PdfDocument(inputBytes: File(path).readAsBytesSync());
    // ignore: avoid_print
    print('PAGES: ${doc.pages.count}');
    final pages = doc.pages.count < 2 ? doc.pages.count : 2;
    for (var p = 0; p < pages; p++) {
      final lines =
          PdfTextExtractor(doc).extractTextLines(startPageIndex: p, endPageIndex: p);
      // ignore: avoid_print
      print('--- PAGE $p : ${lines.length} lines ---');
      var shown = 0;
      for (final l in lines) {
        final words = l.wordCollection.where((w) => w.text.trim().isNotEmpty).toList();
        if (words.isEmpty) continue;
        if (shown++ > 24) break;
        // ignore: avoid_print
        print('top=${words.first.bounds.top.round()} '
            '${words.map((w) => '${w.text}@${w.bounds.left.round()}').join(' ')}');
      }
    }
    doc.dispose();
  });
}
