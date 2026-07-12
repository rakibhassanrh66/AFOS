import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Extracts PDF text lines using the EXACT same call as
/// admin_upload_routine_screen.dart's _extractPdfLines (no page splitting),
/// run ON the Android device itself, to compare against the desktop
/// extraction and find any platform-specific text-run ordering difference.
/// Run with: flutter run -d <android-device-id> -t tool/inspect_routine_pdf_android.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final bytes = File('/data/data/com.example.afos_v7/files/routine_v5.pdf').readAsBytesSync();
  final doc = PdfDocument(inputBytes: bytes);
  final out = StringBuffer();
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

  final outFile = File('/data/data/com.example.afos_v7/files/routine_dump_android.txt');
  await outFile.writeAsString(out.toString());
  // ignore: avoid_print
  print('WROTE_DUMP_OK: ${await outFile.length()} bytes');
  exit(0);
}
