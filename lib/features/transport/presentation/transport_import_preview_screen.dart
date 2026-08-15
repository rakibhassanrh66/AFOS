import 'package:flutter/material.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/depth.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/info_card.dart';
import '../../../shared/widgets/pill_badge.dart';
import '../data/models/transport_schedule.dart';
import '../data/transport_import_service.dart';
import '../data/transport_time_parser.dart';

/// What the review screen hands back to the uploader: the (possibly
/// admin-edited) routes to actually write, the optional broadcast message, and
/// the warning count after edits (so the caller's summary line reflects fixes
/// made here, not the pre-edit parse). Null from the push means cancelled.
typedef ImportReviewResult = ({List<TransportRoute> routes, String message, int warningCount});

/// The QA gate the admin sees BEFORE any transport data is written: every
/// parsed route grouped by section (Regular / Shuttle / Friday), each with its
/// trips + notes, a validation status (ok / warning / error), and now an
/// **Edit** action — the sheet a wrong parse (a mis-typed time, a garbled stop
/// name) gets corrected in, so bad data never goes live in the first place
/// instead of requiring a full re-upload of the source Excel.
///
/// The admin/super-admin can also attach an optional **message to everyone**
/// here — a free-text notice ("R4 morning bus cancelled tomorrow", "new Uttara
/// route added") that rides the university-wide push the upload already sends,
/// instead of the generic "schedule updated" line.
///
/// Pops an [ImportReviewResult] on "Confirm & Import" (carrying every edit made
/// here), or `null` on cancel (back button, swipe, or Cancel).
class TransportImportPreviewScreen extends StatefulWidget {
  final ParsedTransportSchedule parsed;
  final TransportValidation validation;
  const TransportImportPreviewScreen({super.key, required this.parsed, required this.validation});

  @override
  State<TransportImportPreviewScreen> createState() => _TransportImportPreviewScreenState();
}

class _TransportImportPreviewScreenState extends State<TransportImportPreviewScreen> {
  final _messageCtrl = TextEditingController();
  final List<TransportRoute> _routes = [];
  late TransportValidation _validation = widget.validation;
  final _edited = <String>{};

  static String _routeKey(TransportRoute r) => '${r.scheduleType.wire}|${r.routeNo}';

  @override
  void initState() {
    super.initState();
    _routes.addAll(widget.parsed.routes);
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _editRoute(TransportRoute route) async {
    final updated = await showGlassModal<TransportRoute>(
      context,
      builder: (_) => _RouteEditSheet(route: route),
    );
    if (updated == null) return;
    setState(() {
      final i = _routes.indexWhere((r) => _routeKey(r) == _routeKey(route));
      if (i != -1) _routes[i] = updated;
      _edited.add(_routeKey(route));
      // Re-validate the WHOLE schedule, not just this route: e.g. clearing a
      // route number collision or fixing the last "no times" route can change
      // the overall error/warning counts shown in the summary bar and confirm
      // bar, not just this one card's badge.
      _validation = TransportImportService.validate(
          ParsedTransportSchedule(semester: widget.parsed.semester, campus: widget.parsed.campus, routes: _routes));
    });
  }

  @override
  Widget build(BuildContext context) {
    final parsed = widget.parsed;
    final bySection = <ScheduleType, List<TransportRoute>>{};
    for (final r in _routes) {
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
              subtitle: '${_routes.length} routes'
                  '${parsed.campus != null ? ' · ${parsed.campus}' : ''}',
              icon: Icons.directions_bus_filled_rounded,
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [AppColors.holoTeal, AppColors.holoBlue]),
              margin: const EdgeInsets.only(bottom: 12),
            ),
            _SummaryBar(validation: _validation),
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
                  child: _RoutePreviewCard(
                    route: route,
                    validation: _validation,
                    wasEdited: _edited.contains(_routeKey(route)),
                    onEdit: () => _editRoute(route),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            // The optional broadcast notice. Lives in the scrollable list (not the
            // pinned bar) so the keyboard can lift it into view on its own via the
            // Scaffold's default resize.
            _BroadcastMessageField(controller: _messageCtrl),
            const SizedBox(height: 12),
          ])),
          _ConfirmBar(
            validation: _validation,
            onCancel: () => Navigator.of(context).pop(null),
            onConfirm: () => Navigator.of(context).pop((
              routes: _routes,
              message: _messageCtrl.text.trim(),
              warningCount: _validation.warningCount,
            )),
          ),
        ]),
      ),
    );
  }
}

/// Free-text notice the admin/super-admin can send to the whole university along
/// with the import. Empty => the upload sends its default "schedule updated"
/// line instead.
class _BroadcastMessageField extends StatelessWidget {
  final TextEditingController controller;
  const _BroadcastMessageField({required this.controller});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.glassFill(context),
        borderRadius: AppDepth.radius(1),
        border: Border.all(color: AppColors.glassBorder(context), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.campaign_rounded, size: 18, color: AppColors.holoTeal),
          const SizedBox(width: 8),
          Text('Message to everyone (optional)',
              style: AppTextStyles.titleMedium.copyWith(
                  color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        Text('Sent as a notification to all users with this update. Leave empty to send the standard "schedule updated" notice.',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          maxLength: 240,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: AppColors.textPrimaryOf(context)),
          decoration: InputDecoration(
            hintText: 'e.g. R4 morning bus cancelled tomorrow. Check your route.',
            hintStyle: TextStyle(color: AppColors.textMutedOf(context)),
            filled: true,
            fillColor: AppColors.surfaceOf(context),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: AppDepth.radius(1), borderSide: BorderSide.none),
          ),
        ),
      ]),
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
          borderRadius: AppDepth.radius(1),
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
  final bool wasEdited;
  final VoidCallback onEdit;
  const _RoutePreviewCard({required this.route, required this.validation, required this.wasEdited, required this.onEdit});

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
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.16), borderRadius: AppDepth.radius(0)),
            child: Text(route.routeNo, style: TextStyle(color: accent, fontWeight: FontWeight.w800, fontSize: 12)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(route.routeName.isEmpty ? '(no name)' : route.routeName,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context)))),
          if (wasEdited) ...[
            const PillBadge(label: 'EDITED', color: AppColors.holoBlue),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: PillBadge(
              label: level == IssueLevel.ok ? 'OK' : level.name.toUpperCase(),
              color: accent,
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded, size: 18),
            color: AppColors.textSecondaryOf(context),
            tooltip: 'Fix this route before import',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            visualDensity: VisualDensity.compact,
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
        borderRadius: AppDepth.radius(1),
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

/// One editable trip row's live state — a plain mutable holder (not a widget)
/// so add/remove/reorder on the parent sheet's List<_EditableTrip> is simple
/// setState-driven list surgery.
class _EditableTrip {
  final TextEditingController time;
  final TextEditingController note;
  bool comingSoon;
  _EditableTrip({String? time, String? note, this.comingSoon = false})
      : time = TextEditingController(text: time ?? ''),
        note = TextEditingController(text: note ?? '');
  factory _EditableTrip.fromTrip(Trip t) =>
      _EditableTrip(time: t.time, note: t.note, comingSoon: t.isComingSoon);
  void dispose() { time.dispose(); note.dispose(); }

  /// Builds the saved [Trip]. A typed time is re-parsed through
  /// [TransportTimeParser] so "7am" / "7.00 pm" etc. normalize to the app's
  /// canonical "7:00 AM" form, same as an admin's Excel cell would — but an
  /// unparseable string is kept verbatim rather than silently dropped.
  Trip toTrip() {
    final n = note.text.trim();
    if (comingSoon) {
      return Trip(status: TripStatus.comingSoon, note: n.isEmpty ? null : n);
    }
    final raw = time.text.trim();
    if (raw.isEmpty) return Trip(note: n.isEmpty ? null : n);
    final parsed = TransportTimeParser.parseTrip(raw);
    return Trip(time: parsed.time ?? raw, note: n.isEmpty ? null : n);
  }
}

/// Full editor for one route's parsed data: name, stops (destination fixed),
/// and both directions' trips. Opened from [_RoutePreviewCard]'s edit button.
/// Pops the edited [TransportRoute] on Save, or `null` on Cancel.
class _RouteEditSheet extends StatefulWidget {
  final TransportRoute route;
  const _RouteEditSheet({required this.route});
  @override
  State<_RouteEditSheet> createState() => _RouteEditSheetState();
}

class _RouteEditSheetState extends State<_RouteEditSheet> {
  late final _nameCtrl = TextEditingController(text: widget.route.routeName);
  late final List<TextEditingController> _stops = widget.route.stops
      .where((s) => s != kCanonicalDestination)
      .map((s) => TextEditingController(text: s))
      .toList();
  late final List<_EditableTrip> _toDsc =
      widget.route.toDscTrips.where((t) => !t.isEmpty).map(_EditableTrip.fromTrip).toList();
  late final List<_EditableTrip> _fromDsc =
      widget.route.fromDscTrips.where((t) => !t.isEmpty).map(_EditableTrip.fromTrip).toList();

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _stops) { c.dispose(); }
    for (final t in _toDsc) { t.dispose(); }
    for (final t in _fromDsc) { t.dispose(); }
    super.dispose();
  }

  void _save() {
    final updated = widget.route.copyWith(
      routeName: _nameCtrl.text.trim(),
      stopsExcludingDestination:
          _stops.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList(),
      toDscTrips: _toDsc.map((t) => t.toTrip()).where((t) => !t.isEmpty).toList(),
      fromDscTrips: _fromDsc.map((t) => t.toTrip()).where((t) => !t.isEmpty).toList(),
    );
    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    // Single owner of the keyboard inset — same pattern as the transport
    // screen's stop picker sheet (showGlassModal turns GlassSheet's own lift
    // off), so several stacked text fields here don't fight the keyboard.
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 4, bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: (mq.size.height - mq.viewInsets.bottom) * 0.85),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Fix ${widget.route.routeNo}', style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
          const SizedBox(height: 2),
          Text('Corrects this route before it goes live. The source Excel is untouched.',
              style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
          const SizedBox(height: 14),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              _label(context, 'Route name'),
              _textField(context, _nameCtrl, hint: 'e.g. Dhanmondi <> DSC'),
              const SizedBox(height: 16),
              _label(context, 'Stops (in order, pickup → campus)'),
              for (var i = 0; i < _stops.length; i++)
                _StopRow(
                  controller: _stops[i],
                  index: i,
                  isFirst: i == 0,
                  isLast: i == _stops.length - 1,
                  onMoveUp: i == 0 ? null : () => setState(() {
                    final c = _stops.removeAt(i); _stops.insert(i - 1, c);
                  }),
                  onMoveDown: i == _stops.length - 1 ? null : () => setState(() {
                    final c = _stops.removeAt(i); _stops.insert(i + 1, c);
                  }),
                  onRemove: () => setState(() { _stops.removeAt(i).dispose(); }),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _stops.add(TextEditingController())),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add stop', style: TextStyle(fontSize: 12)),
                ),
              ),
              // The route's terminus is fixed by design — see kCanonicalDestination
              // — so it's shown but not editable/removable here.
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.holoTeal.withValues(alpha: 0.08),
                  borderRadius: AppDepth.radius(1),
                ),
                child: Row(children: [
                  const Icon(Icons.flag_rounded, size: 14, color: AppColors.holoTeal),
                  const SizedBox(width: 8),
                  Text('$kCanonicalDestination · destination (fixed)',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.holoTeal, fontWeight: FontWeight.w600)),
                ]),
              ),
              const SizedBox(height: 18),
              _label(context, 'To DSC — departure times'),
              for (var i = 0; i < _toDsc.length; i++)
                _TripEditRow(trip: _toDsc[i], onRemove: () => setState(() { _toDsc.removeAt(i).dispose(); })),
              OutlinedButton.icon(
                onPressed: () => setState(() => _toDsc.add(_EditableTrip())),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add time', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 18),
              _label(context, 'From DSC — departure times'),
              for (var i = 0; i < _fromDsc.length; i++)
                _TripEditRow(trip: _fromDsc[i], onRemove: () => setState(() { _fromDsc.removeAt(i).dispose(); })),
              OutlinedButton.icon(
                onPressed: () => setState(() => _fromDsc.add(_EditableTrip())),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add time', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 20),
            ]),
          ),
          Row(children: [
            Expanded(child: AfosButton(
              label: 'Cancel', outlined: true, color: textSecondary,
              onTap: () => Navigator.of(context).pop(null),
            )),
            const SizedBox(width: 12),
            Expanded(flex: 2, child: AfosButton(
              label: 'Save fix',
              color: AppColors.green,
              onTap: _save,
            )),
          ]),
          SizedBox(height: 8 + mq.padding.bottom),
        ]),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(), style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w800, letterSpacing: 0.5)),
      );

  Widget _textField(BuildContext context, TextEditingController c, {String? hint}) => TextField(
        controller: c,
        style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.textMutedOf(context)),
          isDense: true,
          filled: true,
          fillColor: AppColors.surfaceOf(context),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(borderRadius: AppDepth.radius(1), borderSide: BorderSide.none),
        ),
      );
}

class _StopRow extends StatelessWidget {
  final TextEditingController controller;
  final int index;
  final bool isFirst;
  final bool isLast;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onRemove;
  const _StopRow({
    required this.controller, required this.index, required this.isFirst, required this.isLast,
    required this.onMoveUp, required this.onMoveDown, required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
          width: 22, height: 22, alignment: Alignment.center,
          decoration: BoxDecoration(color: AppColors.holoTeal.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Text('${index + 1}', style: const TextStyle(color: AppColors.holoTeal, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(child: TextField(
          controller: controller,
          style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: isFirst ? 'Origin stop' : 'Stop name',
            hintStyle: TextStyle(color: AppColors.textMutedOf(context)),
            filled: true,
            fillColor: AppColors.surfaceOf(context),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            border: OutlineInputBorder(borderRadius: AppDepth.radius(1), borderSide: BorderSide.none),
          ),
        )),
        IconButton(
          onPressed: onMoveUp, icon: const Icon(Icons.arrow_upward_rounded, size: 16),
          padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          color: AppColors.textSecondaryOf(context), visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: onMoveDown, icon: const Icon(Icons.arrow_downward_rounded, size: 16),
          padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          color: AppColors.textSecondaryOf(context), visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: onRemove, icon: const Icon(Icons.close_rounded, size: 16),
          padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          color: AppColors.red, visualDensity: VisualDensity.compact,
        ),
      ]),
    );
  }
}

class _TripEditRow extends StatefulWidget {
  final _EditableTrip trip;
  final VoidCallback onRemove;
  const _TripEditRow({required this.trip, required this.onRemove});
  @override
  State<_TripEditRow> createState() => _TripEditRowState();
}

class _TripEditRowState extends State<_TripEditRow> {
  @override
  Widget build(BuildContext context) {
    final t = widget.trip;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.glassFill(context),
        borderRadius: AppDepth.radius(1),
        border: Border.all(color: AppColors.glassBorder(context), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(flex: 3, child: TextField(
            controller: t.time,
            enabled: !t.comingSoon,
            style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: '7:00 AM',
              hintStyle: TextStyle(color: AppColors.textMutedOf(context)),
              filled: true,
              fillColor: AppColors.surfaceOf(context),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(borderRadius: AppDepth.radius(1), borderSide: BorderSide.none),
            ),
          )),
          const SizedBox(width: 6),
          Expanded(flex: 4, child: TextField(
            controller: t.note,
            style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Note (optional)',
              hintStyle: TextStyle(color: AppColors.textMutedOf(context)),
              filled: true,
              fillColor: AppColors.surfaceOf(context),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              border: OutlineInputBorder(borderRadius: AppDepth.radius(1), borderSide: BorderSide.none),
            ),
          )),
          IconButton(
            onPressed: widget.onRemove, icon: const Icon(Icons.close_rounded, size: 16),
            padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            color: AppColors.red, visualDensity: VisualDensity.compact,
          ),
        ]),
        Row(children: [
          Checkbox(
            value: t.comingSoon,
            onChanged: (v) => setState(() => t.comingSoon = v ?? false),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 4),
          Text('Coming soon (time not set yet)',
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
        ]),
      ]),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  final TransportValidation validation;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  const _ConfirmBar({required this.validation, required this.onCancel, required this.onConfirm});
  @override
  Widget build(BuildContext context) {
    return Container(
      // No nav clearance added here: this bar is built INSIDE the screen's
      // body SafeArea (:97), which has already consumed the shell's bottom
      // inset for the whole column — so MediaQuery.padding.bottom reads 0 at
      // this point and adding it was a no-op that looked like it did something.
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context), width: 0.5)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (validation.hasErrors)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text('Some routes have errors — fix them with the edit button, or import anyway if you still want to proceed.',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.red)),
          ),
        Row(children: [
          Expanded(child: AfosButton(
            label: 'Cancel', outlined: true, color: AppColors.textSecondaryOf(context),
            onTap: onCancel,
          )),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: AfosButton(
            label: 'Confirm & Import',
            color: validation.hasErrors ? AppColors.amber : AppColors.green,
            onTap: onConfirm,
          )),
        ]),
      ]),
    );
  }
}
