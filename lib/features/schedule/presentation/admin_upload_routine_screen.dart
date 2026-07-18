import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/animations/page_transitions.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/supernova_loader.dart';
import '../../auth/data/repositories/academic_repository.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../transport/data/transport_excel_parser.dart';
import '../../transport/data/transport_import_service.dart';
import '../../transport/data/transport_pdf_parser.dart';
import '../../transport/presentation/transport_import_preview_screen.dart';

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
  final _academicRepo = AcademicRepository();
  List<DepartmentOption> _departments = [];
  DepartmentOption? _selectedDept;
  bool _loadingDepts = true;
  String? _myRole;
  String? _myDeptName;

  bool get _isSuperAdmin => _myRole == 'super_admin';

  @override
  void initState() {
    super.initState();
    _loadDepartments();
  }

  // Every upload used to be silently tagged "CSE" regardless of who
  // uploaded it or what the file actually contained. Only super_admin can
  // freely choose which department an upload is tagged as (the free-choice
  // picker below is super_admin-only, matching the server-side role check
  // in parse-routine) — every other authorized uploader (admin/dept_admin/
  // teacher) is locked to their own profile's department, shown read-only,
  // so one department's staff can never mislabel another's routine even by
  // accident.
  Future<void> _loadDepartments() async {
    try {
      final uid = SupabaseConfig.uid;
      if (uid == null) { if (mounted) setState(() => _loadingDepts = false); return; }
      final p = await SupabaseConfig.client.from('profiles').select('role, department').eq('id', uid).maybeSingle();
      final role = p?['role'] as String?;
      final code = p?['department'] as String?;

      if (role == 'super_admin') {
        final depts = await _academicRepo.fetchDepartments();
        final own = code != null ? depts.where((d) => d.code == code).firstOrNull : null;
        if (mounted) setState(() { _myRole = role; _departments = depts; _selectedDept = own; _loadingDepts = false; });
      } else {
        if (mounted) setState(() { _myRole = role; _myDeptName = code; _loadingDepts = false; });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDepts = false);
    }
  }

  Future<void> _pickFiles() async {
    // withData: true -- on web, PlatformFile.path is always unavailable
    // (merely accessing the getter throws); .bytes is the only cross-platform
    // way to read what was picked, and it's only populated if requested here.
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf', 'xlsx', 'xls'], allowMultiple: true, withData: true);
    if (res == null) return;
    setState(() => _pending.addAll(res.files.map((f) => _PendingUpload(f))));
  }

  void _removeFile(_PendingUpload p) => setState(() => _pending.remove(p));

  /// Resolves a picked file's bytes cross-platform: prefers the in-memory
  /// .bytes (always what's available on web, and present on every platform
  /// now that _pickFiles asks for it), falling back to reading .path only
  /// for the rare case bytes weren't populated on a native platform.
  Future<Uint8List> _fileBytes(PlatformFile file) async {
    if (file.bytes != null) return file.bytes!;
    if (file.path != null) return File(file.path!).readAsBytes();
    throw 'Could not read "${file.name}" — no file data available.';
  }

  /// PDFs are parsed to text lines right here on-device (Syncfusion's PDF
  /// text extractor), not on the server — a multi-page routine PDF has
  /// thousands of positioned text runs, which reliably blew past the edge
  /// function's CPU/time budget and crashed it (HTTP 546). The phone has
  /// no such limit, so only the already-extracted, tiny text payload goes
  /// to the server for the lightweight regex parsing.
  List<String> _extractPdfLines(Uint8List bytes) {
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final textLines = PdfTextExtractor(doc).extractTextLines();
      return textLines.map((l) => l.text.trim()).where((t) => t.isNotEmpty).toList();
    } finally {
      doc.dispose();
    }
  }

  Future<void> _uploadOne(_PendingUpload p) async {
    // Transport is parsed CLIENT-SIDE (Excel primary / PDF fallback), validated,
    // and previewed for admin review before anything is written — see
    // _importTransport. It does not go through the edge function.
    if (p.mode == 'transport') {
      await _importTransport(p);
      return;
    }
    // Transport is university-wide (no department column involved at all).
    // Only super_admin picks explicitly here — every other role has no
    // dropdown to fill in at all (locked server-side to their own profile
    // department instead), so this requirement only applies to super_admin.
    if (_isSuperAdmin && p.mode != 'transport' && _selectedDept == null) {
      setState(() => p.error = 'Select a department above before uploading this file.');
      return;
    }
    setState(() { p.uploading = true; p.result = null; p.error = null; });
    try {
      final jwt = SupabaseConfig.jwt;
      const url = '${SupabaseConfig.url}/functions/v1/parse-routine';
      final isPdf = p.file.extension?.toLowerCase() == 'pdf';
      final headers = {'Authorization': 'Bearer $jwt', 'apikey': SupabaseConfig.publishableKey};

      final bytes = await _fileBytes(p.file);
      final Response res;
      if (isPdf) {
        final lines = _extractPdfLines(bytes);
        if (lines.isEmpty) {
          throw 'Could not read any text from this PDF — it may be a scanned image rather than a text PDF.';
        }
        res = await Dio().post(url,
            data: {'type': p.mode, 'lines': lines, if (_selectedDept != null) 'department': _selectedDept!.code},
            options: Options(headers: {...headers, 'Content-Type': 'application/json'}));
      } else {
        final formData = FormData.fromMap({
          'type': p.mode,
          if (_selectedDept != null) 'department': _selectedDept!.code,
          'file': MultipartFile.fromBytes(bytes, filename: p.file.name),
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

  /// Client-side transport import: parse (Excel primary / PDF fallback),
  /// validate, let the admin review the parsed result + QA flags, and only
  /// write on explicit confirmation. Nothing is written silently.
  Future<void> _importTransport(_PendingUpload p) async {
    setState(() { p.uploading = true; p.result = null; p.error = null; });
    try {
      final bytes = await _fileBytes(p.file);
      final ext = p.file.extension?.toLowerCase();
      final parsed = ext == 'pdf'
          ? TransportPdfParser.parse(bytes)
          : TransportExcelParser.parse(bytes);
      if (parsed.routes.isEmpty) {
        throw 'No transport routes could be read from "${p.file.name}". '
            'If this is a scanned/image PDF, export the sheet as .xlsx instead.';
      }
      final validation = TransportImportService.validate(parsed);
      if (!mounted) return;
      final confirmed = await Navigator.of(context).push<bool>(appPageRoute(
          TransportImportPreviewScreen(parsed: parsed, validation: validation)));
      if (confirmed != true) {
        setState(() { p.uploading = false; p.result = null; });
        return;
      }
      await TransportImportService.write(parsed);
      // Notify the whole university that the schedule changed. This is what was
      // missing entirely: the upload wrote the routes but never told anyone.
      // Best-effort (broadcast swallows its own errors) so a notification
      // failure can't undo a successful import; super-admin uploader is allowed
      // the broadcastAll path server-side.
      await NotificationService.broadcast(
        // No role/department filter => the service sends broadcastAll (every
        // user), which is correct for a university-wide transport change.
        title: 'Transport schedule updated',
        message: 'The ${parsed.semester} bus schedule has been updated — tap to see your route.',
        deepLink: '/transport',
        category: 'transport',
      );
      setState(() => p.result =
          '✅ ${parsed.routes.length} routes imported for ${parsed.semester}'
          '${validation.warningCount > 0 ? ' (${validation.warningCount} warnings)' : ''}.');
    } catch (e) {
      setState(() => p.error = friendlyError(e));
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
    // Department scopes class/exam/legacy routine uploads only; transport is
    // university-wide. Hide the whole department section unless at least one
    // queued file is a non-transport type.
    final showDept = _pending.any((p) => p.mode != 'transport');
    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: AppBar(
        title: Text('Upload Schedule / Transport', style: TextStyle(color: textPrimary)),
        backgroundColor: AppColors.surfaceOf(context),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      body: SingleChildScrollView(
        // Bottom inset so the "Upload All" button clears the floating bottom
        // nav bar (this screen is inside the shell). MediaQuery.padding.bottom
        // already carries the shell's reserved bar space (app_shell.dart).
        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + MediaQuery.of(context).padding.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          RepaintBoundary(
            child: GlassCard(
              borderRadius: 20,
              glowColor: AppColors.holoBlue,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.upload_file_rounded, color: AppColors.holoBlue, size: 48)
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
          if (showDept) ...[
            const SizedBox(height: 20),
            if (_loadingDepts)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator())
          else if (_isSuperAdmin) ...[
            Text('Department', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
            const SizedBox(height: 4),
            Text('Applies to class/exam routine and legacy schedule uploads — transport is university-wide. '
                'As super admin you can upload on behalf of any department.',
                style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
            const SizedBox(height: 8),
            DropdownButtonFormField<DepartmentOption>(
              initialValue: _selectedDept,
              isExpanded: true,
              decoration: InputDecoration(
                  hintText: 'Select department', filled: true, fillColor: AppColors.glassFill(context),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.borderOf(context)))),
              dropdownColor: AppColors.surfaceOf(context),
              style: TextStyle(color: textPrimary),
              items: _departments.map((d) => DropdownMenuItem(value: d,
                  child: Text(d.name, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _selectedDept = v),
            ),
          ] else
            // Not super_admin — no picker at all, just a transparent readout
            // of where this upload is actually going (server-side locked to
            // this account's own profile department regardless of anything
            // the client could send).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: AppColors.glassFill(context), borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderOf(context))),
              child: Row(children: [
                Icon(Icons.lock_outline_rounded, size: 16, color: textSecondary),
                const SizedBox(width: 8),
                Expanded(child: Text(
                    'Uploading for your department: ${_myDeptName ?? "not set — update your profile first"}',
                    style: AppTextStyles.bodyMedium.copyWith(color: textPrimary))),
              ]),
            ),
          ],
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
