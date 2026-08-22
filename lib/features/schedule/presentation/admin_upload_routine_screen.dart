import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show compute;
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/motion.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/animations/page_transitions.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/supernova_loader.dart';
import '../../auth/data/repositories/academic_repository.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../transport/data/models/transport_schedule.dart';
import '../../transport/data/transport_excel_parser.dart';
import '../../transport/data/transport_import_service.dart';
import '../../transport/data/transport_pdf_parser.dart';
import '../../transport/presentation/transport_import_preview_screen.dart';
import '../../uploads/data/upload_batch.dart';

import '../../../core/layout/nav_insets.dart';
/// PDFs are parsed to text lines right here on-device (Syncfusion's PDF
/// text extractor), not on the server — a multi-page routine PDF has
/// thousands of positioned text runs, which reliably blew past the edge
/// function's CPU/time budget and crashed it (HTTP 546). The phone has
/// no such limit, so only the already-extracted, tiny text payload goes
/// to the server for the lightweight regex parsing.
///
/// Top-level (not a State method) and run via `compute()` — this is the
/// single heaviest synchronous parse in the app, invoked directly inside an
/// admin's upload button tap with nothing else keeping the UI thread busy
/// meanwhile, so without an isolate the button visibly freezes for the
/// duration of the extraction.
List<String> _extractPdfLines(Uint8List bytes) {
  final doc = PdfDocument(inputBytes: bytes);
  try {
    final textLines = PdfTextExtractor(doc).extractTextLines();
    return textLines.map((l) => l.text.trim()).where((t) => t.isNotEmpty).toList();
  } finally {
    doc.dispose();
  }
}

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
  /// True when [result] describes a partial success — the routine saved, but
  /// something after it did not.
  ///
  /// This exists because the severity used to live in the STRING, as a `⚠`
  /// glyph, while the result line was painted unconditionally green. So "Saved,
  /// but no users were notified" rendered in the same success colour as a clean
  /// import, and the only thing distinguishing them was an emoji that screen
  /// readers announce as "warning sign" and that cannot take a theme colour.
  /// The severity is a property of the outcome, not a character in the text.
  bool resultWarning = false;
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
    String? batchId;
    try {
      final jwt = SupabaseConfig.jwt;
      const url = '${SupabaseConfig.url}/functions/v1/parse-routine';
      final isPdf = p.file.extension?.toLowerCase() == 'pdf';
      final headers = {'Authorization': 'Bearer $jwt', 'apikey': SupabaseConfig.publishableKey};

      // Opened before the call so the edge function can stamp every row it
      // writes. The insert happens server-side here, which is exactly why the
      // id has to travel with the request rather than be applied afterwards.
      batchId = await UploadBatchService.open(
        kind: p.mode == 'exam_routine' ? 'exam_routine' : 'class_routine',
        sourceFile: p.file.name,
        department: _selectedDept?.code,
      );

      final bytes = await _fileBytes(p.file);
      final Response res;
      if (isPdf) {
        final lines = await compute(_extractPdfLines, bytes);
        if (lines.isEmpty) {
          throw 'Could not read any text from this PDF — it may be a scanned image rather than a text PDF.';
        }
        res = await Dio().post(url,
            data: {'type': p.mode, 'lines': lines, 'upload_batch_id': batchId,
                   if (_selectedDept != null) 'department': _selectedDept!.code},
            options: Options(headers: {...headers, 'Content-Type': 'application/json'}));
      } else {
        final formData = FormData.fromMap({
          'type': p.mode,
          'upload_batch_id': batchId,
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
      await UploadBatchService.finalize(batchId, summary: {
        'inserted': res.data['slotsInserted'] ?? 0,
        'removed': removed,
        'parsed': res.data['totalParsed'] ?? 0,
        'mode': p.mode,
      });
      setState(() {
        p.result = '${res.data["slotsInserted"]} $noun loaded.$removedNote';
        p.resultWarning = false;
      });
      AppHaptics.success();
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
      // TransportPdfParser/TransportExcelParser.parse are both static —
      // torn off as a function reference for compute() the same way the
      // class-routine PDF extraction above is, keeping the upload button
      // responsive during the parse instead of freezing on the UI thread.
      final parsed = ext == 'pdf'
          ? await compute(TransportPdfParser.parse, bytes)
          : await compute(TransportExcelParser.parse, bytes);
      if (parsed.routes.isEmpty) {
        throw 'No transport routes could be read from "${p.file.name}". '
            'If this is a scanned/image PDF, export the sheet as .xlsx instead.';
      }
      final validation = TransportImportService.validate(parsed);
      if (!mounted) return;
      // Preview pops null on cancel (back/swipe/Cancel), or an ImportReviewResult
      // carrying the (possibly admin-edited) routes + optional broadcast message
      // on Confirm & Import. Editing happens IN the preview screen, so `result`
      // — not the original `parsed` — is what must actually get written; using
      // the stale `parsed` here would silently discard every fix the admin made.
      final result = await Navigator.of(context).push<ImportReviewResult?>(appPageRoute(
          TransportImportPreviewScreen(parsed: parsed, validation: validation)));
      if (result == null) {
        setState(() { p.uploading = false; p.result = null; });
        return;
      }
      final edited = ParsedTransportSchedule(
          semester: parsed.semester, campus: parsed.campus, routes: result.routes);
      await TransportImportService.write(edited);
      // Notify the whole university that the schedule changed. This is what was
      // missing entirely: the upload wrote the routes but never told anyone.
      // Best-effort (broadcast swallows its own errors) so a notification
      // failure can't undo a successful import; super-admin uploader is allowed
      // the broadcastAll path server-side.
      final custom = result.message.trim();
      final notifyResult = await NotificationService.broadcast(
        // No role/department filter => the service sends broadcastAll (every
        // user), which is correct for a university-wide transport change.
        title: 'Transport schedule updated',
        // The admin's own notice when they wrote one at review time, else the
        // standard line.
        message: custom.isNotEmpty
            ? custom
            : 'The ${parsed.semester} bus schedule has been updated — tap to see your route.',
        deepLink: '/transport',
        category: 'transport',
      );
      // Surface exactly what the notify step did, so a silent failure is
      // visible instead of the old "routes imported" with no delivery signal.
      // inAppInserted is the count of user_notifications rows actually created.
      final notify = _notifyOutcome(notifyResult);
      setState(() {
        p.result = '${edited.routes.length} routes imported for ${parsed.semester}'
            '${result.warningCount > 0 ? ' (${result.warningCount} warnings)' : ''}.${notify.note}';
        p.resultWarning = notify.warned || result.warningCount > 0;
      });
      if (notify.warned) {
        AppHaptics.warning();
      } else {
        AppHaptics.success();
      }
    } catch (e) {
      setState(() => p.error = friendlyError(e));
    } finally {
      if (mounted) setState(() => p.uploading = false);
    }
  }

  /// Turns the broadcast result into a short human note appended to the upload
  /// result, so the notify step's real outcome is visible instead of silent.
  /// `inAppInserted` is the number of user_notifications rows actually created —
  /// the definitive "did a notification get created in the DB" signal.
  ({String note, bool warned}) _notifyOutcome(Map<String, dynamic>? r) {
    if (r == null) {
      return (note: ' Saved, but the update notification could not be sent (check connection/permissions).', warned: true);
    }
    if (r['insertError'] != null) {
      return (note: ' Saved, but notifying users failed: ${r['insertError']}.', warned: true);
    }
    final inApp = (r['inAppInserted'] as num?)?.toInt() ?? 0;
    if (inApp == 0) {
      return (note: ' Saved, but no users were notified (no recipients matched).', warned: true);
    }
    final pushNote = r['pushError'] != null ? ' (in-app only — push unavailable)' : '';
    return (note: ' $inApp user${inApp == 1 ? '' : 's'} notified$pushNote.', warned: r['pushError'] != null);
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
      // The app's standard floating glass pill — this screen was the only one
      // inside the shell still on a raw Material AppBar, which also meant it
      // had no hamburger and no notification bell, leaving the slide menu
      // unreachable from here. Title matches the slide-menu entry exactly.
      appBar: const AfosAppBar(title: 'Upload Routine/Transport'),
      body: SingleChildScrollView(
        // Bottom inset so the "Upload All" button clears the floating bottom
        // nav bar (this screen is inside the shell). Horizontal padding is 16
        // to match every other feature screen.
        padding: NavInsets.content(context, h: 16, top: 0, bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const FeatureHeader(
            title: 'Upload Routines & Transport',
            subtitle: 'Select one or more PDF/Excel files at once — a class routine, exam routine, and '
                'transport sheet can all go up together. Each file gets its own type (guessed from the '
                'filename, override if wrong) and is parsed independently.',
            icon: Icons.upload_file_rounded,
            accent: AppColors.holoBlue,
            margin: EdgeInsetsDirectional.fromSTEB(0, 16, 0, 12),
          ).animate()
              .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
              .slideY(begin: -0.06, curve: AppMotion.standard),
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
                  border: OutlineInputBorder(borderRadius: AppDepth.radius(1),
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
              padding: EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10 + NavInsets.of(context)),
              decoration: BoxDecoration(color: AppColors.glassFill(context), borderRadius: AppDepth.radius(1),
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
                  color: AppColors.glassFill(context), borderRadius: AppDepth.radius(2),
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
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(1),
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
              border: OutlineInputBorder(borderRadius: AppDepth.radius(1), borderSide: BorderSide(color: AppColors.borderOf(context)))),
          dropdownColor: AppColors.surfaceOf(context),
          style: TextStyle(color: textPrimary, fontSize: 13),
          items: _modes.map((m) => DropdownMenuItem(value: m, child: Text(_modeLabel(m)))).toList(),
          onChanged: (v) { if (v != null) onModeChanged(v); },
        )),
        if (pending.uploading) Padding(padding: const EdgeInsets.only(top: 10),
            child: SupernovaBusy(label: isPdf ? 'Reading the PDF…' : 'Reading the sheet…')),
        // Amber when the import landed but something after it did not. This
        // line was unconditionally green, so "Saved, but no users were
        // notified" looked exactly like a clean run.
        if (pending.result != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(pending.resultWarning ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                  size: 14, color: pending.resultWarning ? AppColors.amber : AppColors.green),
              const SizedBox(width: 6),
              Expanded(child: Text(pending.result!,
                  style: TextStyle(
                      color: pending.resultWarning ? AppColors.amber : AppColors.green,
                      fontSize: 12, fontWeight: FontWeight.w600))),
            ])),
        if (pending.error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(pending.error!, style: const TextStyle(color: AppColors.red, fontSize: 12))),
      ]),
    );
  }
}
