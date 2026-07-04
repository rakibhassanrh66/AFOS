import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../../shared/models/user_model.dart';

/// Mirrors TranscriptGenerator's shape — lets whoever scans a VR-ID save a
/// record of the verification (name/ID/department/role/scan time) so they
/// have proof the person was checked, independent of the in-app access log.
class VrIdPdfGenerator {
  static Future<void> generateVerification(UserModel user, DateTime scannedAt) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Header(level: 0, child: pw.Text('AFOS VR-ID Verification')),
            pw.SizedBox(height: 12),
            pw.Text('VERIFIED', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            pw.Table.fromTextArray(
              headers: ['Field', 'Value'],
              data: [
                ['Name', user.fullName],
                ['Student/University ID', user.studentId],
                ['Department', user.department],
                ['Role', user.role],
                ['Scanned at', scannedAt.toString()],
              ],
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }
}
