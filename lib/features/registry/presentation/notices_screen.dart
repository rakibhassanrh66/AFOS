import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../config/theme/motion.dart';
import '../../../core/layout/nav_insets.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/offline_cache.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../../web/presentation/widgets/adaptive_list.dart';

/// Everything the university has published, for the people it was published to.
///
/// WHY THIS EXISTS. Notices could be written — `ManageNoticesScreen` is a
/// complete authoring tool — and they could be pushed, because publishing one
/// broadcasts a notification. What there was no way to do was READ them. The
/// dashboard showed the newest three, and the module tile labelled "Notices"
/// opened the notification centre, which lists notifications rather than
/// notices: once a banner was dismissed or scrolled past, the notice behind it
/// was unreachable. The table has sat at zero rows since it was created, which
/// is what a write-only feature looks like from the outside.
class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});
  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  List<Map<String, dynamic>> _notices = const [];
  StreamSubscription? _sub;
  bool _loading = true;
  String _filter = 'ALL';

  /// The values `notices_category_check` actually permits, plus the ALL
  /// pseudo-filter. Kept in the same order the authoring screen offers them.
  static const _categories = [
    'ALL', 'GENERAL', 'RULE', 'ANNOUNCEMENT', 'URGENT', 'EXAM', 'EVENT',
  ];

  @override
  void initState() {
    super.initState();
    // Cached the same way the dashboard caches its preview: a notice is
    // exactly the thing someone opens on campus wifi that has just dropped.
    _sub = cachedListStream(
      cacheKey: 'notices_all',
      liveStream: () => SupabaseConfig.client
          .from('notices')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(100),
    ).listen((rows) {
      if (mounted) setState(() { _notices = rows; _loading = false; });
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  static Color categoryColour(String c) => switch (c) {
        'RULE' => AppColors.teal,
        'ANNOUNCEMENT' => AppColors.holoTeal,
        'URGENT' => AppColors.red,
        'EXAM' => AppColors.orange,
        'EVENT' => AppColors.pink,
        _ => AppColors.blue,
      };

  List<Map<String, dynamic>> get _visible => _filter == 'ALL'
      ? _notices
      : _notices.where((n) => '${n['category']}' == _filter).toList();

  @override
  Widget build(BuildContext context) {
    final shown = _visible;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const AfosAppBar(title: 'Notices'),
      body: Column(children: [
        FeatureHeader(
          title: 'University Notices',
          subtitle: _loading
              ? 'Loading…'
              : '${shown.length} notice${shown.length == 1 ? '' : 's'}'
                  '${_filter == 'ALL' ? '' : ' · $_filter'}',
          icon: AppIcons.notices,
          gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.red, AppColors.orange]),
          margin: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 12),
        )
            .animate()
            .fadeIn(duration: AppMotion.durationOf(context, AppMotion.base))
            .slideY(begin: -0.06, curve: AppMotion.standard),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 0),
            itemCount: _categories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final c = _categories[i];
              final on = c == _filter;
              final colour =
                  c == 'ALL' ? AppColors.blue : categoryColour(c);
              return GestureDetector(
                onTap: () => setState(() => _filter = c),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: colour.withValues(alpha: on ? 0.18 : 0.06),
                    borderRadius: AppDepth.radius(1),
                    border: Border.all(
                        color: colour.withValues(alpha: on ? 0.55 : 0.16)),
                  ),
                  child: Text(
                      c == 'ALL'
                          ? 'All'
                          : c[0] + c.substring(1).toLowerCase(),
                      style: AppTextStyles.labelSmall.copyWith(
                          color: colour,
                          fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : shown.isEmpty
                  ? EmptyState(
                      icon: AppIcons.notices,
                      title: _filter == 'ALL'
                          ? 'No notices yet'
                          : 'Nothing under $_filter',
                      subtitle: _filter == 'ALL'
                          ? 'Announcements and rules from the university appear here'
                          : 'Try another category')
                  : AdaptiveList(
                      padding: EdgeInsetsDirectional.fromSTEB(
                          16, 0, 16, 16 + NavInsets.of(context)),
                      itemCount: shown.length,
                      itemBuilder: (ctx, i) =>
                          _NoticeCard(notice: shown[i], index: i),
                    ),
        ),
      ]),
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final Map<String, dynamic> notice;
  final int index;
  const _NoticeCard({required this.notice, required this.index});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final category = '${notice['category'] ?? 'GENERAL'}';
    final colour = _NoticesScreenState.categoryColour(category);
    final when = DateTime.tryParse('${notice['created_at']}')?.toLocal();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppDepth.radius(2),
        border: Border.all(color: AppColors.borderOf(context), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // The accent takes the card's own corners, as the seat-plan card does —
        // a symmetric radius here reads as a separate stripe laid on top.
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(LiquidGlass.radiusCard),
              topRight: Radius.circular(LiquidGlass.radiusCut),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: colour.withValues(alpha: 0.14),
                    borderRadius: AppDepth.radius(0)),
                child: Text(category,
                    style: AppTextStyles.labelSmall.copyWith(
                        color: colour, fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              if (when != null)
                Text(AppFormatters.fullDate(when),
                    style: AppTextStyles.labelSmall
                        .copyWith(color: textSecondary)),
            ]),
            const SizedBox(height: 10),
            Text('${notice['title'] ?? ''}',
                style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
            if ('${notice['body'] ?? ''}'.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('${notice['body']}',
                  style:
                      AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
            ],
            if ('${notice['author_name'] ?? ''}'.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('— ${notice['author_name']}',
                  style:
                      AppTextStyles.labelSmall.copyWith(color: textSecondary)),
            ],
          ]),
        ),
      ]),
    ).animate(delay: AppMotion.staggerFor(context, index)).fadeIn().slideY(begin: 0.05);
  }
}
