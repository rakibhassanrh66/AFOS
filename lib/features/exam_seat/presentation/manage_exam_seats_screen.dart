import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../uploads/data/upload_batch.dart';
import '../data/exam_room_pdf_parser.dart';

import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/responsive.dart';
/// admin/dept_admin/super_admin/exam_controller: upload one or more real
/// exam seat-plan PDFs. Confirmed against an actual DIU sample document —
/// these publish room *capacity* per batch+section (a section spans
/// several rooms, and a room can be split between two adjacent sections),
/// never an individual student seat number, so that's exactly what this
/// stores and what students see (see exam_seat_screen.dart).
class ManageExamSeatsScreen extends StatefulWidget {
  const ManageExamSeatsScreen({super.key});
  @override State<ManageExamSeatsScreen> createState() => _ManageExamSeatsScreenState();
}

class _ManageExamSeatsScreenState extends State<ManageExamSeatsScreen> {
  List<PlatformFile> _files = [];
  List<ExamRoomAllocationRow> _parsedRows = [];
  bool _parsing = false, _uploading = false;
  String? _error;

  Future<void> _pickFiles() async {
    // withData: true -- on web, PlatformFile.path is always unavailable
    // (accessing the getter itself throws); .bytes is the only cross-platform
    // way to read the picked file's content, and it's only populated if
    // requested up front here.
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true, withData: true);
    // BUG_REGISTER P1-01: setState after an awaited platform round-trip with
    // no mounted guard. The file picker is exactly the kind of await a user
    // can navigate away from.
    if (!mounted) return;
    if (res != null) setState(() { _files = res.files; _parsedRows = []; _error = null; });
  }

  Future<void> _parseAll() async {
    setState(() { _parsing = true; _error = null; });
    try {
      final allRows = <ExamRoomAllocationRow>[];
      for (final f in _files) {
        final bytes = f.bytes ?? (f.path != null ? File(f.path!).readAsBytesSync() : null);
        if (bytes == null) continue;
        // The heaviest of the three parsers per-page word extraction +
        // row-grouping + multi-tier regex classification — and this loop
        // can run it across several files back to back, so compute() keeps
        // the "Parsing…" state responsive instead of one long UI freeze.
        allRows.addAll(await compute(ExamRoomPdfParser.parse, bytes));
      }
      if (allRows.isEmpty) {
        throw "No seat allocation rows found — these may be scanned images rather than text PDFs, or don't match the expected table layout.";
      }
      if (mounted) setState(() => _parsedRows = allRows);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _parsing = false);
  }

  Future<void> _upload() async {
    setState(() { _uploading = true; _error = null; });
    String? batchId;
    try {
      // Opened before anything is written so every row can carry it, which is
      // what makes this upload removable later as a unit instead of by
      // guessing at a date range.
      batchId = await UploadBatchService.open(
        kind: 'exam_seat_plan',
        sourceFile: _files.map((f) => f.name).join(', '),
      );

      // Replace, not append — re-uploading the same exam date(s) (e.g. a
      // corrected PDF) shouldn't leave stale duplicate rows behind.
      final dates = _parsedRows.map((r) => r.examDate.toIso8601String().split('T').first).toSet();
      for (final d in dates) {
        await SupabaseConfig.client.from('exam_room_allocations').delete().eq('exam_date', d);
      }

      // Stamp the term these dates fall in. Without this every upload files
      // rows with term_id null — which is precisely the state the table was
      // found in: 1632 allocations that nothing joined to any exam period,
      // sitting beside a routine that could not see them.
      final ordered = dates.toList()..sort();
      String? termId;
      try {
        final terms = await SupabaseConfig.client.from('exam_terms')
            .select('id').lte('starts_on', ordered.first)
            .gte('ends_on', ordered.last).limit(1) as List;
        if (terms.isNotEmpty) termId = terms.first['id'] as String?;
      } catch (_) {
        // A failed lookup must not cost the upload — the rows are still
        // usable, they are just not linked. Reported below rather than hidden.
      }

      await SupabaseConfig.client.from('exam_room_allocations').insert(
          _parsedRows.map((r) => {
                ...r.toRow(),
                if (termId != null) 'term_id': termId,
                'upload_batch_id': batchId,
              }).toList());

      // Closed with the server's own count of stamped rows, so the history
      // reports what landed rather than what was sent.
      await UploadBatchService.finalize(batchId, summary: {
        'dates': dates.length,
        'sections': _parsedRows.map((r) => '${r.batch}_${r.section}').toSet().length,
        'seats': _parsedRows.fold<int>(0, (a, r) => a + r.seats),
        if (termId == null) 'unlinked': true,
      });

      // Notify every affected student — exam_controller has no direct
      // `students` read access (see list_students_by_batch_section), and
      // direct-userIds sends are capped at 20 recipients per call, so
      // resolve+chunk per distinct batch+section rather than one send.
      final sections = _parsedRows.map((r) => '${r.batch}_${r.section}').toSet();
      for (final key in sections) {
        final parts = key.split('_');
        final batch = parts[0], section = parts.sublist(1).join('_');
        try {
          final res = await SupabaseConfig.client.rpc('list_students_by_batch_section',
              params: {'p_batch': batch, 'p_section': section}) as List;
          final ids = res.map((r) => (r as Map)['profile_id'] as String).toList();
          for (var i = 0; i < ids.length; i += 20) {
            await NotificationService.sendToUsers(
              userIds: ids.sublist(i, i + 20 > ids.length ? ids.length : i + 20),
              title: 'Exam seat plan published',
              message: 'Your exam room allocation is now available — check Exam Seat Plan.',
              category: 'exam', deepLink: '/exam-seat',
            );
          }
        } catch (_) {
          // Best-effort — a notification failure shouldn't undo the upload.
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${_parsedRows.length} room allocations uploaded across ${dates.length} exam date(s)'
                // Say it plainly rather than reporting a clean success for
                // rows that belong to no exam period.
                '${termId == null ? ' — no published exam term covers these dates, so they are not linked to one' : ''}'),
            backgroundColor: termId == null ? AppColors.amber : AppColors.green));
        setState(() { _files = []; _parsedRows = []; });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    final distinctDates = _parsedRows.map((r) => r.examDate).toSet().length;
    final distinctSections = _parsedRows.map((r) => '${r.batch}_${r.section}').toSet().length;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Exam Seat Plan Upload'),
      // Same reason as settings_screen: a bare ListView stretches a column of
      // label/control pairs across the whole 1440px window, putting each
      // control an arm's length from the thing it belongs to. 760 is the form
      // measure, not AdaptiveContentWidth's 1100 dashboard default.
      body: AdaptiveContentWidth(maxWidth: 760, child:
        ListView(padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 16 + NavInsets.of(context)), children: [
        const FeatureHeader(
          title: 'Exam Seat Plan Upload',
          subtitle: 'Publish room allocations from the official PDF',
          icon: AppIcons.examSeat,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.orange, AppColors.amber]),
          margin: EdgeInsets.only(bottom: 16),
        ),
        Text('Upload the official exam seat-plan PDF(s) — you can select several at once '
                '(e.g. one per exam date). Each is parsed for room/seat allocations per batch+section.',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 16),
        AfosButton(label: 'Pick PDF(s)', icon: Icons.upload_file_rounded, onTap: _pickFiles),
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 12),
          SurfaceCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: _files.map((f) => Padding(padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(f.name, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimaryOf(context))))).toList())),
          const SizedBox(height: 12),
          AfosButton(label: 'Parse ${_files.length} File(s)', loading: _parsing, onTap: _parseAll),
        ],
        if (_parsedRows.isNotEmpty) ...[
          const SizedBox(height: 16),
          SurfaceCard(child: Row(children: [
            const Icon(AppIcons.examSeat, color: AppColors.gold, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text(
                '${_parsedRows.length} room allocations · $distinctSections sections · $distinctDates exam date(s)',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)))),
          ])),
          const SizedBox(height: 12),
          AfosButton(label: 'Confirm & Upload', loading: _uploading, onTap: _upload),
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: AppColors.red)),
        ],
      ])),
    );
  }
}
