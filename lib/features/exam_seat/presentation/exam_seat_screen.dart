import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

class ExamSeatScreen extends StatefulWidget {
  const ExamSeatScreen({super.key});
  @override State<ExamSeatScreen> createState() => _ExamSeatState();
}

class _ExamSeatState extends State<ExamSeatScreen> {
  List<Map<String, dynamic>> _assignments = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final res = await SupabaseConfig.client
          .from('exam_seat_assignments')
          .select('*, exams(*)')
          .eq('student_id', uid) as List;
      if (mounted) setState(() => _assignments = res.cast());
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: 'Exam Seat Plan'),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
          : _assignments.isEmpty
              ? EmptyState(icon: Icons.event_seat_rounded,
                  title: 'No seat assignments', subtitle: 'Seat plans will appear here before exams')
              : RefreshIndicator(
                  onRefresh: _load, color: AppColors.blue,
                  child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _assignments.length,
                      itemBuilder: (ctx, i) => _SeatCard(assignment: _assignments[i], index: i))),
    );
  }
}

class _SeatCard extends StatelessWidget {
  final Map<String, dynamic> assignment; final int index;
  const _SeatCard({required this.assignment, required this.index});

  @override
  Widget build(BuildContext context) {
    final exam = assignment['exams'] as Map<String, dynamic>? ?? {};
    final isRetake = assignment['is_retake'] as bool? ?? false;
    final examDate = exam['exam_date'] != null ? DateTime.tryParse(exam['exam_date']) : null;

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isRetake ? AppColors.gold : AppColors.borderOf(context), width: isRetake ? 1.5 : 0.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(height: 4, decoration: BoxDecoration(
              color: isRetake ? AppColors.gold : AppColors.blue,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(15)))),
          Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(exam['subject'] ?? 'Unknown Subject', style: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimaryOf(context))),
                Text(exam['subject_code'] ?? '', style: AppTextStyles.monoSmall.copyWith(color: AppColors.textSecondaryOf(context))),
              ])),
              if (isRetake) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                  child: const Text('RETAKE', style: TextStyle(color: AppColors.gold, fontSize: 11, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 12),
            if (examDate != null) Row(children: [
              Icon(Icons.calendar_today_rounded, size: 14, color: AppColors.textSecondaryOf(context)),
              const SizedBox(width: 6),
              Text(AppFormatters.fullDate(examDate), style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.access_time_rounded, size: 14, color: AppColors.textSecondaryOf(context)),
              const SizedBox(width: 6),
              Text('${exam['start_time'] ?? '--'} – ${exam['end_time'] ?? '--'}',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
            ]),
            const SizedBox(height: 12),
            Container(padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.gold.withOpacity(0.08), borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.gold.withOpacity(0.25))),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _SeatInfo('Room', assignment['room_number'] ?? '-'),
                  _SeatInfo('Seat', assignment['seat_number'] ?? '-'),
                  _SeatInfo('Row', assignment['row_label'] ?? '-'),
                  _SeatInfo('Floor', '${assignment['floor_number'] ?? '-'}'),
                ])),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.apartment_rounded, size: 14, color: AppColors.textSecondaryOf(context)),
              const SizedBox(width: 6),
              Text(assignment['building'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
            ]),
          ])),
        ]),
      ),
    ).animate(delay: Duration(milliseconds: index * 80)).fadeIn().slideY(begin: 0.05);
  }

  void _showDetail(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx, backgroundColor: AppColors.surfaceOf(ctx), isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.borderOf(ctx), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Text('Seat Details', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(ctx))),
            const SizedBox(height: 20),
            RepaintBoundary(
              child: GlassCard(
                glowColor: AppColors.gold,
                padding: const EdgeInsets.all(16),
                child: _SeatMapWidget(rows: 6, cols: 5,
                    studentRow: 2, studentCol: 3,
                    seatLabel: assignment['seat_number'] ?? 'S?'),
              ),
            ),
            const SizedBox(height: 20),
            AfosButton(
              label: 'Download Admit Card',
              icon: Icons.download_rounded,
              onTap: () { Navigator.pop(ctx); },
            ),
          ])));
  }
}

class _SeatInfo extends StatelessWidget {
  final String label, value;
  const _SeatInfo(this.label, this.value);
  @override
  Widget build(BuildContext context) => Column(children: [
    Text(value, style: AppTextStyles.headlineLarge.copyWith(color: AppColors.gold)),
    Text(label, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
  ]);
}

class _SeatMapWidget extends StatelessWidget {
  final int rows, cols, studentRow, studentCol;
  final String seatLabel;
  const _SeatMapWidget({required this.rows, required this.cols,
      required this.studentRow, required this.studentCol, required this.seatLabel});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(color: AppColors.textMutedOf(context).withOpacity(0.3), borderRadius: BorderRadius.circular(6)),
          child: Text('TEACHER', style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 10, letterSpacing: 2))),
      ...List.generate(rows, (r) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(cols, (c) {
                final isMe = r == studentRow && c == studentCol;
                return Container(
                  width: 40, height: 36, margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                      color: isMe ? AppColors.gold : AppColors.surfaceOf(context),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: isMe ? AppColors.gold : AppColors.borderOf(context), width: isMe ? 2 : 0.5),
                      boxShadow: isMe ? [BoxShadow(color: AppColors.gold.withOpacity(0.4), blurRadius: 8)] : null),
                  child: Center(child: isMe
                      ? Text(seatLabel, style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w800))
                      : null),
                );
              })))),
    ]);
  }
}
