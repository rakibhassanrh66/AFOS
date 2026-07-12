import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Extracts PDF text lines exactly like admin_upload_routine_screen.dart's
/// _extractPdfLines, then dumps them to a text file for inspection against
/// the parse-routine edge function's regexes.
/// Run with: flutter run -d windows -t tool/inspect_routine_pdf.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final files = <String, String>{
    'class_routine_v5': r'C:\Users\Rakib Hassan\Downloads\Documents\CSE Class Routine V5 Summer-2026.pdf',
  };

  final out = StringBuffer();
  for (final entry in files.entries) {
    out.writeln('===== ${entry.key} : ${entry.value} =====');
    final bytes = File(entry.value).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    try {
      out.writeln('PAGE_COUNT: ${doc.pages.count}');
      var globalIdx = 0;
      for (var p = 0; p < doc.pages.count; p++) {
        final textLines = PdfTextExtractor(doc).extractTextLines(startPageIndex: p, endPageIndex: p);
        final lines = textLines.map((l) => l.text.trim()).where((t) => t.isNotEmpty).toList();
        out.writeln('--- PAGE $p : ${lines.length} lines ---');
        for (final l in lines) {
          out.writeln('$globalIdx: $l');
          globalIdx++;
        }
      }
    } finally {
      doc.dispose();
    }
    out.writeln();
  }

  final outFile = File(r'E:\FYDP\AFOS\tool\routine_pdf_dump_v5_paged.txt');
  await outFile.writeAsString(out.toString());
  // ignore: avoid_print
  print('WROTE_DUMP_OK: ${await outFile.length()} bytes');
  exit(0);
}
