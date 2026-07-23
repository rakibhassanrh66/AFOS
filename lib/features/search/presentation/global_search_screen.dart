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
import '../../../core/utils/postgrest_filters.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../transport/data/transport_display.dart';

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
    // `%` and `_` are ilike wildcards. Interpolating the raw query meant a
    // search for "100%" or "a_b" silently matched far more than was typed.
    final like = '%${escapeLikePattern(q)}%';
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
      // Bus routes. Transport was missing from global search entirely, so
      // searching a stop name campus-wide returned nothing even though seven
      // routes pass through Mirpur.
      //
      // Fetched whole and ranked on the client, NOT filtered with `.or(...)`.
      // PostgREST's `or=(...)` embeds the value into a filter *expression*, and
      // its grammar was actively hostile here — verified against the live API:
      //   * a COMMA ("Mirpur-1, 10") → PGRST100 "failed to parse logic tree".
      //     The try/catch above swallowed it, so transport results silently
      //     vanished with no error shown.
      //   * PARENTHESES ("Malibagh Railgate (South Bus Stop)" is a real stop)
      //     parsed as filter syntax and returned WRONG rows rather than failing.
      //   * `*` is a wildcard alias for `%` in like/ilike and cannot be escaped.
      // Quoting the value fixes the first two but not the third, and only 21
      // routes are active — a few KB — so filtering locally is both cheaper and
      // exactly consistent with the in-app Transport search, since it reuses the
      // same `searchRank` matcher (punctuation-insensitive, any token order,
      // ranked). `route_details` is the ordered stop list as text, which is what
      // makes STOPS searchable at all — the `stops` jsonb can't be matched here.
      () async {
        try {
          final rows = await client.from('transport_routes')
              .select('route_number, route_name, route_details')
              .eq('is_active', true) as List;
          final routes = rows.cast<Map<String, dynamic>>();
          final ranked = searchRank(routes, q,
              (r) => '${r['route_number'] ?? ''} ${r['route_name'] ?? ''} ${r['route_details'] ?? ''}');
          return ranked.take(6).map((r) => _SearchHit(
              '${r['route_number'] ?? ''} — ${(r['route_name'] as String? ?? 'Route').replaceAll(RegExp(r'\s*[<>]+\s*'), ' › ')}',
              r['route_details'] as String? ?? 'Bus route',
              '/transport', Icons.directions_bus_filled_rounded, AppColors.holoTeal)).toList();
        } catch (_) {
          return const <_SearchHit>[];
        }
      }(),
    ]);

    if (!mounted || gen != _gen) return;
    final groups = <_SearchGroup>[];
    const labels = ['Notices', 'Class Schedule', 'Library', 'Lost & Found', 'Clubs', 'Transport'];
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
            hint: 'Search notices, classes, books, clubs, routes…',
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
        subtitle: 'Find notices, classes, library books, lost & found items, clubs, and bus routes — all in one place.',
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
