import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/supernova_loader.dart';

const _modes = ['class_routine', 'exam_routine', 'transport', 'schedule'];
String _modeLabel(String m) => switch (m) {
      'transport' => 'Transport Routes',
      'exam_routine' => 'Exam Routine',
      'schedule' => 'Legacy Schedule',
      _ => 'Class Routine',
    };

/// Guesses a starting type from the filename so the admin usually doesn't
/// need to touch the per-file dropdown at all — still fully overridable,
/// since a real filename won't always be this predictable.
String _guessMode(String filename) {
  final n = filename.toLowerCase();
  if (n.contains('exam')) return 'exam_routine';
  if (n.contains('transport') || n.contains('bus')) return 'transport';
  return 'class_routine';
}

class _PendingUpload {
  final PlatformFile file;
  String mode;
  String? result, error;
  bool uploading = false;
  _PendingUpload(this.file) : mode = _guessMode(file.name);
}

class AdminUploadRoutineScreen extends StatefulWidget {
  const AdminUploadRoutineScreen({super.key});
  @override State<AdminUploadRoutineScreen> createState() => _AdminUploadState();
}

class _AdminUploadState extends State<AdminUploadRoutineScreen> {
  final List<_PendingUpload> _pending = [];
  bool _uploadingAll = false;

  Future<void> _pickFiles() async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf', 'xlsx', 'xls'], allowMultiple: true);
    if (res == null) return;
    setState(() => _pending.addAll(res.files.map((f) => _PendingUpload(f))));
  }

  void _removeFile(_PendingUpload p) => setState(() => _pending.remove(p));

  /// PDFs are parsed to text lines right here on-device (Syncfusion's PDF
  /// text extractor), not on the server — a multi-page routine PDF has
  /// thousands of positioned text runs, which reliably blew past the edge
  /// function's CPU/time budget and crashed it (HTTP 546). The phone has
  /// no such limit, so only the already-extracted, tiny text payload goes
  /// to the server for the lightweight regex parsing.
  List<String> _extractPdfLines(String path) {
    final bytes = File(path).readAsBytesSync();
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final textLines = PdfTextExtractor(doc).extractTextLines();
      return textLines.map((l) => l.text.trim()).where((t) => t.isNotEmpty).toList();
    } finally {
      doc.dispose();
    }
  }

  Future<void> _uploadOne(_PendingUpload p) async {
    setState(() { p.uploading = true; p.result = null; p.error = null; });
    try {
      final jwt = SupabaseConfig.jwt;
      final url = '${SupabaseConfig.url}/functions/v1/parse-routine';
      final isPdf = p.file.extension?.toLowerCase() == 'pdf';
      final headers = {'Authorization': 'Bearer $jwt', 'apikey': SupabaseConfig.publishableKey};

      final Response res;
      if (isPdf) {
        final lines = _extractPdfLines(p.file.path!);
        if (lines.isEmpty) {
          throw 'Could not read any text from this PDF — it may be a scanned image rather than a text PDF.';
        }
        res = await Dio().post(url,
            data: {'type': p.mode, 'lines': lines},
            options: Options(headers: {...headers, 'Content-Type': 'application/json'}));
      } else {
        final formData = FormData.fromMap({
          'type': p.mode,
          'file': await MultipartFile.fromFile(p.file.path!, filename: p.file.name),
        });
        res = await Dio().post(url, data: formData, options: Options(headers: headers));
      }

      final noun = switch (p.mode) {
        'transport' => 'transport routes',
        'exam_routine' => 'exam entries',
        _ => 'class slots',
      };
      final removed = res.data["slotsRemoved"] ?? 0;
      final removedNote = removed > 0 ? ' $removed obsolete $noun cleared.' : '';
      setState(() => p.result = '✅ ${res.data["slotsInserted"]} $noun loaded.$removedNote');
    } catch (e) {
      final data = e is DioException ? e.response?.data : null;
      setState(() => p.error = data is Map && data['error'] != null ? data['error'].toString() : friendlyError(e));
    } finally {
      if (mounted) setState(() => p.uploading = false);
    }
  }

  Future<void> _uploadAll() async {
    setState(() => _uploadingAll = true);
    // Sequential, not parallel — each PDF extraction is CPU-heavy on-device
    // and the edge function itself only budgets for one parse at a time.
    for (final p in _pending) {
      await _uploadOne(p);
    }
    if (mounted) setState(() => _uploadingAll = false);
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: AppBar(
        title: Text('Upload Schedule / Transport', style: TextStyle(color: textPrimary)),
        backgroundColor: AppColors.surfaceOf(context),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RepaintBoundary(
            child: GlassCard(
              borderRadius: 20,
              glowColor: AppColors.holoBlue,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.upload_file_rounded, color: AppColors.holoBlue, size: 48)
                      .animate().scale(curve: Curves.easeOutCubic),
                  const SizedBox(height: 16),
                  Text('Upload Routines & Transport', style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
                  const SizedBox(height: 8),
                  Text('Select one or more PDF/Excel files at once — a class routine, exam routine, and transport '
                      'sheet can all be uploaded together. Each file gets its own type (guessed from the filename, '
                      'override if wrong) and is parsed independently.',
                      style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _pickFiles,
            child: Container(
              width: double.infinity, height: 100,
              decoration: BoxDecoration(
                  color: AppColors.glassFill(context), borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.glassBorder(context))),
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_circle_outline, color: textSecondary, size: 32),
                const SizedBox(height: 8),
                Text('Tap to select PDF or Excel files (multiple allowed)',
                    style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
              ])),
            ),
          ),
          const SizedBox(height: 16),
          ..._pending.map((p) => _PendingCard(
              pending: p,
              onModeChanged: (m) => setState(() => p.mode = m),
              onRemove: () => _removeFile(p),
              onUploadOne: () => _uploadOne(p))),
          if (_pending.isNotEmpty) ...[
            const SizedBox(height: 8),
            AfosButton(label: 'Upload All (${_pending.length})', loading: _uploadingAll, onTap: _uploadAll,
                color: AppColors.holoBlue),
          ],
        ]),
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final _PendingUpload pending;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onRemove, onUploadOne;
  const _PendingCard({required this.pending, required this.onModeChanged, required this.onRemove, required this.onUploadOne});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final isPdf = pending.file.extension?.toLowerCase() == 'pdf';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isPdf ? Icons.picture_as_pdf : Icons.table_chart_rounded,
              color: isPdf ? AppColors.red : AppColors.green, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pending.file.name, style: AppTextStyles.bodyMedium.copyWith(color: textPrimary),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text('${(pending.file.size / 1024).toStringAsFixed(1)} KB', style: TextStyle(color: textSecondary, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.close_rounded, size: 18), onPressed: onRemove),
        ]),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: DropdownButtonFormField<String>(
          initialValue: pending.mode,
          isExpanded: true,
          decoration: InputDecoration(
              isDense: true, filled: true, fillColor: AppColors.glassFill(context),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.borderOf(context)))),
          dropdownColor: AppColors.surfaceOf(context),
          style: TextStyle(color: textPrimary, fontSize: 13),
          items: _modes.map((m) => DropdownMenuItem(value: m, child: Text(_modeLabel(m)))).toList(),
          onChanged: (v) { if (v != null) onModeChanged(v); },
        )),
        if (pending.uploading) Padding(padding: const EdgeInsets.only(top: 10),
            child: SupernovaBusy(label: isPdf ? 'Reading the PDF…' : 'Reading the sheet…')),
        if (pending.result != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(pending.result!, style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w600))),
        if (pending.error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(pending.error!, style: const TextStyle(color: AppColors.red, fontSize: 12))),
      ]),
    );
  }
}
