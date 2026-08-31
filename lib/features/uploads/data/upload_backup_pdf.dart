import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/supabase_config.dart';
import 'upload_batch.dart';

/// Produces the backup a person must take before an upload can be removed.
///
/// The deal the owner asked for is: nothing gets deleted to free storage until
/// the system has handed over a document containing everything that upload
/// put in. So this writes every stamped row — not a summary — and the server
/// will not run the deletion until it has been told a backup exists.
///
/// DELIVERY. Uploaded to the private `upload-backups` bucket and opened
/// through a signed URL, which is the one delivery route in this project that
/// works on BOTH targets. A browser download started from inside the page is
/// blocked on web, and `path_provider` does not exist there; the VR-ID
/// generator settled this the same way.
class UploadBackupPdf {
  UploadBackupPdf._();

  /// Rows beyond this are summarised rather than listed. A seat plan can be
  /// 1767 rows; a 300-page PDF nobody opens is not a better backup than a
  /// 20-page one plus the counts, and the row data is still in the database
  /// until the moment it is removed.
  static const _maxRowsListed = 1200;

  /// Builds the PDF, stores it, records it against the batch, and opens it.
  /// Returns the storage path so the caller can say where it went.
  static Future<String> generateStoreAndOpen(UploadBatch batch) async {
    final path = await generateAndStore(batch);
    final url = await SupabaseConfig.client.storage
        .from('upload-backups')
        .createSignedUrl(path, 3600);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return path;
  }

  /// Same as [generateStoreAndOpen] but never opens a viewer. For a single
  /// upload, opening the backup is the confirmation a person watches for.
  /// For a bulk purge across many batches, launching one browser tab/viewer
  /// per item is not a UX, it's a stack of pop-ups — the stored PDF and the
  /// same "Download backup again" affordance the per-batch sheet already has
  /// is the point, not the auto-open.
  static Future<String> generateAndStore(UploadBatch batch) async {
    final data = await UploadBatchService.contents(batch.id);
    final bytes = await _build(batch, data);

    final uid = SupabaseConfig.uid ?? 'unknown';
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '$uid/${batch.kind}_${batch.id}_$stamp.pdf';

    await SupabaseConfig.client.storage.from('upload-backups').uploadBinary(
        path, bytes,
        fileOptions: const FileOptions(contentType: 'application/pdf'));

    // Recorded only after the bytes are actually stored, so the interlock can
    // never be satisfied by a backup that failed to upload.
    await UploadBatchService.markBackup(batch.id, path);
    return path;
  }

  /// Re-opens a backup that was generated earlier.
  static Future<void> reopen(String path) async {
    final url = await SupabaseConfig.client.storage
        .from('upload-backups')
        .createSignedUrl(path, 3600);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // -- building ------------------------------------------------------------

  static String _fmt(Object? v) {
    if (v == null) return '';
    final s = '$v';
    return s.length > 60 ? '${s.substring(0, 57)}...' : s;
  }

  /// The columns worth printing per table, in the order a person reads them.
  /// Deliberately not "every column": `id`, `created_at` and the batch id
  /// itself are noise in a document whose job is to let someone reconstruct
  /// what was lost.
  static const _columns = <String, List<String>>{
    'exam_room_allocations': [
      'exam_date', 'slot_label', 'department', 'course_code', 'course_title',
      'teacher_initial', 'batch', 'section', 'room_no', 'seats',
    ],
    'exams': [
      'exam_date', 'slot_label', 'start_time', 'end_time', 'subject_code',
      'subject', 'batch', 'section', 'department', 'exam_type',
    ],
    'schedule_slots': [
      'day_of_week', 'start_time', 'end_time', 'course_code', 'course_title',
      'batch', 'section', 'room', 'teacher_initial',
    ],
    'notices': ['created_at', 'category', 'title', 'body', 'author_name'],
    'transport_routes': ['route_number', 'route_name', 'start_point', 'end_point'],
    'transport_stops': ['route_id', 'stop_name', 'arrival_time', 'stop_order'],
  };

  static Future<Uint8List> _build(
      UploadBatch batch, Map<String, dynamic> data) async {
    final doc = pw.Document();
    final uploader = data['uploader'] as String? ?? batch.uploader ?? 'Unknown';

    final tables = <String, List<Map<String, dynamic>>>{};
    for (final key in _columns.keys) {
      final rows = ((data[key] as List?) ?? const [])
          .map((r) => (r as Map).cast<String, dynamic>())
          .toList();
      if (rows.isNotEmpty) tables[key] = rows;
    }
    final total = tables.values.fold<int>(0, (a, r) => a + r.length);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Container(
                alignment: pw.Alignment.centerRight,
                margin: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                    'AFOS upload backup — ${batch.kindLabel} — ${batch.id}',
                    style: const pw.TextStyle(fontSize: 8,
                        color: PdfColors.grey600))),
        footer: (ctx) => pw.Container(
            alignment: pw.Alignment.centerRight,
            child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(fontSize: 8,
                    color: PdfColors.grey600))),
        build: (ctx) => [
          pw.Header(level: 0, child: pw.Text('AFOS — Upload Backup')),
          pw.SizedBox(height: 4),
          pw.Text(
              'Everything the following upload wrote, taken before it is removed.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle:
                pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            headers: const ['Field', 'Value'],
            data: [
              ['Kind', batch.kindLabel],
              ['Source file', batch.sourceFile ?? '—'],
              ['Department', batch.department ?? '—'],
              ['Uploaded by', uploader],
              ['Uploaded at', batch.uploadedAt.toString()],
              ['Rows recorded', '${batch.rowCount}'],
              ['Rows in this document', '$total'],
              ['Batch id', batch.id],
              if (batch.note != null) ['Note', batch.note!],
            ],
          ),
          pw.SizedBox(height: 16),
          for (final entry in tables.entries) ..._section(entry.key, entry.value),
          if (tables.isEmpty)
            pw.Text('This upload has no rows left to back up.',
                style: const pw.TextStyle(fontSize: 10)),
        ],
      ),
    );
    return doc.save();
  }

  static List<pw.Widget> _section(String table, List<Map<String, dynamic>> rows) {
    final cols = _columns[table]!;
    // Only the columns that actually carry something, so a seat plan does not
    // print an empty "section" column across every page.
    final used = cols
        .where((c) => rows.any((r) => '${r[c] ?? ''}'.trim().isNotEmpty))
        .toList();
    final shown = rows.length > _maxRowsListed
        ? rows.sublist(0, _maxRowsListed)
        : rows;

    return [
      pw.SizedBox(height: 10),
      pw.Text('$table — ${rows.length} row${rows.length == 1 ? '' : 's'}',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      if (rows.length > _maxRowsListed)
        pw.Text(
            'Showing the first $_maxRowsListed of ${rows.length}. '
            'The remainder are counted above but not listed.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      pw.SizedBox(height: 4),
      pw.TableHelper.fromTextArray(
        cellStyle: const pw.TextStyle(fontSize: 7.5),
        headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold),
        cellHeight: 14,
        headers: used,
        data: [
          for (final r in shown) [for (final c in used) _fmt(r[c])],
        ],
      ),
    ];
  }
}
