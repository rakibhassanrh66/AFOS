import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../config/theme/app_colors.dart';
import '../../config/theme/app_text_styles.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/local_cache_service.dart';
import '../../config/theme/spacing.dart';

/// Phase E of the offline policy (docs/OFFLINE_POLICY.md): the global
/// [OfflineBanner] says "you're offline" once for the whole app, but doesn't
/// say which data on THIS screen is live vs. stale. This fills that gap —
/// invisible online or when nothing is cached yet, and only ever appears
/// alongside data that is actually a cache read, never invented staleness.
class CacheFreshnessBadge extends StatelessWidget {
  final String cacheKey;
  final bool isMap;
  const CacheFreshnessBadge({super.key, required this.cacheKey, this.isMap = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.isOnline,
      builder: (context, online, _) {
        if (online) return const SizedBox.shrink();
        final cachedAt = isMap
            ? LocalCacheService.instance.getMap(cacheKey)?.cachedAt
            : LocalCacheService.instance.getList(cacheKey)?.cachedAt;
        if (cachedAt == null) return const SizedBox.shrink();
        // Align, not just a Row — most call sites drop this straight into a
        // `Column(children: [...])` with no explicit crossAxisAlignment,
        // which defaults to center. Left this on a bare intrinsic-width Row
        // and it would float centered under a left-aligned header instead of
        // lining up with it. Align fills the available width itself, so the
        // parent Column's alignment can no longer move it.
        return Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.history_rounded, size: 12, color: AppColors.textSecondaryOf(context)),
              const SizedBox(width: AppSpace.xs),
              Text('Cached · updated ${timeago.format(cachedAt)}',
                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
            ]),
          ),
        );
      },
    );
  }
}
