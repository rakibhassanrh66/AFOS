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
    'class_routine': r'C:\Users\Rakib Hassan\Downloads\Documents\CSE Class Routine V4.2 Summer-2026_2.pdf',
    'exam_routine': r'C:\Users\Rakib Hassan\Downloads\Documents\CSE Exam Routine Mid Semester Summer 2026_2.pdf',
    'transport': r'C:\Users\Rakib Hassan\Downloads\Documents\Transport Schedule Mid-term Exam  Semester- Summer-2026. .xlsx - Transport Schedule Mid-term Exam _ Summer-2026.pdf',
  };

  final out = StringBuffer();
  for (final entry in files.entries) {
    out.writeln('===== ${entry.key} : ${entry.value} =====');
    final bytes = File(entry.value).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final textLines = PdfTextExtractor(doc).extractTextLines();
      final lines = textLines.map((l) => l.text.trim()).where((t) => t.isNotEmpty).toList();
      out.writeln('LINE_COUNT: ${lines.length}');
      for (var i = 0; i < lines.length; i++) {
        out.writeln('$i: ${lines[i]}');
      }
    } finally {
      doc.dispose();
    }
    out.writeln();
  }

  final outFile = File(r'E:\FYDP\AFOS\tool\routine_pdf_dump.txt');
  await outFile.writeAsString(out.toString());
  // ignore: avoid_print
  print('WROTE_DUMP_OK: ${await outFile.length()} bytes');
  exit(0);
}
