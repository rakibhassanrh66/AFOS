import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../exam_seat/data/exam_routine_pdf_parser.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/upload_batch.dart';

/// Imports an official exam routine PDF.
///
/// WHY THIS SCREEN EXISTS. `ExamRoutinePdfParser` was written against the real
/// Summer 2026 document and then wired to nothing: `/admin/upload` offers an
/// "Exam Routine" mode, but that path posts extracted text LINES to the
/// `parse-routine` edge function — an older, line-based reader that never sees
/// a coordinate. So the only routine in the database was put there by hand,
/// and an exam controller had no way to load one at all.
///
/// The parser is coordinate-based because this document cannot be read any
/// other way: its slot columns, its centred date labels and its multi-course
/// cells are all geometry. Everything it recovers is shown here BEFORE
/// anything is written, because the failure this feature has actually suffered
/// is silent loss — eight of thirty-eight exams, with no warning.
class ExamRoutineUploadScreen extends StatefulWidget {
  const ExamRoutineUploadScreen({super.key});
  @override
  State<ExamRoutineUploadScreen> createState() => _ExamRoutineUploadState();
}

class _ExamRoutineUploadState extends State<ExamRoutineUploadScreen> {
  PlatformFile? _file;
  ExamRoutineParseResult? _parsed;
  bool _parsing = false, _uploading = false, _publish = false;
  String? _error, _result;

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (res == null || res.files.isEmpty) return;
    setState(() {
      _file = res.files.first;
      _parsed = null;
      _error = null;
      _result = null;
    });
  }

  Future<void> _parse() async {
    final f = _file;
    if (f == null) return;
    setState(() {
      _parsing = true;
      _error = null;
    });
    try {
      final bytes =
          f.bytes ?? (f.path != null ? File(f.path!).readAsBytesSync() : null);
      if (bytes == null) throw 'Could not read the selected file.';
      // Same reason the seat-plan screen uses compute(): word extraction plus
      // per-page geometry across a dozen pages is long enough to drop frames.
      final res = await compute(ExamRoutinePdfParser.parse, bytes);
      if (res.entries.isEmpty) {
        throw 'No exam rows were found. This may be a scanned image rather '
            'than a text PDF, or a layout this parser does not know.';
      }
      if (mounted) setState(() => _parsed = res);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _parsing = false);
  }

  /// "09:00 am" -> "09:00:00". Postgres would accept the 12-hour form, but
  /// normalising here means the value stored is the value read back, whatever
  /// the connection's DateStyle happens to be.
  static String? _to24(String? v) {
    if (v == null) return null;
    final m = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap])m?$', caseSensitive: false)
        .firstMatch(v.trim());
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final min = m.group(2)!;
    final pm = m.group(3)!.toLowerCase() == 'p';
    if (pm && h != 12) h += 12;
    if (!pm && h == 12) h = 0;
    return '${h.toString().padLeft(2, '0')}:$min:00';
  }

  Future<void> _upload() async {
    final parsed = _parsed;
    if (parsed == null) return;
    final h = parsed.header;
    if (h.examType == null || h.season == null || h.year == null) {
      setState(() => _error =
          'The document title did not say which examination this is '
          '(type, season and year). Nothing was written.');
      return;
    }
    final dept = h.department;
    if (dept == null || dept.isEmpty) {
      setState(() => _error =
          'No department could be read from the document. Nothing was written.');
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
      _result = null;
    });
    String? batchId;
    try {
      final client = SupabaseConfig.client;

      // Opened first, so every row can carry it.
      batchId = await UploadBatchService.open(
        kind: 'exam_routine',
        sourceFile: _file?.name,
        department: dept,
      );

      // One term per (type, season, year, department). Reused when it already
      // exists so a corrected routine updates the term students are already
      // looking at rather than creating a second, competing one.
      final existing = await client
          .from('exam_terms')
          .select('id')
          .eq('exam_type', h.examType!)
          .eq('season', h.season!)
          .eq('year', h.year!)
          .eq('department', dept)
          .maybeSingle();

      final termRow = {
        'exam_type': h.examType,
        'season': h.season,
        'year': h.year,
        'department': dept,
        'starts_on': parsed.startsOn?.toIso8601String().split('T').first,
        'ends_on': parsed.endsOn?.toIso8601String().split('T').first,
        'source_file': _file?.name,
        'uploaded_by': SupabaseConfig.uid,
        'published': _publish,
      };

      final String termId;
      if (existing == null) {
        final ins = await client
            .from('exam_terms')
            .insert(termRow)
            .select('id')
            .single();
        termId = '${ins['id']}';
      } else {
        termId = '${existing['id']}';
        await client.from('exam_terms').update(termRow).eq('id', termId);
      }

      // Replace, not append: re-uploading a corrected routine must not leave
      // the superseded rows beside the new ones. Scoped to this term only.
      await client.from('exams').delete().eq('term_id', termId);

      await client.from('exams').insert([
        for (final e in parsed.entries)
          {
            'subject': e.courseTitle,
            'subject_code': e.courseCode,
            'department': dept,
            'exam_date': e.date.toIso8601String().split('T').first,
            'start_time': _to24(e.slotStart),
            'end_time': _to24(e.slotEnd),
            'exam_type': h.examType,
            'batch': e.batch,
            'slot_label': e.slotLabel,
            'term_id': termId,
            'upload_batch_id': batchId,
          }
      ]);

      final byDate = <String, int>{};
      for (final e in parsed.entries) {
        final d = e.date.toIso8601String().split('T').first;
        byDate[d] = (byDate[d] ?? 0) + 1;
      }
      final batch = await UploadBatchService.finalize(batchId, summary: {
        'term': '${h.examType} ${h.season} ${h.year} $dept',
        'dates': byDate,
        'published': _publish,
        'warnings': parsed.warnings.length,
      });

      if (mounted) {
        setState(() {
          _result = '${batch.rowCount} exams imported across ${byDate.length} '
              'date${byDate.length == 1 ? '' : 's'}.'
              '${_publish ? '' : ' Not published yet — students see nothing until you publish it.'}';
          _parsed = null;
          _file = null;
        });
      }
    } catch (e) {
      // The batch stays open and shows in the history as 'pending', which is
      // the honest record of an import that started and did not finish.
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _uploading = false);
  }

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondaryOf(context);
    final textPrimary = AppColors.textPrimaryOf(context);
    final parsed = _parsed;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Exam Routine Upload'),
      body: AdaptiveContentWidth(
        maxWidth: 760,
        child: ListView(
          padding: EdgeInsetsDirectional.fromSTEB(
              16, 16, 16, 16 + NavInsets.of(context)),
          children: [
            const FeatureHeader(
              title: 'Exam Routine Upload',
              subtitle: 'Publish which exam sits when, from the official PDF',
              icon: AppIcons.examSeat,
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.blue, AppColors.holoTeal]),
              margin: EdgeInsets.only(bottom: 16),
            ),
            Text(
                'Select the examination routine PDF. Everything it reads is '
                'shown for review before anything is written.',
                style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
            const SizedBox(height: 16),
            AfosButton(
                label: 'Pick Routine PDF',
                icon: Icons.upload_file_rounded,
                onTap: _pick),
            if (_file != null) ...[
              const SizedBox(height: 12),
              SurfaceCard(
                  child: Text(_file!.name,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: textPrimary))),
              const SizedBox(height: 12),
              AfosButton(label: 'Read It', loading: _parsing, onTap: _parse),
            ],
            if (parsed != null) ...[
              const SizedBox(height: 16),
              _Preview(parsed: parsed),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _publish,
                onChanged: (v) => setState(() => _publish = v),
                title: Text('Publish to students now',
                    style:
                        AppTextStyles.bodyMedium.copyWith(color: textPrimary)),
                subtitle: Text(
                    'Off means it is imported but invisible until you publish '
                    'it — the usual order is import, check, then publish.',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: textSecondary)),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              AfosButton(
                  label: 'Confirm & Import',
                  loading: _uploading,
                  onTap: _upload),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              SurfaceCard(
                  child: Row(children: [
                const Icon(Icons.check_circle_outline_rounded,
                    color: AppColors.green, size: 18),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_result!,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: textPrimary))),
              ])),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: AppColors.red)),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the parser recovered, per date, before anything is written.
///
/// Shown in full rather than as a count because the way this document fails is
/// by losing a day quietly — a total of "30 entries" looks perfectly healthy
/// when it should read 38.
class _Preview extends StatelessWidget {
  final ExamRoutineParseResult parsed;
  const _Preview({required this.parsed});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final h = parsed.header;

    final byDate = <DateTime, List<String>>{};
    for (final e in parsed.entries) {
      (byDate[e.date] ??= []).add('${e.courseCode}/${e.batch}');
    }
    final dates = byDate.keys.toList()..sort();

    return SurfaceCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            [
              if (h.examType != null) h.examType!.toUpperCase(),
              if (h.season != null) h.season!,
              if (h.year != null) '${h.year}',
              if (h.department != null) h.department!,
            ].join(' · '),
            style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
        const SizedBox(height: 4),
        Text(
            '${parsed.entries.length} exams · ${dates.length} dates · '
            '${parsed.startsOn?.day}/${parsed.startsOn?.month} to '
            '${parsed.endsOn?.day}/${parsed.endsOn?.month}',
            style: AppTextStyles.numericSmall.copyWith(color: textSecondary)),
        const SizedBox(height: 12),
        for (final d in dates)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: 54,
                  child: Text('${d.day}/${d.month}',
                      style: AppTextStyles.numericSmall
                          .copyWith(color: textPrimary))),
              Expanded(
                  child: Text(byDate[d]!.join('  '),
                      style: AppTextStyles.labelSmall
                          .copyWith(color: textSecondary))),
              Text('${byDate[d]!.length}',
                  style: AppTextStyles.numericSmall
                      .copyWith(color: textSecondary)),
            ]),
          ),
        if (parsed.warnings.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('${parsed.warnings.length} warning'
              '${parsed.warnings.length == 1 ? '' : 's'}',
              style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.amber, fontWeight: FontWeight.w700)),
          for (final w in parsed.warnings.take(6))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(w,
                  style:
                      AppTextStyles.labelSmall.copyWith(color: textSecondary)),
            ),
        ],
      ]),
    );
  }
}
