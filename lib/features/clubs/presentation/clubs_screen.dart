import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

class ClubsScreen extends StatefulWidget {
  const ClubsScreen({super.key});
  @override State<ClubsScreen> createState() => _ClubsState();
}

class _ClubsState extends State<ClubsScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String, dynamic>> _clubs = [], _myClubs = [], _events = [];
  bool _loading = true;
  String _filter = 'All';
  static const _filters = ['All', 'Tech', 'Sports', 'Cultural', 'Volunteer', 'Academic'];

  @override
  void initState() { super.initState(); _tab = TabController(length: 3, vsync: this); _load(); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = SupabaseConfig.uid;
    try {
      var q = SupabaseConfig.client.from('clubs').select();
      if (_filter != 'All') q = q.eq('category', _filter);
      final [clubs, events] = await Future.wait([
        q.order('name') as Future,
        SupabaseConfig.client.from('club_events').select().order('event_date') as Future,
      ]);
      List myClubs = [];
      if (uid != null) {
        myClubs = await SupabaseConfig.client.from('club_members')
            .select('*, clubs(*)').eq('member_id', uid) as List;
      }
      if (mounted) setState(() {
        _clubs = (clubs as List).cast();
        _events = (events as List).cast();
        _myClubs = myClubs.cast();
      });
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _join(String clubId) async {
    try {
      await SupabaseConfig.client.from('club_members').insert(
          {'club_id': clubId, 'member_id': SupabaseConfig.uid, 'role': 'member'});
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Joined club ✓'), backgroundColor: AppColors.green));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AfosAppBar(title: 'Clubs'),
      body: Column(children: [
        Container(color: AppColors.surface, child: TabBar(controller: _tab,
            labelColor: AppColors.blue, unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.blue,
            tabs: const [Tab(text: 'Discover'), Tab(text: 'My Clubs'), Tab(text: 'Events')])),
        Expanded(child: TabBarView(controller: _tab, children: [
          Column(children: [
            _FilterBar(selected: _filter, filters: _filters,
                onSelect: (f) { setState(() => _filter = f); _load(); }),
            Expanded(child: _loading
                ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 5, itemHeight: 120))
                : _ClubList(clubs: _clubs, myClubs: _myClubs, onJoin: _join)),
          ]),
          _loading ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _MyClubsTab(myClubs: _myClubs),
          _loading ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _EventsTab(events: _events),
        ])),
      ]),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final String selected; final List<String> filters; final ValueChanged<String> onSelect;
  const _FilterBar({required this.selected, required this.filters, required this.onSelect});
  @override
  Widget build(BuildContext context) => Container(
    height: 48, color: AppColors.surface,
    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: filters.map((f) {
          final sel = selected == f;
          return Padding(padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(onTap: () => onSelect(f),
                  child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: sel ? AppColors.pink : AppColors.card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: sel ? AppColors.pink : AppColors.border, width: 0.5)),
                      child: Text(f, style: TextStyle(color: sel ? Colors.white : AppColors.textSecondary,
                          fontSize: 12, fontWeight: sel ? FontWeight.w600 : FontWeight.normal)))));
        }).toList()),
  );
}

class _ClubList extends StatelessWidget {
  final List<Map<String, dynamic>> clubs, myClubs; final ValueChanged<String> onJoin;
  const _ClubList({required this.clubs, required this.myClubs, required this.onJoin});
  @override
  Widget build(BuildContext context) {
    if (clubs.isEmpty) return EmptyState(icon: Icons.groups_rounded, title: 'No clubs found', subtitle: 'Check back later');
    final joinedIds = myClubs.map((m) => m['club_id'] as String? ?? '').toSet();
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: clubs.length,
        itemBuilder: (ctx, i) {
          final c = clubs[i];
          final joined = joinedIds.contains(c['id'] as String?);
          return Container(margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border, width: 0.5)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(height: 80, decoration: BoxDecoration(
                    color: AppColors.pink.withOpacity(0.15),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
                    child: const Center(child: Icon(Icons.groups_rounded, color: AppColors.pink, size: 36))),
                Padding(padding: const EdgeInsets.all(14), child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c['name'] ?? '', style: AppTextStyles.titleLarge),
                    const SizedBox(height: 3),
                    Text(c['tagline'] ?? '', style: AppTextStyles.bodyMedium, maxLines: 2),
                    const SizedBox(height: 6),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: AppColors.pink.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                        child: Text(c['category'] ?? '', style: const TextStyle(color: AppColors.pink, fontSize: 11, fontWeight: FontWeight.w600))),
                  ])),
                  const SizedBox(width: 12),
                  GestureDetector(onTap: joined ? null : () => onJoin(c['id']),
                      child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(color: joined ? AppColors.green.withOpacity(0.1) : AppColors.pink,
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(joined ? 'Joined ✓' : 'Join',
                              style: TextStyle(color: joined ? AppColors.green : Colors.white,
                                  fontSize: 13, fontWeight: FontWeight.w600)))),
                ])),
              ])).animate(delay: Duration(milliseconds: i * 60)).fadeIn().slideY(begin: 0.05);
        });
  }
}

class _MyClubsTab extends StatelessWidget {
  final List<Map<String, dynamic>> myClubs;
  const _MyClubsTab({required this.myClubs});
  @override
  Widget build(BuildContext context) {
    if (myClubs.isEmpty) return EmptyState(icon: Icons.group_add_rounded,
        title: 'No clubs joined', subtitle: 'Discover and join clubs from the Discover tab');
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: myClubs.length,
        itemBuilder: (ctx, i) {
          final m = myClubs[i];
          final club = m['clubs'] as Map<String, dynamic>? ?? {};
          return Container(margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 0.5)),
              child: Row(children: [
                Container(width: 44, height: 44, decoration: BoxDecoration(
                    color: AppColors.pink.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.groups_rounded, color: AppColors.pink, size: 24)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(club['name'] ?? '', style: AppTextStyles.titleMedium),
                  Text(club['category'] ?? '', style: AppTextStyles.bodyMedium),
                ])),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                    child: Text((m['role'] as String? ?? 'member').toUpperCase(),
                        style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w700))),
              ]));
        });
  }
}

class _EventsTab extends StatelessWidget {
  final List<Map<String, dynamic>> events;
  const _EventsTab({required this.events});
  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return EmptyState(icon: Icons.event_rounded,
        title: 'No upcoming events', subtitle: 'Events will appear here');
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: events.length,
        itemBuilder: (ctx, i) {
          final e = events[i];
          final date = e['event_date'] != null ? DateTime.tryParse(e['event_date']) : null;
          return Container(margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border, width: 0.5)),
              child: Row(children: [
                Container(width: 48, height: 56, decoration: BoxDecoration(
                    color: AppColors.indigo.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(date != null ? '${date.day}' : '?',
                          style: const TextStyle(color: AppColors.indigo, fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(date != null ? _month(date.month) : '',
                          style: const TextStyle(color: AppColors.indigo, fontSize: 10)),
                    ])),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e['title'] ?? '', style: AppTextStyles.titleMedium),
                  Text(e['venue'] ?? '', style: AppTextStyles.bodyMedium),
                  if (e['max_seats'] != null) Text('${e['max_seats']} seats',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ])),
              ]));
        });
  }
  String _month(int m) => ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m];
}
