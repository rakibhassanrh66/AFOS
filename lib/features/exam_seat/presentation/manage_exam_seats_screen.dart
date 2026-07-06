import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/exam_room_pdf_parser.dart';

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
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'], allowMultiple: true);
    if (res != null) setState(() { _files = res.files; _parsedRows = []; _error = null; });
  }

  Future<void> _parseAll() async {
    setState(() { _parsing = true; _error = null; });
    try {
      final allRows = <ExamRoomAllocationRow>[];
      for (final f in _files) {
        if (f.path == null) continue;
        final bytes = File(f.path!).readAsBytesSync();
        allRows.addAll(ExamRoomPdfParser.parse(bytes));
      }
      if (allRows.isEmpty) {
        throw "No seat allocation rows found — these may be scanned images rather than text PDFs, or don't match the expected table layout.";
      }
      if (mounted) setState(() => _parsedRows = allRows);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    if (mounted) setState(() => _parsing = false);
  }

  Future<void> _upload() async {
    setState(() { _uploading = true; _error = null; });
    try {
      // Replace, not append — re-uploading the same exam date(s) (e.g. a
      // corrected PDF) shouldn't leave stale duplicate rows behind.
      final dates = _parsedRows.map((r) => r.examDate.toIso8601String().split('T').first).toSet();
      for (final d in dates) {
        await SupabaseConfig.client.from('exam_room_allocations').delete().eq('exam_date', d);
      }
      await SupabaseConfig.client.from('exam_room_allocations').insert(
          _parsedRows.map((r) => r.toRow()).toList());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${_parsedRows.length} room allocations uploaded across ${dates.length} exam date(s) ✓'),
            backgroundColor: AppColors.green));
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
      appBar: AfosAppBar(title: 'Exam Seat Plan Upload'),
      body: ListView(padding: const EdgeInsets.all(16), children: [
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
            Icon(AppIcons.examSeat, color: AppColors.gold, size: 18),
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
      ]),
    );
  }
}
