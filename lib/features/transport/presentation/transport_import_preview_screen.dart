import 'package:flutter/material.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/info_card.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../data/models/transport_schedule.dart';
import '../data/transport_import_service.dart';

/// The QA gate the admin sees BEFORE any transport data is written: every
/// parsed route grouped by section (Regular / Shuttle / Friday), each with its
/// trips + notes and a validation status (ok / warning / error). Pops `true`
/// only on explicit "Confirm & Import".
class TransportImportPreviewScreen extends StatelessWidget {
  final ParsedTransportSchedule parsed;
  final TransportValidation validation;
  const TransportImportPreviewScreen({super.key, required this.parsed, required this.validation});

  @override
  Widget build(BuildContext context) {
    final bySection = <ScheduleType, List<TransportRoute>>{};
    for (final r in parsed.routes) {
      bySection.putIfAbsent(r.scheduleType, () => []).add(r);
    }

    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimaryOf(context)),
        title: Text('Review Import', style: TextStyle(color: AppColors.textPrimaryOf(context))),
      ),
      body: SafeArea(
        child: Column(children: [
          // No `navContentClearance` on this list: the pinned _ConfirmBar sits
          // below it and the enclosing SafeArea already consumes the shell's
          // bottom inset for both. Adding it here counted the clearance twice
          // and left ~145px of dead space between the last route card and the
          // confirm bar.
          Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
            FeatureHeader(
              title: 'Schedule for ${parsed.semester}',
              subtitle: '${parsed.routes.length} routes'
                  '${parsed.campus != null ? ' · ${parsed.campus}' : ''}',
              icon: Icons.directions_bus_filled_rounded,
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [AppColors.holoTeal, AppColors.holoBlue]),
              margin: const EdgeInsets.only(bottom: 12),
            ),
            _SummaryBar(validation: validation),
            const SizedBox(height: 8),
            for (final entry in bySection.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text(entry.key.label.toUpperCase(),
                    style: AppTextStyles.labelSmall.copyWith(
                        letterSpacing: 1.5, color: AppColors.textSecondaryOf(context))),
              ),
              for (final route in entry.value)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _RoutePreviewCard(route: route, validation: validation),
                ),
            ],
            const SizedBox(height: 12),
          ])),
          _ConfirmBar(validation: validation),
        ]),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  final TransportValidation validation;
  const _SummaryBar({required this.validation});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _stat(context, 'Errors', validation.errorCount, AppColors.red)),
      const SizedBox(width: 10),
      Expanded(child: _stat(context, 'Warnings', validation.warningCount, AppColors.amber)),
    ]);
  }

  Widget _stat(BuildContext context, String label, int n, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: n > 0 ? color.withValues(alpha: 0.12) : AppColors.glassFill(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: n > 0 ? color.withValues(alpha: 0.4) : AppColors.glassBorder(context), width: n > 0 ? 1 : 0.5),
        ),
        child: Row(children: [
          Icon(n > 0 ? (label == 'Errors' ? Icons.error_outline_rounded : Icons.warning_amber_rounded) : Icons.check_circle_outline_rounded,
              color: n > 0 ? color : AppColors.green, size: 20),
          const SizedBox(width: 10),
          Text('$n', style: TextStyle(color: n > 0 ? color : AppColors.textPrimaryOf(context), fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 12)),
        ]),
      );
}

class _RoutePreviewCard extends StatelessWidget {
  final TransportRoute route;
  final TransportValidation validation;
  const _RoutePreviewCard({required this.route, required this.validation});

  @override
  Widget build(BuildContext context) {
    final level = validation.levelFor(route);
    final accent = switch (level) {
      IssueLevel.error => AppColors.red,
      IssueLevel.warning => AppColors.amber,
      IssueLevel.ok => AppColors.green,
    };
    final messages = validation.messagesFor(route);

    return InfoCard(
      accent: accent,
      stripe: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(8)),
            child: Text(route.routeNo, style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(route.routeName.isEmpty ? '(no name)' : route.routeName,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context)))),
          PillBadge(
            label: level == IssueLevel.ok ? 'OK' : level.name.toUpperCase(),
            color: accent,
          ),
        ]),
        if (route.stops.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(route.stops.join('  ›  '),
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(context))),
        ],
        const SizedBox(height: 10),
        _TripRow(label: 'To DSC', trips: route.toDscTrips),
        const SizedBox(height: 6),
        _TripRow(label: 'From DSC', trips: route.fromDscTrips),
        if (messages.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final m in messages)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, size: 14, color: accent),
                const SizedBox(width: 6),
                Expanded(child: Text(m, style: AppTextStyles.labelSmall.copyWith(color: accent))),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _TripRow extends StatelessWidget {
  final String label;
  final List<Trip> trips;
  const _TripRow({required this.label, required this.trips});

  @override
  Widget build(BuildContext context) {
    final shown = trips.where((t) => !t.isEmpty).toList();
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 64, child: Text(label,
          style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w700))),
      Expanded(child: shown.isEmpty
          ? Text('—', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMutedOf(context)))
          : Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in shown) _TripChip(trip: t),
            ])),
    ]);
  }
}

class _TripChip extends StatelessWidget {
  final Trip trip;
  const _TripChip({required this.trip});
  @override
  Widget build(BuildContext context) {
    final comingSoon = trip.isComingSoon;
    final color = comingSoon ? AppColors.amber : AppColors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(comingSoon ? 'Being updated' : (trip.time ?? '—'),
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        if (comingSoon)
          Text('time not set yet', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context)))
        else if (trip.note != null && trip.note!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(trip.note!, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
          ),
      ]),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  final TransportValidation validation;
  const _ConfirmBar({required this.validation});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context), width: 0.5)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (validation.hasErrors)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Some routes have errors — review them, then import if you still want to proceed.',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.red)),
          ),
        Row(children: [
          Expanded(child: AfosButton(
            label: 'Cancel', outlined: true, color: AppColors.textSecondaryOf(context),
            onTap: () => Navigator.of(context).pop(false),
          )),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: AfosButton(
            label: 'Confirm & Import',
            color: validation.hasErrors ? AppColors.amber : AppColors.green,
            onTap: () => Navigator.of(context).pop(true),
          )),
        ]),
      ]),
    );
  }
}
