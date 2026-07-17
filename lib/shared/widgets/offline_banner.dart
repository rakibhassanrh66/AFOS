import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../config/theme/app_colors.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/outbox_service.dart';
import 'glass_sheet.dart';

class OfflineBanner extends StatefulWidget {
  final Widget child;
  const OfflineBanner({super.key, required this.child});
  @override State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _offline = !ConnectivityService.instance.isOnline.value;

  @override
  void initState() {
    super.initState();
    ConnectivityService.instance.isOnline.addListener(_onConnectivityChanged);
  }

  @override
  void dispose() {
    ConnectivityService.instance.isOnline.removeListener(_onConnectivityChanged);
    super.dispose();
  }

  void _onConnectivityChanged() {
    if (mounted) setState(() => _offline = !ConnectivityService.instance.isOnline.value);
  }

  void _showPendingActions() {
    showGlassSheet(context, child: const _PendingActionsSheet());
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = OutboxService.instance.pending.where((r) => r['status'] == 'pending').length;
    final failedCount = OutboxService.instance.pending.where((r) => r['status'] == 'failed').length;
    return Column(children: [
      AnimatedCrossFade(
        firstChild: Container(
          width: double.infinity, color: AppColors.amber, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.wifi_off, size: 16, color: Colors.white),
            SizedBox(width: 8),
            Flexible(child: Text(
                "No internet — showing cached data. New actions will be saved and sent when you're back online.",
                style: TextStyle(color: Colors.white, fontSize: 12), textAlign: TextAlign.center)),
          ]),
        ),
        secondChild: const SizedBox.shrink(),
        crossFadeState: _offline ? CrossFadeState.showFirst : CrossFadeState.showSecond,
        duration: const Duration(milliseconds: 300),
      ),
      if (pendingCount > 0 || failedCount > 0)
        GestureDetector(
          onTap: _showPendingActions,
          child: Container(
            width: double.infinity,
            color: (failedCount > 0 ? AppColors.red : AppColors.blue).withValues(alpha: 0.12),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(failedCount > 0 ? Icons.error_outline_rounded : Icons.cloud_upload_outlined,
                  size: 14, color: failedCount > 0 ? AppColors.red : AppColors.blue),
              const SizedBox(width: 6),
              Text(
                failedCount > 0
                    ? '$failedCount action${failedCount == 1 ? '' : 's'} failed to send — tap to review'
                    : '$pendingCount action${pendingCount == 1 ? '' : 's'} waiting to send',
                style: TextStyle(color: failedCount > 0 ? AppColors.red : AppColors.blue, fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        ),
      Expanded(child: widget.child),
    ]);
  }
}

class _PendingActionsSheet extends StatefulWidget {
  const _PendingActionsSheet();
  @override State<_PendingActionsSheet> createState() => _PendingActionsSheetState();
}

class _PendingActionsSheetState extends State<_PendingActionsSheet> {
  static const _typeLabels = {
    'hall_application_submit': 'Hall application',
    'feedback_submit': 'Feedback',
    'mentorship_booking_request': 'Mentorship request',
    'club_join_request': 'Club join request',
    'cr_request': 'CR request',
  };

  Future<void> _retry(String key) async {
    await OutboxService.instance.retry(key);
    if (mounted) setState(() {});
  }

  Future<void> _discard(String key) async {
    await OutboxService.instance.discard(key);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = OutboxService.instance.pending;
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Queued actions', style: TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text("Sent automatically once you're back online.",
              style: TextStyle(color: textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('Nothing queued', style: TextStyle(color: textSecondary))))
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final row = items[i];
                  final key = row['key'] as String;
                  final type = row['type'] as String;
                  final status = row['status'] as String? ?? 'pending';
                  final createdAt = DateTime.tryParse(row['createdAt'] as String? ?? '');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Icon(status == 'failed' ? Icons.error_outline_rounded : Icons.schedule_rounded,
                          color: status == 'failed' ? AppColors.red : AppColors.amber, size: 20),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_typeLabels[type] ?? type, style: TextStyle(color: textPrimary, fontWeight: FontWeight.w600)),
                        Text(createdAt != null ? timeago.format(createdAt) : '',
                            style: TextStyle(color: textSecondary, fontSize: 11)),
                      ])),
                      if (status == 'failed') ...[
                        TextButton(onPressed: () => _retry(key), child: const Text('Retry')),
                        TextButton(onPressed: () => _discard(key),
                            child: const Text('Discard', style: TextStyle(color: AppColors.red))),
                      ],
                    ]),
                  );
                },
              ),
            ),
        ]);
  }
}
