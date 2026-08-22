import 'package:flutter/material.dart';

import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/button_styles.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../../../shared/widgets/user_details_sheet.dart';
import '../../shell/presentation/top_app_bar.dart';
import 'widgets/offering_card.dart' show offeringStatusColor;

/// What the teacher is actually being asked to decide, on a page of its own.
///
/// The requester's profile used to be a bottom sheet reached by tapping the
/// name — it opened over the queue, it could not be scrolled comfortably next
/// to the decision, and crucially it carried NO buttons, so reviewing somebody
/// and then acting on them were two separate motions with a dismiss in
/// between. A teacher checking twenty applicants did that forty times.
///
/// Here the identity and the decision are the same screen: read who they are,
/// then accept or decline without going anywhere. Returning `true` means the
/// caller should reload, because something was decided.
class JoinRequestDetailScreen extends StatefulWidget {
  final Map<String, dynamic> request;

  /// All async and all optional, because which of them apply depends entirely
  /// on the request's current status — a declined request has no Decline.
  final Future<void> Function()? onAccept;
  final Future<void> Function()? onDecline;
  final Future<void> Function()? onRemove;
  final Future<void> Function()? onReconsider;

  const JoinRequestDetailScreen({
    super.key,
    required this.request,
    this.onAccept,
    this.onDecline,
    this.onRemove,
    this.onReconsider,
  });

  @override
  State<JoinRequestDetailScreen> createState() => _JoinRequestDetailScreenState();
}

class _JoinRequestDetailScreenState extends State<JoinRequestDetailScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final student = r['profiles'] as Map<String, dynamic>? ?? const {};
    final offering = r['course_offerings'] as Map<String, dynamic>? ?? const {};
    final course = offering['courses'] as Map<String, dynamic>? ?? const {};
    final status = r['status'] as String? ?? 'pending';
    final archived = offering['is_archived'] == true;
    final requestedAt = DateTime.tryParse(r['created_at'] as String? ?? '');

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Review Request'),
      // A single request being read and decided on — the most column-shaped
      // thing in the app. Full-width stretched the decision buttons to the
      // far edge of a 1440px window, away from the request they act on.
      body: AdaptiveContentWidth(maxWidth: 760, child: ListView(
        padding: NavInsets.content(context),
        children: [
          Row(children: [
            Expanded(
              child: Text(
                '${course['code'] ?? 'Course'} · Section ${offering['section'] ?? '—'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.textPrimaryOf(context)),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          // Own line, uncapped. Beside the title it was a non-flex sibling
          // competing for the same row; capped small enough not to starve the
          // title, it clipped its own word instead. There is no width that
          // satisfies both, so they stop sharing a line.
          Align(
            alignment: Alignment.centerLeft,
            child: PillBadge(
                label: status.toUpperCase(),
                color: offeringStatusColor(status),
                maxWidth: double.infinity),
          ),
          const SizedBox(height: 4),
          Text(
            'Batch ${offering['batch'] ?? '—'}'
            '${requestedAt == null ? '' : ' · asked ${AppFormatters.dateTime(requestedAt)}'}',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textSecondaryOf(context)),
          ),
          const SizedBox(height: 16),

          // The single question this page exists to answer, before the identity
          // detail rather than after it.
          _MatchVerdict(
            studentBatch: student['batch'] as String?,
            studentSection: student['section'] as String?,
            offeringBatch: offering['batch'] as String?,
            offeringSection: offering['section'] as String?,
          ),

          if (archived) ...[
            const SizedBox(height: 10),
            const _Notice(
              color: AppColors.red,
              icon: Icons.archive_outlined,
              // Not a soft warning: the database refuses this outright
              // (trg_no_approval_into_archived), so an Accept here fails. Say
              // so before the tap instead of surfacing a Postgres error after.
              message: 'This course has ended, so nobody can be admitted to it. '
                  'Restore it from My Course Offerings first if that was a mistake.',
            ),
          ],

          const SizedBox(height: 16),
          UserDetailsSheet(
            profile: student,
            extraRows: {
              if ((student['email'] as String?)?.isNotEmpty == true)
                'Email': student['email'] as String,
              if ((student['semester'] as num?) != null) 'Semester': '${student['semester']}',
              if (requestedAt != null) 'Requested': AppFormatters.dateTime(requestedAt),
            },
          ),

          const SizedBox(height: 24),
          JoinRequestActions(
            status: status,
            archived: archived,
            busy: _busy,
            onAccept: widget.onAccept == null ? null : () => _run(widget.onAccept!),
            onDecline: widget.onDecline == null ? null : () => _run(widget.onDecline!),
            onRemove: widget.onRemove == null ? null : () => _run(widget.onRemove!),
            onReconsider:
                widget.onReconsider == null ? null : () => _run(widget.onReconsider!),
          ),
        ],
      )),
    );
  }
}

/// The decision buttons at the foot of the Review Request page.
///
/// A widget of its own rather than a method on the State so
/// `review_screens_layout_test` can measure it. The whole screen cannot go
/// through that harness — it is a full Scaffold with an AppBar, and nesting one
/// inside the probe's scroll view trips a framework focus assertion — but these
/// buttons are the part that carries the risk, because the app theme gives
/// OutlinedButton `minimumSize: Size(double.infinity, 52)` and a long label on
/// a full-width button still has to fit its own text.
class JoinRequestActions extends StatelessWidget {
  final String status;
  final bool archived, busy;
  final VoidCallback? onAccept, onDecline, onRemove, onReconsider;

  const JoinRequestActions({
    super.key,
    required this.status,
    required this.archived,
    required this.busy,
    this.onAccept,
    this.onDecline,
    this.onRemove,
    this.onReconsider,
  });

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Center(
          child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()));
    }
    // Every label is capped. These sit on full-width buttons, so at a large
    // text scale on a narrow phone the label is wider than the button it is
    // inside and overflows it — the button does not shrink to fit its text.
    return switch (status) {
      // A Wrap, not a Row of two Expandeds.
      //
      // Two Expandeds split the row in half whether or not half is enough. On a
      // 320dp phone at a 1.6x text scale each half gave the label 105px of the
      // 158px "Decline" needs, so a THIRD of the word was cut off — the buttons
      // fit, their text did not.
      //
      // A Wrap sizes each button to its own label and moves the second one to a
      // line of its own only when they genuinely cannot share one, so nothing
      // is ever truncated and the common 1.0x case still reads as a pair. This
      // only works with rowAction(): the theme sets
      // `minimumSize: Size(double.infinity, 52)`, and inside a Wrap an
      // infinitely-wide button takes a line to itself at EVERY scale — which is
      // exactly how these cards shipped once before, a full-width Decline with
      // a stranded Accept beneath it.
      'pending' => Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 8,
          children: [
            OutlinedButton(
              onPressed: onDecline,
              style: rowAction(
                  OutlinedButton.styleFrom(foregroundColor: AppColors.red)),
              child: const Text('Decline', maxLines: 1),
            ),
            FilledButton(
              onPressed: archived ? null : onAccept,
              style: rowAction(
                  FilledButton.styleFrom(backgroundColor: AppColors.green)),
              child: const Text('Accept', maxLines: 1),
            ),
          ],
        ),
      // No Flexible around these labels: `label` is not a direct child of a
      // Flex — the button builds its own Row and already wraps the label in a
      // Flexible itself — so adding one throws "Incorrect use of
      // ParentDataWidget". maxLines + ellipsis is the whole fix.
      'approved' => OutlinedButton.icon(
          onPressed: onRemove,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.red),
          icon: const Icon(Icons.person_remove_outlined, size: 18),
          label: const Text('Remove from this course',
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      'rejected' => OutlinedButton.icon(
          onPressed: onReconsider,
          icon: const Icon(Icons.undo_rounded, size: 18),
          label: const Text('Put back in the queue',
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Belongs-in-this-section verdict, stated as a conclusion rather than as two
/// batch strings the teacher has to compare themselves.
class _MatchVerdict extends StatelessWidget {
  final String? studentBatch, studentSection, offeringBatch, offeringSection;
  const _MatchVerdict({
    required this.studentBatch,
    required this.studentSection,
    required this.offeringBatch,
    required this.offeringSection,
  });

  static String _n(Object? v) => (v as String? ?? '').trim().toUpperCase();

  @override
  Widget build(BuildContext context) {
    final sb = _n(studentBatch), ss = _n(studentSection);
    final ob = _n(offeringBatch), os = _n(offeringSection);

    if (sb.isEmpty || ss.isEmpty) {
      return const _Notice(
        color: AppColors.amber,
        icon: Icons.help_outline_rounded,
        message: 'This student has not set their batch or section, so there is '
            'nothing to check them against. Decide on the ID and name.',
      );
    }
    if (sb == ob && ss == os) {
      return _Notice(
        color: AppColors.green,
        icon: Icons.check_circle_outline_rounded,
        message: 'In batch $sb, section $ss — exactly this class. Nothing unusual here.',
      );
    }
    return _Notice(
      color: AppColors.amber,
      icon: Icons.error_outline_rounded,
      message: 'They are in batch $sb, section $ss but this class is batch $ob, '
          'section $os. Legitimate for a retaker or someone who moved — worth asking.',
    );
  }
}

class _Notice extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String message;
  const _Notice({required this.color, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(LiquidGlass.radiusControl),
          border: Border.all(color: color.withValues(alpha: 0.30), width: 0.5),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: AppTextStyles.bodyMedium.copyWith(color: color)),
          ),
        ]),
      );
}
