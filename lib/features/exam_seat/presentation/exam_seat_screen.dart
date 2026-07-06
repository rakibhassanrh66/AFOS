import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

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

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final student = await SupabaseConfig.client.from('students')
          .select('batch_label, section').eq('profile_id', uid).maybeSingle();
      final batch = student?['batch_label'] as String?;
      final section = student?['section'] as String?;
      if (batch == null || section == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final res = await SupabaseConfig.client.from('exam_room_allocations')
          .select().eq('batch', batch).eq('section', section)
          .order('exam_date').order('room_no') as List;
      if (mounted) setState(() => _allocations = res.cast());
    } catch (_) {}
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
      appBar: AfosAppBar(title: 'Exam Seat Plan'),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
          : sessions.isEmpty
              ? EmptyState(icon: AppIcons.examSeat,
                  title: 'No seat plan yet', subtitle: 'Room allocations will appear here once published')
              : RefreshIndicator(
                  onRefresh: _load, color: AppColors.blue,
                  child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: sessions.length,
                      itemBuilder: (ctx, i) => _SessionCard(session: sessions[i], index: i))),
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
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(height: 4, decoration: BoxDecoration(
            color: AppColors.blue, borderRadius: const BorderRadius.vertical(top: Radius.circular(15)))),
        Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(session.courseTitle ?? 'Exam', style: AppTextStyles.titleLarge.copyWith(color: textPrimary)),
          if ((session.courseCode ?? '').isNotEmpty)
            Text(session.courseCode!, style: AppTextStyles.monoSmall.copyWith(color: textSecondary)),
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
              decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.3))),
              child: Text('${r.room} · ${r.seats} seats',
                  style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700, fontSize: 12)))).toList()),
          if ((session.teacherInitial ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10),
              child: Text('Course teacher: ${session.teacherInitial}', style: TextStyle(color: textSecondary, fontSize: 11))),
        ])),
      ]),
    ).animate(delay: Duration(milliseconds: index * 80)).fadeIn().slideY(begin: 0.05);
  }
}
