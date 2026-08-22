import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../config/theme/motion.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/offline_cache.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/error_view.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/exam_seat_view.dart';

import '../../../core/layout/nav_insets.dart';
import '../../web/presentation/widgets/adaptive_list.dart';
/// Shows which room(s) the student's own batch+section is assigned for
/// each exam — confirmed against a real DIU seat-plan document that this
/// is genuinely all it publishes (room capacity per section, split across
/// several rooms), never an individual seat/desk number, so that's what's
/// shown here rather than a fabricated seat-map visualization.
class ExamSeatScreen extends StatefulWidget {
  const ExamSeatScreen({super.key});
  @override State<ExamSeatScreen> createState() => _ExamSeatState();
}

class _ExamSeatState extends State<ExamSeatScreen> {
  ExamSeatView _view = const ExamSeatView();
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    setState(() => _error = null);
    try {
      // This screen used to select exam_room_allocations by batch+section
      // alone — no date bound and no term. That was correct while the table
      // held one exam period and became wrong the moment it held two:
      // verified live on 2026-08-22, mid-finals, a batch-67 student was
      // shown three JUNE mid-term sessions under the heading "upcoming",
      // two of them titled only "Exam" because those rows carry no course
      // code, and nothing at all about the exam they sat the next morning.
      //
      // The list therefore comes from my_exam_schedule(), which already
      // picks the live published term, applies the batch -> all-sections
      // fan-out and narrows by the caller's own section. The allocation
      // rows are read only to decorate it with seat counts, and are bounded
      // by that same term's window.
      //
      // cachedListFetch (not cachedMapFetch) for a single object on purpose:
      // the lenient variant returns null on a failed fetch, which here would
      // render a network blip as "no exam routine published" — the exact
      // silent-empty class of bug this project has already paid for once.
      final wrapped = await cachedListFetch(
        cacheKey: 'exam_schedule_$uid',
        liveFetch: () async {
          final res = await SupabaseConfig.client.rpc('my_exam_schedule');
          return [(res as Map).cast<String, dynamic>()];
        },
      );
      final sched = wrapped.isEmpty ? const <String, dynamic>{} : wrapped.first;
      final term = (sched['term'] as Map?)?.cast<String, dynamic>();
      final batch = sched['batch'] as String?;
      final section = sched['section'] as String?;

      // Seats and the course teacher's initial are not in the RPC payload
      // (it returns room numbers only), so they come from the allocation
      // rows. A student with a batch and no section deliberately gets every
      // room the batch uses rather than none — same fan-out rule the RPC
      // applies, so the two agree.
      var seatRows = const <Map<String, dynamic>>[];
      if (term != null && (batch ?? '').isNotEmpty) {
        seatRows = await cachedListFetch(
          cacheKey: 'exam_seat_alloc_${term['id']}_${batch}_${section ?? 'all'}',
          liveFetch: () async {
            var q = SupabaseConfig.client.from('exam_room_allocations')
                .select().eq('batch', batch!);
            if ((section ?? '').isNotEmpty) q = q.eq('section', section!);
            if (term['startsOn'] != null) q = q.gte('exam_date', term['startsOn']);
            if (term['endsOn'] != null) q = q.lte('exam_date', term['endsOn']);
            final rows = await q.order('exam_date').order('room_no') as List;
            return rows.cast<Map<String, dynamic>>();
          },
        );
      }

      final view = ExamSeatView.from(sched, seatRows);
      if (mounted) setState(() => _view = view);
    } catch (e) {
      // Previously swallowed silently, so a real load failure (network
      // blip, expired session) rendered identically to "seat plan not
      // published yet" — high-stakes to get wrong for something students
      // check right before an exam.
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  /// The subtitle used to read "N upcoming sessions" for a list that was not
  /// filtered to upcoming anything. It now names the term and counts only
  /// what has genuinely not happened yet.
  String _subtitle() {
    if (_loading) return 'Loading…';
    if (_view.term == null) return 'No exam routine published';
    if (_view.isOver) return '${_view.termLabel} · finished';
    return '${_view.termLabel} · ${_view.upcomingCount()} upcoming';
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _view.sessions;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Exam Seat Plan'),
      body: Column(children: [
        FeatureHeader(
          title: 'Exam Seat Plan',
          subtitle: _subtitle(),
          icon: AppIcons.examSeat,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.orange, AppColors.amber]),
          margin: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
        ).animate().fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
            .slideY(begin: -0.06, curve: AppMotion.standard),
        Expanded(child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : sessions.isEmpty
                // Three different nothings, which the old single "No seat
                // plan yet" ran together: no routine has been published at
                // all, one has but this batch does not sit in it, and the
                // caller has no batch on their profile to match against.
                ? EmptyState(icon: AppIcons.examSeat,
                    title: _view.term == null
                        ? 'No exam routine published'
                        : 'No exams for your batch',
                    subtitle: _view.term == null
                        ? 'Your rooms appear here once the exam routine is published'
                        : '${_view.termLabel} is published but lists nothing for your batch and section')
                : RefreshIndicator(
                    onRefresh: _load, color: AppColors.blue,
                    child: AdaptiveList(
                        padding: EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16 + NavInsets.of(context)),
                        itemCount: sessions.length,
                        itemBuilder: (ctx, i) => _SessionCard(session: sessions[i], index: i)))),
      ]),
    );
  }
}

class _SessionCard extends StatelessWidget {
  final ExamSessionView session; final int index;
  const _SessionCard({required this.session, required this.index});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: AppDepth.radius(2),
          border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // The accent bar sits ON the card's top edge, so it takes the card's
        // own corners — three large, top-right cut — not a symmetric radius.
        Container(height: 4, decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [AppColors.orange, AppColors.amber]),
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(LiquidGlass.radiusCard),
                topRight: Radius.circular(LiquidGlass.radiusCut)))),
        Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(width: 40, height: 40,
                decoration: BoxDecoration(
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [AppColors.orange, AppColors.amber]),
                    borderRadius: AppDepth.radius(1),
                    boxShadow: [BoxShadow(color: AppColors.orange.withValues(alpha: 0.3), blurRadius: 8, offset: AppDepth.litOffset(3))]),
                child: const Icon(Icons.event_note_rounded, color: Colors.white, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(session.courseTitle ?? 'Exam', style: AppTextStyles.titleLarge.copyWith(color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
              if ((session.courseCode ?? '').isNotEmpty)
                Text(session.courseCode!, style: AppTextStyles.monoSmall.copyWith(color: textSecondary)),
            ])),
          ]),
          const SizedBox(height: 12),
          if (session.date != null) Row(children: [
            Icon(Icons.calendar_today_rounded, size: 14, color: textSecondary),
            const SizedBox(width: 6),
            Text(AppFormatters.fullDate(session.date!), style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
            // A term runs for a week or more, so by the middle of it the list
            // holds exams already sat. They stay — a student checking which
            // room they were in is a real thing — but they must not read as
            // still to come.
            if (session.isPast()) ...[
              const SizedBox(width: 8),
              Text('Completed',
                  style: AppTextStyles.labelSmall.copyWith(
                      color: textSecondary, fontWeight: FontWeight.w700)),
            ],
          ]),
          if (session.slotStart != null) Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
            Icon(Icons.access_time_rounded, size: 14, color: textSecondary),
            const SizedBox(width: 6),
            Text('Slot ${session.slotLabel ?? ''} · ${session.slotStart} – ${session.slotEnd}',
                style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
          ])),
          const SizedBox(height: 12),
          Text('Your section\'s room(s)', style: AppTextStyles.labelSmall.copyWith(color: textSecondary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          // An empty Wrap rendered as nothing at all under that heading, so a
          // routine with no seat plan yet looked identical to a rendering
          // fault. The room is the one thing this screen exists to answer:
          // when it is genuinely not known, say so.
          if (session.rooms.isEmpty)
            Text('Room not published yet',
                style: AppTextStyles.bodyMedium.copyWith(color: textSecondary))
          else
          Wrap(spacing: 8, runSpacing: 8, children: session.rooms.map((r) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.1), borderRadius: AppDepth.radius(1),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.3))),
              // Room number and seat count, several chips side by side — a
              // column of figures the eye scans across, so tabular.
              child: Text('${r.room} · ${r.seats} seats',
                  style: AppTextStyles.numericSmall.copyWith(
                      color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 12)))).toList()),
          if ((session.teacherInitial ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10),
              child: Text('Course teacher: ${session.teacherInitial}', style: TextStyle(color: textSecondary, fontSize: 11))),
        ])),
      ]),
    ).animate(delay: AppMotion.staggerFor(context, index)).fadeIn().slideY(begin: 0.05);
  }
}
