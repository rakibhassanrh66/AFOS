import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class TranscriptGenerator {
  static Future<void> generateTranscript(Map<String, dynamic> studentData, List<Map<String, dynamic>> results) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Header(level: 0, child: pw.Text('Official Transcript: ${studentData['full_name']}')),
              pw.Table.fromTextArray(
                headers: ['Semester', 'SGPA', 'Credits'],
                data: results.map((r) => [r['semester_name'], r['sgpa'].toString(), r['total_credits'].toString()]).toList(),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }
}
