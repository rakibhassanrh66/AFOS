import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/haptics/app_haptics.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/assignments_repository.dart';

/// What a class handed in, and where the teacher marks it.
///
/// `getSubmissions()` has existed in the repository since the feature shipped
/// and was never called — the teacher card showed a submission COUNT and had
/// no way to open the list, and `assignment_submissions` had no marks column
/// to write to even if it had.
class AssignmentSubmissionsScreen extends StatefulWidget {
  final Map<String, dynamic> assignment;
  const AssignmentSubmissionsScreen({super.key, required this.assignment});

  @override
  State<AssignmentSubmissionsScreen> createState() =>
      _AssignmentSubmissionsScreenState();
}

class _AssignmentSubmissionsScreenState extends State<AssignmentSubmissionsScreen> {
  final _repo = AssignmentsRepository();
  List<Map<String, dynamic>> _submissions = [];
  bool _loading = true;
  String? _error;

  double get _maxMarks =>
      ((widget.assignment['max_marks'] as num?) ?? 10).toDouble();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final rows = await _repo.getSubmissions(widget.assignment['id'] as String);
      if (mounted) setState(() => _submissions = rows);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _grade(Map<String, dynamic> s, double marks, String? feedback) async {
    try {
      await _repo.gradeSubmission(
          submissionId: s['id'] as String, marks: marks, feedback: feedback);
      await _load();
      if (mounted) {
        AppHaptics.success();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Marked'), backgroundColor: AppColors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    }
  }

  Future<void> _openAttachment(String path) async {
    final url = await _repo.signedAttachmentUrl(path);
    if (!mounted) return;
    if (url == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not open that file'), backgroundColor: AppColors.red));
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final graded = _submissions.where((s) => s['marks'] != null).length;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(
          title: widget.assignment['title'] as String? ?? 'Submissions'),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: _load)
          : _loading
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(children: [
                    ShimmerCard(height: 110), SizedBox(height: 10),
                    ShimmerCard(height: 110),
                  ]))
              : Column(children: [
                  Container(
                    margin: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
                      border: Border.all(
                          color: AppColors.glassBorder(context), width: 0.8),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                            '${widget.assignment['course_code'] ?? ''} · '
                            'out of ${_maxMarks.toStringAsFixed(0)}',
                            style: AppTextStyles.bodyMedium.copyWith(
                                color: AppColors.textSecondaryOf(context))),
                      ),
                      Flexible(
                        child: PillBadge(
                            label: '$graded / ${_submissions.length} marked',
                            color: graded == _submissions.length && graded > 0
                                ? AppColors.green
                                : AppColors.amber),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: _submissions.isEmpty
                        ? const EmptyState(
                            icon: Icons.inbox_outlined,
                            title: 'Nothing handed in yet',
                            subtitle: 'Submissions from your class appear here')
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: NavInsets.content(context, top: 0),
                              itemCount: _submissions.length,
                              itemBuilder: (ctx, i) => _SubmissionCard(
                                submission: _submissions[i],
                                maxMarks: _maxMarks,
                                onGrade: (m, f) => _grade(_submissions[i], m, f),
                                onOpenAttachment: _openAttachment,
                              ),
                            ),
                          ),
                  ),
                ]),
    );
  }
}

class _SubmissionCard extends StatefulWidget {
  final Map<String, dynamic> submission;
  final double maxMarks;
  final void Function(double marks, String? feedback) onGrade;
  final Future<void> Function(String path) onOpenAttachment;

  const _SubmissionCard({
    required this.submission,
    required this.maxMarks,
    required this.onGrade,
    required this.onOpenAttachment,
  });

  @override
  State<_SubmissionCard> createState() => _SubmissionCardState();
}

class _SubmissionCardState extends State<_SubmissionCard> {
  late final TextEditingController _marksCtrl;
  late final TextEditingController _feedbackCtrl;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    final m = widget.submission['marks'] as num?;
    _marksCtrl = TextEditingController(
        text: m == null ? '' : m.toStringAsFixed(m % 1 == 0 ? 0 : 2));
    _feedbackCtrl =
        TextEditingController(text: widget.submission['feedback'] as String? ?? '');
  }

  @override
  void dispose() {
    _marksCtrl.dispose();
    _feedbackCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final parsed = double.tryParse(_marksCtrl.text.trim());
    if (parsed == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter a mark first'), backgroundColor: AppColors.amber));
      return;
    }
    // Clamped here for immediate feedback; the DB trigger is the real guard
    // and rejects anything above the assignment's own maximum.
    widget.onGrade(parsed.clamp(0, widget.maxMarks).toDouble(),
        _feedbackCtrl.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.submission;
    final p = s['profiles'] as Map<String, dynamic>? ?? const {};
    final marks = s['marks'] as num?;
    final attachment = s['attachment_url'] as String?;
    final content = s['content'] as String? ?? '';
    final isGraded = marks != null;
    final color = isGraded ? AppColors.green : AppColors.amber;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Column(children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(LiquidGlass.radiusCard),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['full_name'] as String? ?? 'Student',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleMedium
                          .copyWith(color: AppColors.textPrimaryOf(context))),
                  Text(
                      [
                        p['university_id'] as String? ?? '',
                        if (attachment != null) 'file attached',
                      ].where((e) => e.isNotEmpty).join(' · '),
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textSecondaryOf(context))),
                ]),
              ),
              Flexible(
                child: PillBadge(
                    label: isGraded
                        ? '${marks.toStringAsFixed(marks % 1 == 0 ? 0 : 1)}'
                            ' / ${widget.maxMarks.toStringAsFixed(0)}'
                        : 'NOT MARKED',
                    color: color),
              ),
              Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  color: AppColors.textSecondaryOf(context)),
            ]),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(13, 0, 13, 13),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (content.trim().isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.glassFill(context),
                    borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
                  ),
                  child: Text(content,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textPrimaryOf(context))),
                ),
                const SizedBox(height: 10),
              ],
              if (attachment != null) ...[
                OutlinedButton.icon(
                  onPressed: () => widget.onOpenAttachment(attachment),
                  icon: const Icon(Icons.attach_file_rounded, size: 17),
                  label: const Text('Open attachment'),
                ),
                const SizedBox(height: 10),
              ],
              Row(children: [
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _marksCtrl,
                    textAlign: TextAlign.center,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                    ],
                    // One mark field per submission, stacked down the list —
                    // same case as the marks-entry grid.
                    style: AppTextStyles.numericMedium.copyWith(
                        color: AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '0',
                      suffixText: '/${widget.maxMarks.toStringAsFixed(0)}',
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      filled: true,
                      fillColor: AppColors.blue.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                          borderRadius: AppDepth.radius(0),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _feedbackCtrl,
                    style: TextStyle(color: AppColors.textPrimaryOf(context)),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Feedback (optional)',
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      filled: true,
                      fillColor: AppColors.glassFill(context),
                      border: OutlineInputBorder(
                          borderRadius: AppDepth.radius(0),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(backgroundColor: AppColors.green),
                  child: const Text('Save'),
                ),
              ]),
            ]),
          ),
      ]),
    );
  }
}
