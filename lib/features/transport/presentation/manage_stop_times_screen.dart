import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/error_formatter.dart';
import '../../../shared/widgets/afos_button.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/stop_offsets_repository.dart';
import '../data/stop_time_calculator.dart';

/// Admin screen for recording **per-stop bus timings** on one route.
///
/// The uploaded sheet only ever gives two numbers per route — the start time at
/// the first stop, and the departure time from campus — so the app genuinely
/// cannot say when a bus reaches a mid-route stop. This screen is where that
/// missing information gets supplied, once, as minute offsets:
///
///  * **To campus** — minutes after the route's start time (origin is 0).
///  * **From campus** — minutes after leaving DSC.
///
/// Anything left blank stays blank: the rider-facing screen then says so
/// plainly instead of showing an invented time.
class ManageStopTimesScreen extends StatefulWidget {
  final String routeNumber;
  final String scheduleType;
  final String routeName;
  final List<String> stops;
  const ManageStopTimesScreen({
    super.key,
    required this.routeNumber,
    required this.scheduleType,
    required this.routeName,
    required this.stops,
  });

  @override
  State<ManageStopTimesScreen> createState() => _ManageStopTimesScreenState();
}

class _ManageStopTimesScreenState extends State<ManageStopTimesScreen> {
  late final List<TextEditingController> _toCampus;
  late final List<TextEditingController> _fromCampus;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _toCampus = List.generate(widget.stops.length, (_) => TextEditingController());
    _fromCampus = List.generate(widget.stops.length, (_) => TextEditingController());
    // The origin is by definition 0 minutes into its own inbound run.
    if (widget.stops.isNotEmpty) _toCampus[0].text = '0';
    _load();
  }

  @override
  void dispose() {
    for (final c in _toCampus) { c.dispose(); }
    for (final c in _fromCampus) { c.dispose(); }
    super.dispose();
  }

  Future<void> _load() async {
    final existing = await StopOffsetsRepository.fetchForRoute(widget.routeNumber, widget.scheduleType);
    if (!mounted) return;
    for (var i = 0; i < widget.stops.length; i++) {
      final o = existing[widget.stops[i].toLowerCase()];
      if (o == null) continue;
      if (o.minutesFromOrigin != null) _toCampus[i].text = '${o.minutesFromOrigin}';
      if (o.minutesFromDsc != null) _fromCampus[i].text = '${o.minutesFromDsc}';
    }
    setState(() => _loading = false);
  }

  /// Fills every blank field by spreading the given total evenly across the
  /// stops — a starting point an admin can then correct, not a claim of
  /// accuracy. Deliberately does NOT overwrite values already entered.
  void _spaceEvenly(List<TextEditingController> col, int totalMinutes, {required bool inbound}) {
    final n = widget.stops.length;
    if (n < 2) return;
    for (var i = 0; i < n; i++) {
      if (col[i].text.trim().isNotEmpty) continue;
      // Inbound counts from the first stop; outbound counts from campus, which
      // sits at the END of the stored order, so it approaches in reverse.
      final step = inbound ? i : (n - 1 - i);
      col[i].text = '${(totalMinutes * step / (n - 1)).round()}';
    }
    setState(() {});
  }

  Future<void> _promptSpaceEvenly({required bool inbound}) async {
    final ctrl = TextEditingController(text: '45');
    final total = await showDialog<int>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(dialogCtx),
        title: Text(inbound ? 'Total run time to campus' : 'Total run time from campus',
            style: TextStyle(color: AppColors.textPrimaryOf(dialogCtx), fontSize: 17)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Spreads this evenly across the stops to fill the blanks. '
            'Only an estimate to start from — correct any stop afterwards.',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(dialogCtx)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: TextStyle(color: AppColors.textPrimaryOf(dialogCtx)),
            decoration: const InputDecoration(suffixText: 'minutes'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, int.tryParse(ctrl.text.trim())),
            child: const Text('Fill blanks'),
          ),
        ],
      ),
    );
    if (total != null && total > 0) {
      _spaceEvenly(inbound ? _toCampus : _fromCampus, total, inbound: inbound);
    }
  }

  int? _parse(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null || v < 0 || v > 600) return null;
    return v;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final rows = <StopOffset>[];
      for (var i = 0; i < widget.stops.length; i++) {
        rows.add(StopOffset(
          routeNumber: widget.routeNumber,
          scheduleType: widget.scheduleType,
          stopName: widget.stops[i],
          minutesFromOrigin: _parse(_toCampus[i]),
          minutesFromDsc: _parse(_fromCampus[i]),
        ));
      }
      final saved = await StopOffsetsRepository.saveRoute(rows);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(saved == 0
            ? 'Nothing to save — no timings entered yet'
            : 'Saved timings for $saved stop${saved == 1 ? '' : 's'} on ${widget.routeNumber}'),
        backgroundColor: saved == 0 ? AppColors.amber : AppColors.green,
      ));
      if (saved > 0) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.red));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: AfosAppBar(title: '${widget.routeNumber} stop times'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 24 + MediaQuery.of(context).padding.bottom),
              children: [
                FeatureHeader(
                  title: 'Stop timings',
                  subtitle: 'Minutes from the start of each leg. The sheet only gives the route\'s '
                      'start time and its campus departure — these offsets are what let riders see '
                      'the time at their own stop. Leave a stop blank if you don\'t know it.',
                  icon: Icons.more_time_rounded,
                  accent: AppColors.holoTeal,
                  margin: const EdgeInsets.fromLTRB(0, 16, 0, 12),
                ),
                Text(widget.routeName, style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => _promptSpaceEvenly(inbound: true),
                    icon: const Icon(Icons.school_rounded, size: 15),
                    label: const Text('Fill to-campus', style: TextStyle(fontSize: 12)),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () => _promptSpaceEvenly(inbound: false),
                    icon: const Icon(Icons.home_rounded, size: 15),
                    label: const Text('Fill from-campus', style: TextStyle(fontSize: 12)),
                  )),
                ]),
                const SizedBox(height: 12),
                for (var i = 0; i < widget.stops.length; i++)
                  SurfaceCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          width: 26, height: 26,
                          decoration: BoxDecoration(
                              color: AppColors.holoTeal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8)),
                          child: Center(child: Text('${i + 1}',
                              style: const TextStyle(
                                  color: AppColors.holoTeal, fontSize: 12, fontWeight: FontWeight.bold))),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(widget.stops[i],
                            style: AppTextStyles.bodyMedium.copyWith(
                                color: textPrimary, fontWeight: FontWeight.w600))),
                        if (i == 0)
                          Text('origin', style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _MinuteField(
                          controller: _toCampus[i],
                          label: 'To campus',
                          accent: AppColors.holoTeal,
                          enabled: i != 0, // origin is always 0
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _MinuteField(
                          controller: _fromCampus[i],
                          label: 'From campus',
                          accent: AppColors.holoBlue,
                        )),
                      ]),
                    ]),
                  ),
                const SizedBox(height: 8),
                AfosButton(
                  label: 'Save timings',
                  icon: Icons.save_rounded,
                  loading: _saving,
                  onTap: _saving ? null : _save,
                ),
              ],
            ),
    );
  }
}

class _MinuteField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final Color accent;
  final bool enabled;
  const _MinuteField({
    required this.controller,
    required this.label,
    required this.accent,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
      style: TextStyle(color: AppColors.textPrimaryOf(context), fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: accent, fontSize: 12),
        suffixText: 'min',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent.withValues(alpha: 0.35)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
