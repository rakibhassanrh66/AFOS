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

import '../../../core/layout/nav_insets.dart';
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
  List<Map<String, dynamic>> _allocations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    setState(() => _error = null);
    try {
      // Both calls were plain, uncached fetches — offline meant an outright
      // failure (the error state below), not the last-known seat plan. High
      // stakes to get wrong for something students specifically check right
      // before walking into an exam, often on patchy exam-hall wifi. Same
      // cachedMapFetch/cachedListFetch pattern schedule_repository.dart
      // already uses for exams/routine data.
      final student = await cachedMapFetch(
        cacheKey: 'exam_seat_student_$uid',
        liveFetch: () async {
          final row = await SupabaseConfig.client.from('students')
              .select('batch_label, section').eq('profile_id', uid).maybeSingle();
          if (row == null) throw StateError('no student row yet');
          return row;
        },
      );
      final batch = student?['batch_label'] as String?;
      final section = student?['section'] as String?;
      if (batch == null || section == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final res = await cachedListFetch(
        cacheKey: 'exam_seat_allocations_${batch}_$section',
        liveFetch: () async {
          final rows = await SupabaseConfig.client.from('exam_room_allocations')
              .select().eq('batch', batch).eq('section', section)
              .order('exam_date').order('room_no') as List;
          return rows.cast<Map<String, dynamic>>();
        },
      );
      if (mounted) setState(() => _allocations = res);
    } catch (e) {
      // Previously swallowed silently, so a real load failure (network
      // blip, expired session) rendered identically to "seat plan not
      // published yet" — high-stakes to get wrong for something students
      // check right before an exam.
      if (mounted) setState(() => _error = friendlyError(e));
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Groups the flat room-allocation rows into one card per exam session
  /// (same date+slot+course), each listing every room assigned to it.
  List<_ExamSession> get _sessions {
    final byKey = <String, _ExamSession>{};
    for (final a in _allocations) {
      final key = '${a['exam_date']}_${a['slot_label']}_${a['course_code']}';
      byKey.putIfAbsent(key, () => _ExamSession(
          examDate: DateTime.tryParse(a['exam_date'] ?? ''),
          slotLabel: a['slot_label'], slotStart: a['slot_start'], slotEnd: a['slot_end'],
          courseCode: a['course_code'], courseTitle: a['course_title'], teacherInitial: a['teacher_initial']));
      byKey[key]!.rooms.add(_RoomSeats(a['room_no'] ?? '-', a['seats'] as int? ?? 0));
    }
    final sessions = byKey.values.toList()
      ..sort((a, b) => (a.examDate ?? DateTime(0)).compareTo(b.examDate ?? DateTime(0)));
    return sessions;
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Exam Seat Plan'),
      body: Column(children: [
        FeatureHeader(
          title: 'Exam Seat Plan',
          subtitle: _loading ? 'Loading…' : '${sessions.length} upcoming session${sessions.length == 1 ? '' : 's'}',
          icon: AppIcons.examSeat,
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [AppColors.orange, AppColors.amber]),
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        ).animate().fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
            .slideY(begin: -0.06, curve: AppMotion.standard),
        Expanded(child: _loading
            ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
            : _error != null
                ? ErrorView(message: _error!, onRetry: _load)
                : sessions.isEmpty
                ? const EmptyState(icon: AppIcons.examSeat,
                    title: 'No seat plan yet', subtitle: 'Room allocations will appear here once published')
                : RefreshIndicator(
                    onRefresh: _load, color: AppColors.blue,
                    child: ListView.builder(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + NavInsets.of(context)),
                        itemCount: sessions.length,
                        itemBuilder: (ctx, i) => _SessionCard(session: sessions[i], index: i)))),
      ]),
    );
  }
}

class _RoomSeats { final String room; final int seats; _RoomSeats(this.room, this.seats); }

class _ExamSession {
  final DateTime? examDate;
  final String? slotLabel, slotStart, slotEnd, courseCode, courseTitle, teacherInitial;
  final List<_RoomSeats> rooms = [];
  _ExamSession({this.examDate, this.slotLabel, this.slotStart, this.slotEnd,
      this.courseCode, this.courseTitle, this.teacherInitial});
}

class _SessionCard extends StatelessWidget {
  final _ExamSession session; final int index;
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
                    boxShadow: [BoxShadow(color: AppColors.orange.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]),
                child: const Icon(Icons.event_note_rounded, color: Colors.white, size: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(session.courseTitle ?? 'Exam', style: AppTextStyles.titleLarge.copyWith(color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
              if ((session.courseCode ?? '').isNotEmpty)
                Text(session.courseCode!, style: AppTextStyles.monoSmall.copyWith(color: textSecondary)),
            ])),
          ]),
          const SizedBox(height: 12),
          if (session.examDate != null) Row(children: [
            Icon(Icons.calendar_today_rounded, size: 14, color: textSecondary),
            const SizedBox(width: 6),
            Text(AppFormatters.fullDate(session.examDate!), style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
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
