import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

class MentorshipScreen extends StatefulWidget {
  const MentorshipScreen({super.key});
  @override State<MentorshipScreen> createState() => _MentorshipState();
}

class _MentorshipState extends State<MentorshipScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _mentors = [], _sessions = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _tab = TabController(length: 2, vsync: this); _load(); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final [mentors, sessions] = await Future.wait([
        SupabaseConfig.client.from('mentors').select('*, profiles(full_name,avatar_url,department)') as Future,
        SupabaseConfig.client.from('mentorship_bookings').select('*, mentors(*, profiles(full_name))')
            .eq('student_id', SupabaseConfig.uid ?? '').order('created_at', ascending: false) as Future,
      ]);
      if (mounted) setState(() {
        _mentors = (mentors as List).cast();
        _sessions = (sessions as List).cast();
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AfosAppBar(title: 'Mentorship'),
      body: Column(children: [
        Container(color: AppColors.surfaceOf(context), child: TabBar(controller: _tab,
            labelColor: AppColors.blue, unselectedLabelColor: AppColors.textSecondaryOf(context),
            indicatorColor: AppColors.blue,
            tabs: const [Tab(text: 'Find Mentor'), Tab(text: 'My Sessions')])),
        Expanded(child: TabBarView(controller: _tab, children: [
          _loading ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 4, itemHeight: 130))
              : _MentorList(mentors: _mentors, onBook: (m) => _showBookingDialog(context, m)),
          _loading ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _SessionsTab(sessions: _sessions, onRefresh: _load),
        ])),
      ]),
    );
  }

  void _showBookingDialog(BuildContext ctx, Map<String, dynamic> mentor) {
    final topicCtrl = TextEditingController();
    showModalBottomSheet(context: ctx, isScrollControlled: true,
        backgroundColor: AppColors.surfaceOf(ctx),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Book Session', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(ctx))),
              const SizedBox(height: 6),
              Text('with ${(mentor['profiles'] as Map?)?['full_name'] ?? ''}',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(ctx))),
              const SizedBox(height: 20),
              AfosTextField(hint: 'What topic do you need help with?', controller: topicCtrl, maxLines: 3),
              const SizedBox(height: 16),
              AfosButton(label: 'Request Session', onTap: () async {
                if (topicCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await SupabaseConfig.client.from('mentorship_bookings').insert({
                    'student_id': SupabaseConfig.uid,
                    'mentor_id': mentor['id'],
                    'topic': topicCtrl.text.trim(),
                    'status': 'pending',
                  });
                  _load();
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Session requested ✓'), backgroundColor: AppColors.green));
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString()), backgroundColor: AppColors.red));
                }
              }),
            ])));
  }
}

class _MentorList extends StatelessWidget {
  final List<Map<String, dynamic>> mentors;
  final ValueChanged<Map<String, dynamic>> onBook;
  const _MentorList({required this.mentors, required this.onBook});

  @override
  Widget build(BuildContext context) {
    if (mentors.isEmpty) return EmptyState(icon: Icons.school_rounded,
        title: 'No mentors available', subtitle: 'Mentors will appear here once faculty register');
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: mentors.length,
        itemBuilder: (ctx, i) {
          final m = mentors[i];
          final profile = m['profiles'] as Map<String, dynamic>? ?? {};
          final specs = (m['specializations'] as List?)?.cast<String>() ?? [];
          return Container(margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 56, height: 56, decoration: BoxDecoration(
                    shape: BoxShape.circle, border: Border.all(color: AppColors.blue.withOpacity(0.3), width: 2),
                    color: AppColors.blue.withOpacity(0.1)),
                    child: const Center(child: Icon(Icons.person_rounded, color: AppColors.blue, size: 28))),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(profile['full_name'] ?? '', style: AppTextStyles.titleLarge.copyWith(color: AppColors.textPrimaryOf(context))),
                  Text(m['title'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
                  Text(profile['department'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
                  const SizedBox(height: 8),
                  if (specs.isNotEmpty) Wrap(spacing: 6, runSpacing: 4, children: specs.map((s) =>
                      Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                          child: Text(s, style: const TextStyle(color: AppColors.blue, fontSize: 10)))).toList()),
                  const SizedBox(height: 12),
                  Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(
                        color: (m['is_accepting_bookings'] as bool? ?? true) ? AppColors.green : AppColors.red,
                        shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text((m['is_accepting_bookings'] as bool? ?? true) ? 'Available' : 'Busy',
                        style: TextStyle(
                            color: (m['is_accepting_bookings'] as bool? ?? true) ? AppColors.green : AppColors.red,
                            fontSize: 12)),
                    const Spacer(),
                    if (m['is_accepting_bookings'] as bool? ?? true)
                      GestureDetector(onTap: () => onBook(m),
                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(color: AppColors.blue, borderRadius: BorderRadius.circular(20)),
                              child: const Text('Book →', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)))),
                  ]),
                ])),
              ])).animate(delay: Duration(milliseconds: i * 70)).fadeIn().slideY(begin: 0.05);
        });
  }
}

class _SessionsTab extends StatelessWidget {
  final List<Map<String, dynamic>> sessions; final VoidCallback onRefresh;
  const _SessionsTab({required this.sessions, required this.onRefresh});

  Color _statusColor(String s) => switch(s) {
    'confirmed' => AppColors.green, 'rejected' => AppColors.red,
    'completed' => AppColors.textSecondary, _ => AppColors.amber
  };

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return EmptyState(icon: Icons.event_note_rounded,
        title: 'No sessions yet', subtitle: 'Book your first mentorship session');
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: sessions.length,
        itemBuilder: (ctx, i) {
          final s = sessions[i];
          final mentor = (s['mentors'] as Map?)?['profiles'] as Map? ?? {};
          final status = s['status'] as String? ?? 'pending';
          return Container(margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
              child: Row(children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(
                    color: AppColors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
                    shape: BoxShape.rectangle),
                    child: const Icon(Icons.school_rounded, color: AppColors.blue, size: 22)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(mentor['full_name'] ?? 'Faculty', style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
                  Text(s['topic'] ?? '', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context)), maxLines: 2, overflow: TextOverflow.ellipsis),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: _statusColor(status).withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                    child: Text(status.toUpperCase(),
                        style: TextStyle(color: _statusColor(status), fontSize: 10, fontWeight: FontWeight.w700))),
              ]));
        });
  }
}
