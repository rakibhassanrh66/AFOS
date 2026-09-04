import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../config/theme/app_colors.dart';
import '../../../../config/theme/app_text_styles.dart';
import '../../../../config/theme/depth.dart';
import '../../../../config/theme/motion.dart';
import '../../../../config/theme/spacing.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../../core/utils/error_formatter.dart';
import '../../../../shared/widgets/afos_button.dart';
import '../../../../shared/widgets/afos_text_field.dart';
import '../../../../shared/widgets/pill_badge.dart';
import '../../../../shared/widgets/surface_card.dart';
import '../../data/models/teacher_link.dart';
import '../../data/repositories/advising_repository.dart';

/// The student's side of one pairing — advisor or final-year supervisor.
///
/// One widget for both, because the flow is identical: type an initial, see
/// who it is, ask, wait, then talk. Only the copy and the [kind] differ, and
/// building it twice is how two screens drift.
///
/// States, in the order a student meets them:
///   empty     - a field asking for an initial
///   resolved  - the teacher's card, with Request
///   pending   - waiting on them, with Withdraw
///   active    - the card again, with Message
///   declined  - the reason, and the field back
class TeacherLinkCard extends StatefulWidget {
  final LinkKind kind;

  /// Shown instead of the whole card when the student is not eligible — the
  /// FYDP card is for 3rd and 4th year only. Null means "always show".
  final String? ineligibleReason;

  /// Called after any change, so the profile screen can refresh around it.
  final VoidCallback? onChanged;

  const TeacherLinkCard({
    super.key,
    required this.kind,
    this.ineligibleReason,
    this.onChanged,
  });

  @override
  State<TeacherLinkCard> createState() => _TeacherLinkCardState();
}

class _TeacherLinkCardState extends State<TeacherLinkCard> {
  final _repo = AdvisingRepository();
  final _initialCtrl = TextEditingController();

  TeacherLink? _link;
  TeacherCard? _teacher;
  TeacherCard? _preview;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _lookupNote;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _initialCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final link = await _repo.myLink(widget.kind);
      TeacherCard? teacher;
      if (link != null) {
        // The link names a teacher_id, but a student may not read the teacher
        // directory — so the card comes back through the same resolver, keyed
        // on the initial the student themselves typed.
        teacher = await _repo.resolveInitial(_initialCtrl.text);
      }
      if (!mounted) return;
      setState(() {
        _link = link;
        _teacher = teacher;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  void _onTyped(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _preview = null;
        _lookupNote = null;
      });
      return;
    }
    // 350ms: long enough that a three-letter initial is not four round trips,
    // short enough that the card feels like it answers as you type.
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final found = await _repo.resolveInitial(value);
        if (!mounted) return;
        setState(() {
          _preview = found;
          _lookupNote = found == null
              ? 'No teacher is registered under "${value.trim()}". Check it with '
                  'your department — initials are set by the teacher themselves.'
              : null;
        });
      } catch (_) {
        // A failed lookup while typing is not worth an error state; the
        // Request button reports properly if it is really broken.
      }
    });
  }

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _repo.request(_initialCtrl.text, widget.kind);
      AppHaptics.success();
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _end() async {
    final link = _link;
    if (link == null) return;
    setState(() => _busy = true);
    try {
      await _repo.end(link.id);
      AppHaptics.success();
      _initialCtrl.clear();
      setState(() => _preview = null);
      await _load();
      widget.onChanged?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reason = widget.ineligibleReason;
    if (reason != null) return const SizedBox.shrink();

    return SurfaceCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context),
          AppSpace.vGapMd,
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.lg),
              child: Center(
                child: SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            AnimatedSize(
              duration: AppMotion.durationOf(context, AppMotion.base),
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: _body(context),
            ),
          if (_error != null) ...[
            AppSpace.vGapSm,
            Text(_error!,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.red)),
          ],
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final status = _link?.status;
    return Row(children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: AppColors.holoBlue.withValues(alpha: 0.14),
          borderRadius: AppDepth.radius(0),
        ),
        child: Icon(
            widget.kind == LinkKind.fydp
                ? Icons.science_rounded
                : Icons.support_agent_rounded,
            size: 18,
            color: AppColors.holoBlue),
      ),
      AppSpace.gapMd,
      Expanded(
        child: Text(widget.kind.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.titleMedium
                .copyWith(color: AppColors.textPrimaryOf(context))),
      ),
      // Flexible, not bare: a Row lays its non-flex children out first with
      // unbounded width, so a badge beside an Expanded title can take the
      // whole row and leave the title with 0px. row_starve_guard_test caught
      // exactly this here.
      if (status == LinkStatus.pending)
        const Flexible(child: PillBadge(label: 'WAITING', color: AppColors.amber))
      else if (status == LinkStatus.active)
        const Flexible(child: PillBadge(label: 'ACTIVE', color: AppColors.green)),
    ]);
  }

  Widget _body(BuildContext context) {
    final link = _link;

    if (link != null && link.status.isLive) {
      return Column(
        key: ValueKey('live-${link.id}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_teacher != null)
            TeacherSummary(teacher: _teacher!)
          else
            Text(
              link.status == LinkStatus.pending
                  ? 'Your request is with them. You will be told when they answer.'
                  : 'Linked. Open the conversation below.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondaryOf(context)),
            ),
          AppSpace.vGapMd,
          Row(children: [
            Expanded(
              child: AfosButton(
                label: link.status == LinkStatus.pending ? 'Withdraw' : 'Release',
                outlined: true,
                loading: _busy,
                onTap: _busy ? null : _end,
              ),
            ),
          ]),
        ],
      );
    }

    // No live link: the field, plus the reason the last one ended if there
    // was one. A decline without its reason reads as the app losing the
    // request.
    return Column(
      key: const ValueKey('empty'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (link?.status == LinkStatus.declined && link?.declineReason != null) ...[
          Container(
            width: double.infinity,
            padding: AppSpace.allMd,
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.10),
              borderRadius: AppDepth.radius(1),
            ),
            child: Text('Declined: ${link!.declineReason}',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textPrimaryOf(context))),
          ),
          AppSpace.vGapMd,
        ],
        Text(
          widget.kind == LinkKind.fydp
              ? 'Type your supervisor’s initial exactly as your department writes it.'
              : 'Type your advisor’s initial exactly as your department writes it.',
          style: AppTextStyles.bodyMedium
              .copyWith(color: AppColors.textSecondaryOf(context)),
        ),
        AppSpace.vGapSm,
        AfosTextField(
          hint: 'Teacher initial',
          controller: _initialCtrl,
          textInputAction: TextInputAction.search,
          onChanged: _onTyped,
        ),
        if (_lookupNote != null) ...[
          AppSpace.vGapSm,
          Text(_lookupNote!,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondaryOf(context))),
        ],
        if (_preview != null) ...[
          AppSpace.vGapMd,
          TeacherSummary(teacher: _preview!),
          AppSpace.vGapMd,
          AfosButton(
            label: 'Ask ${_preview!.fullName.split(' ').first} to be my '
                '${widget.kind.teacherNoun.toLowerCase()}',
            loading: _busy,
            onTap: _busy ? null : _request,
          ),
        ],
      ],
    );
  }
}

/// The teacher's card. Shown both while choosing and once linked, so the
/// person a student picked looks the same before and after they said yes.
///
/// Public so the layout sweep can drive the REAL widget across six viewports
/// and four text scales. A copy in a test cannot regress.
class TeacherSummary extends StatelessWidget {
  final TeacherCard teacher;
  const TeacherSummary({required this.teacher});

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      if (teacher.designation != null) teacher.designation!,
      if (teacher.department != null) teacher.department!,
    ];
    return Container(
      width: double.infinity,
      padding: AppSpace.allMd,
      decoration: BoxDecoration(
        color: AppColors.holoBlue.withValues(alpha: 0.08),
        borderRadius: AppDepth.radius(1),
        border: Border.all(color: AppColors.holoBlue.withValues(alpha: 0.22)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(teacher.fullName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.titleMedium
                      .copyWith(color: AppColors.textPrimaryOf(context))),
              if (lines.isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs),
                Text(lines.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textSecondaryOf(context))),
              ],
            ]),
          ),
          if (teacher.initial != null) ...[
            AppSpace.gapSm,
            // An initial is short, but nothing enforces that — it is free
            // text a teacher types. Flexible so a long one cannot eat the
            // name it sits beside.
            Flexible(
                child: PillBadge(
                    label: teacher.initial!, color: AppColors.holoBlue)),
          ],
        ]),
        if (teacher.onLeave) ...[
          AppSpace.vGapSm,
          Row(children: [
            const Icon(Icons.event_busy_rounded, size: 14, color: AppColors.amber),
            AppSpace.gapXs,
            Expanded(
              child: Text('On leave today',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.amber)),
            ),
          ]),
        ],
        if (teacher.email != null || teacher.phone != null) ...[
          AppSpace.vGapSm,
          Text(
            [teacher.email, teacher.phone]
                .where((v) => (v ?? '').isNotEmpty)
                .join('  ·  '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondaryOf(context)),
          ),
        ],
      ]),
    );
  }
}
