import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/widgets/afos_text_field.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/info_card.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

import '../../../shared/widgets/glass_bottom_nav.dart';
/// Lightweight cross-module search: one query fans out to notices, class
/// schedule, library books, lost & found, and clubs; results are grouped by
/// module and tap through to the relevant screen. All reads go through the
/// caller's existing RLS (authenticated-read tables) — no new access path.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});
  @override State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _SearchHit {
  final String title, subtitle, route;
  final IconData icon;
  final Color color;
  const _SearchHit(this.title, this.subtitle, this.route, this.icon, this.color);
}

class _SearchGroup {
  final String label;
  final List<_SearchHit> hits;
  const _SearchGroup(this.label, this.hits);
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  int _gen = 0;
  bool _loading = false;
  String _query = '';
  List<_SearchGroup> _groups = [];

  @override
  void dispose() { _debounce?.cancel(); _ctrl.dispose(); super.dispose(); }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    if (q.length < 2) {
      setState(() { _query = q; _groups = []; _loading = false; });
      return;
    }
    final gen = ++_gen;
    setState(() { _query = q; _loading = true; });
    final like = '%$q%';
    final client = SupabaseConfig.client;

    Future<List<_SearchHit>> run(Future<List> Function() query, _SearchHit Function(Map<String, dynamic>) map) async {
      try {
        final rows = await query();
        return rows.map((r) => map(Map<String, dynamic>.from(r as Map))).toList();
      } catch (_) {
        return const [];
      }
    }

    final results = await Future.wait([
      // Notices
      run(() => client.from('notices').select('title, body, category').ilike('title', like).limit(6),
          (r) => _SearchHit(r['title'] as String? ?? '', r['body'] as String? ?? 'Notice',
              '/notifications', AppIcons.notices, AppColors.red)),
      // Class schedule (by subject)
      run(() => client.from('schedule_slots').select('subject, building, room_number').ilike('subject', like).limit(6),
          (r) => _SearchHit(r['subject'] as String? ?? '', '${r['building'] ?? ''} ${r['room_number'] ?? ''}'.trim(),
              '/schedule', AppIcons.schedule, AppColors.blue)),
      // Library books
      run(() => client.from('books').select('title, author').ilike('title', like).limit(6),
          (r) => _SearchHit(r['title'] as String? ?? '', r['author'] as String? ?? 'Book',
              '/library', AppIcons.library, AppColors.indigo)),
      // Lost & found
      run(() => client.from('lost_found_posts').select('title, description, type').ilike('title', like).limit(6),
          (r) => _SearchHit(r['title'] as String? ?? '', (r['type'] as String? ?? 'item').toUpperCase(),
              '/lost-found', AppIcons.lostFound, AppColors.coral)),
      // Clubs
      run(() => client.from('clubs').select('name, description').ilike('name', like).limit(6),
          (r) => _SearchHit(r['name'] as String? ?? '', r['description'] as String? ?? 'Club',
              '/clubs', AppIcons.clubs, AppColors.pink)),
    ]);

    if (!mounted || gen != _gen) return;
    final groups = <_SearchGroup>[];
    const labels = ['Notices', 'Class Schedule', 'Library', 'Lost & Found', 'Clubs'];
    for (var i = 0; i < results.length; i++) {
      if (results[i].isNotEmpty) groups.add(_SearchGroup(labels[i], results[i]));
    }
    setState(() { _groups = groups; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Search'),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: AfosTextField(
            hint: 'Search notices, classes, books, clubs…',
            controller: _ctrl,
            prefixIcon: Icons.search_rounded,
            onChanged: _onChanged,
          ),
        ),
        Expanded(child: _body(context)),
      ]),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(16), child: ShimmerList(count: 5));
    }
    if (_query.length < 2) {
      return const EmptyState(
        icon: Icons.search_rounded,
        title: 'Search across AFOS',
        subtitle: 'Find notices, classes, library books, lost & found items, and clubs — all in one place.',
      );
    }
    if (_groups.isEmpty) {
      return EmptyState(
        icon: Icons.search_off_rounded,
        title: 'No results for "$_query"',
        subtitle: 'Try a different keyword.',
      );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24 + GlassBottomNav.navContentClearance), children: [
      for (final g in _groups) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
          child: Text('${g.label.toUpperCase()}  ·  ${g.hits.length}',
              style: AppTextStyles.labelSmall.copyWith(
                  letterSpacing: 1.2, color: AppColors.textSecondaryOf(context))),
        ),
        for (final h in g.hits)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InfoCard(
              accent: h.color,
              icon: h.icon,
              title: h.title.isEmpty ? '(untitled)' : h.title,
              subtitle: h.subtitle,
              trailing: Icon(Icons.chevron_right_rounded, color: AppColors.textSecondaryOf(context), size: 20),
              onTap: () => context.push(h.route),
            ),
          ),
      ],
    ]);
  }
}
