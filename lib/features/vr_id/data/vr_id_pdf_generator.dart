import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/supabase_config.dart';

/// Generates a VR-ID verification PDF (photo + name + full academic
/// detail) from the raw row `verify_vr_id_scan` returns, uploads it to the
/// private `vr-id-verifications` bucket, then opens a signed URL to it in
/// the device browser — this is the actual "scan opens a website showing
/// the PDF" behavior, replacing the previous local-only print/share sheet
/// (which also never included a photo or any academic field at all).
class VrIdPdfGenerator {
  static Future<void> generateAndOpen(Map<String, dynamic> scannedUser) async {
    final pdf = pw.Document();
    pw.MemoryImage? photo;
    final avatarUrl = scannedUser['avatar_url'] as String?;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      try {
        final res = await Dio().get<Uint8List>(avatarUrl,
            options: Options(responseType: ResponseType.bytes));
        if (res.data != null) photo = pw.MemoryImage(res.data!);
      } catch (_) {
        // No photo embedded if it can't be fetched — the rest of the
        // verification (name/ID/academic detail) is still generated.
      }
    }

    final role = scannedUser['role'] as String? ?? '';
    final isStudent = role == 'student';
    final rows = <List<String>>[
      ['Name', scannedUser['full_name'] as String? ?? '-'],
      ['University ID', scannedUser['university_id'] as String? ?? '-'],
      ['Department', scannedUser['department'] as String? ?? '-'],
      ['Role', role],
    ];
    if (isStudent) {
      rows.addAll([
        ['Batch', scannedUser['batch_label'] as String? ?? '-'],
        ['Section', scannedUser['section'] as String? ?? '-'],
        ['Semester', '${scannedUser['semester'] ?? '-'}'],
        ['CGPA', '${scannedUser['cgpa'] ?? '-'}'],
      ]);
    } else if (role == 'teacher') {
      rows.add(['Designation', scannedUser['designation'] as String? ?? '-']);
    }
    rows.add(['Scanned at', DateTime.now().toString()]);

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Header(level: 0, child: pw.Text('AFOS VR-ID Verification')),
            pw.SizedBox(height: 12),
            if (photo != null) pw.Center(child: pw.Container(
                width: 120, height: 120,
                decoration: const pw.BoxDecoration(shape: pw.BoxShape.circle),
                child: pw.ClipOval(child: pw.Image(photo, fit: pw.BoxFit.cover)))),
            pw.SizedBox(height: 16),
            pw.Text('VERIFIED', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(headers: ['Field', 'Value'], data: rows),
          ],
        ),
      ),
    );

    final bytes = await pdf.save();
    final scannerUid = SupabaseConfig.uid;
    if (scannerUid == null) return;
    final path = '$scannerUid/${scannedUser['id']}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    await SupabaseConfig.client.storage.from('vr-id-verifications').uploadBinary(
        path, bytes, fileOptions: const FileOptions(contentType: 'application/pdf'));
    final signedUrl = await SupabaseConfig.client.storage
        .from('vr-id-verifications').createSignedUrl(path, 300);
    await launchUrl(Uri.parse(signedUrl), mode: LaunchMode.externalApplication);
  }
}
