import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/utils/location_helper.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/supernova_loader.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/transport_repository.dart';

/// Parses "10:50 AM" / "4:20 PM" style time strings (as stored in
/// transport_routes.to_dsc_times/from_dsc_times) into minutes-since-midnight.
/// Returns null for anything unparseable rather than throwing -- source
/// data is PDF-extracted and not perfectly uniform.
int? _parseTimeToMinutes(String raw) {
  final m = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM|am|pm)?').firstMatch(raw.trim());
  if (m == null) return null;
  var hour = int.parse(m.group(1)!);
  final minute = int.parse(m.group(2)!);
  final ampm = m.group(3)?.toUpperCase();
  if (ampm == 'PM' && hour != 12) hour += 12;
  if (ampm == 'AM' && hour == 12) hour = 0;
  return hour * 60 + minute;
}

typedef _NextTrip = ({String time, int minutesUntil, bool isTomorrow});

/// Finds the next upcoming departure in [times] relative to [nowMinutes],
/// wrapping to tomorrow's first departure if everything today has passed.
_NextTrip? _nextDeparture(List<String> times, int nowMinutes) {
  final parsed = times
      .map((t) => (raw: t, min: _parseTimeToMinutes(t)))
      .where((e) => e.min != null)
      .toList()
    ..sort((a, b) => a.min!.compareTo(b.min!));
  if (parsed.isEmpty) return null;
  final upcoming = parsed.where((e) => e.min! >= nowMinutes);
  if (upcoming.isNotEmpty) {
    final next = upcoming.first;
    return (time: next.raw, minutesUntil: next.min! - nowMinutes, isTomorrow: false);
  }
  final first = parsed.first;
  return (time: first.raw, minutesUntil: (24 * 60 - nowMinutes) + first.min!, isTomorrow: true);
}

// Uses stop *names* for origin/destination/waypoints rather than lat/long
// — the source routine sheet never has GPS coordinates for stops (only
// names), so this works even when the in-app map has no path to draw,
// which is most routes today.
Future<void> _openInGoogleMaps(List<String> stopNames) async {
  final origin = Uri.encodeComponent('${stopNames.first}, Dhaka, Bangladesh');
  final destination = Uri.encodeComponent('${stopNames.last}, Dhaka, Bangladesh');
  final middle = stopNames.length > 2 ? stopNames.sublist(1, stopNames.length - 1) : const <String>[];
  final waypoints = middle.map((s) => Uri.encodeComponent('$s, Dhaka, Bangladesh')).join('|');
  final url = Uri.parse('https://www.google.com/maps/dir/?api=1'
      '&origin=$origin&destination=$destination'
      '${waypoints.isNotEmpty ? '&waypoints=$waypoints' : ''}&travelmode=driving');
  await launchUrl(url, mode: LaunchMode.externalApplication);
}

class TransportScreen extends StatefulWidget {
  const TransportScreen({super.key});
  @override State<TransportScreen> createState() => _TransportState();
}

class _TransportState extends State<TransportScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _repo = TransportRepository();
  String? _selectedRouteId;
  // Created once and reused across rebuilds -- calling _repo.watchRoutes()/
  // watchLiveStatus() fresh inline inside build() (as StreamBuilder's
  // `stream:` argument) handed a brand new Stream to StreamBuilder on every
  // unrelated setState (e.g. _viewOnMap), which raced the old subscription's
  // teardown against the new one's setup and could throw "Bad state: Stream
  // has already been listened to." (same root cause fixed in
  // schedule_screen.dart's _classesStream()).
  late final Stream<List<Map<String,dynamic>>> _routesStream = _repo.watchRoutes();
  late final Stream<Map<String, Map<String, dynamic>>> _liveStatusStream = _repo.watchLiveStatus();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length:4,vsync:this);
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  void _viewOnMap(String routeId) {
    setState(() => _selectedRouteId = routeId);
    _tab.animateTo(3);
  }

  static const _tabLabels = ['Find Route', 'My Route', 'All Routes', 'Map'];
  static const _tabIcons = [Icons.alt_route_rounded, Icons.person_pin_circle_rounded, Icons.list_alt_rounded, Icons.map_rounded];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar:const AfosAppBar(title:'Transport'),
      body:Column(children:[
        Expanded(child: StreamBuilder<List<Map<String,dynamic>>>(
          stream: _routesStream,
          builder: (ctx, snap) {
            final loading = snap.connectionState==ConnectionState.waiting;
            final routes = snap.data ?? const <Map<String,dynamic>>[];
            return StreamBuilder<Map<String, Map<String, dynamic>>>(
              stream: _liveStatusStream,
              builder: (ctx2, statusSnap) {
                final liveStatus = statusSnap.data ?? const <String, Map<String, dynamic>>{};
                final liveCount = liveStatus.values.where((s) => s['status'] != 'departed' && s['status'] != 'cancelled').length;
                return Column(children: [
                  FeatureHeader(
                    title: 'Campus Transport',
                    subtitle: loading ? 'Loading routes…' : '${routes.length} routes available',
                    icon: Icons.directions_bus_filled_rounded,
                    gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                        colors: [AppColors.holoTeal, AppColors.holoBlue]),
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    trailing: (!loading && liveCount > 0)
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                            child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Text('$liveCount', textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                                  style: const TextStyle(color: Colors.white, fontSize: 20, height: 1.0, fontWeight: FontWeight.w800)),
                              Text('live now', textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                                  style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 10, height: 1.0)),
                            ]),
                          )
                        : null,
                  ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.06, curve: Curves.easeOutCubic),
                  AnimatedBuilder(
                    animation: _tab,
                    builder: (ctx3, _) => GlassTabBar(
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      currentIndex: _tab.index,
                      onChanged: (i) => _tab.animateTo(i),
                      tabs: [
                        for (var i = 0; i < _tabLabels.length; i++)
                          GlassTab(_tabLabels[i], icon: _tabIcons[i]),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(child: TabBarView(controller:_tab,children:[
                    loading?const Padding(padding:EdgeInsets.all(16),child:ShimmerList()):_FindRouteTab(routes:routes, liveStatus: liveStatus),
                    loading?const Padding(padding:EdgeInsets.all(16),child:ShimmerList()):_MyRouteTab(routes:routes, liveStatus: liveStatus),
                    loading?const Padding(padding:EdgeInsets.all(16),child:ShimmerList()):_AllRoutesTab(routes:routes, liveStatus: liveStatus, repo: _repo, onViewOnMap: _viewOnMap),
                    _MapTab(selectedRouteId: _selectedRouteId, repo: _repo),
                  ])),
                ]);
              },
            );
          },
        )),
      ]),
    );
  }
}

/// on_time=green, delayed=amber (+minutes), departed=grey, cancelled=red.
/// Renders nothing if there's no live status row for the route yet.
class _LiveStatusBadge extends StatelessWidget {
  final Map<String, dynamic>? status;
  const _LiveStatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    if (status == null) return const SizedBox.shrink();
    final s = status!['status'] as String? ?? 'on_time';
    final delay = status!['delay_minutes'] as int? ?? 0;
    final (color, label) = switch (s) {
      'delayed' => (AppColors.amber, delay > 0 ? 'Delayed ${delay}m' : 'Delayed'),
      'departed' => (AppColors.textMuted, 'Departed'),
      'cancelled' => (AppColors.red, 'Cancelled'),
      _ => (AppColors.green, 'On time'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha:0.15), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha:0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Lets a user pick where they are and where they want to go, then shows
/// every route whose stop list contains both stops — a route's `stops` array
/// is stored in a single fixed physical order, but the bus itself runs both
/// directions along it (see to_dsc_times/from_dsc_times), so which stop
/// happens to come first in that stored order says nothing about whether
/// the trip is possible.
class _FindRouteTab extends StatefulWidget {
  final List<Map<String,dynamic>> routes;
  final Map<String, Map<String, dynamic>> liveStatus;
  const _FindRouteTab({required this.routes, required this.liveStatus});
  @override State<_FindRouteTab> createState() => _FindRouteTabState();
}

class _FindRouteTabState extends State<_FindRouteTab> {
  String? _from, _to;

  List<String> get _stopNames {
    final names = <String>{};
    for (final r in widget.routes) {
      final stops = (r['stops'] as List?) ?? const [];
      for (final s in stops) {
        final name = (s as Map)['name'] as String?;
        if (name != null && name.isNotEmpty) names.add(name);
      }
    }
    final list = names.toList()..sort();
    return list;
  }

  List<_RouteMatch> get _matches {
    if (_from == null || _to == null || _from == _to) return const [];
    final results = <_RouteMatch>[];
    for (final r in widget.routes) {
      final stops = ((r['stops'] as List?) ?? const [])
          .cast<Map>().map((s) => s['name'] as String?).toList();
      final fromIdx = stops.indexWhere((s) => s == _from);
      final toIdx = stops.indexWhere((s) => s == _to);
      if (fromIdx == -1 || toIdx == -1) continue;
      // The sheet gives per-trip times to/from DSC, not per-stop times, so
      // we surface the route's daily trip schedule rather than a single
      // board/arrive time we don't actually have data for.
      final toDsc = ((r['to_dsc_times'] as List?) ?? const []).cast<String>();
      final fromDsc = ((r['from_dsc_times'] as List?) ?? const []).cast<String>();
      results.add((
        routeId: r['id'] as String,
        routeNumber: r['route_number'] as String? ?? '?',
        routeName: r['route_name'] as String? ?? 'Route',
        toDsc: toDsc,
        fromDsc: fromDsc,
      ));
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final stopNames = _stopNames;
    if (stopNames.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.signpost_outlined, size: 40, color: textSecondary),
        const SizedBox(height: 12),
        Text('No stop data uploaded yet', textAlign: TextAlign.center, style: TextStyle(color: textSecondary)),
      ])));
    }
    final matches = _matches;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Where are you, and where are you going?',
          style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.borderOf(context), width: 0.6)),
        child: Column(children: [
          _StopDropdown(label: 'From', icon: Icons.trip_origin_rounded, value: _from, options: stopNames,
              onChanged: (v) => setState(() => _from = v)),
          Row(children: [
            const SizedBox(width: 30),
            Expanded(child: Divider(height: 1, color: AppColors.borderOf(context))),
            GestureDetector(
              onTap: () => setState(() { final t = _from; _from = _to; _to = t; }),
              child: Container(margin: const EdgeInsets.symmetric(horizontal: 10),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: AppColors.holoTeal.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: const Icon(Icons.swap_vert_rounded, size: 16, color: AppColors.holoTeal)),
            ),
            Expanded(child: Divider(height: 1, color: AppColors.borderOf(context))),
            const SizedBox(width: 30),
          ]),
          _StopDropdown(label: 'To', icon: Icons.location_on_rounded, value: _to, options: stopNames,
              onChanged: (v) => setState(() => _to = v)),
        ]),
      ),
      const SizedBox(height: 20),
      if (_from != null && _to != null && _from == _to)
        Text('Pick two different stops', style: TextStyle(color: textSecondary))
      else if (_from != null && _to != null && matches.isEmpty)
        Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.route_outlined, size: 34, color: textSecondary),
          const SizedBox(height: 10),
          Text('No route covers that trip', style: TextStyle(color: textSecondary)),
        ])))
      else
        ...matches.map((m) => SurfaceCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 40, height: 40,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [AppColors.holoTeal, AppColors.holoBlue]),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [BoxShadow(color: AppColors.holoTeal.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 2))]),
              child: Center(child: Text(m.routeNumber,
                  textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                  style: const TextStyle(color: Colors.white, height: 1.0, fontWeight: FontWeight.bold)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(m.routeName, style: AppTextStyles.titleMedium.copyWith(color: textPrimary), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                _LiveStatusBadge(status: widget.liveStatus[m.routeId]),
              ]),
              Text('$_from → $_to', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
              const SizedBox(height: 6),
              if (m.toDsc.isNotEmpty) _TimeChipsRow(label: 'To DSC', times: m.toDsc),
              if (m.fromDsc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
                  child: _TimeChipsRow(label: 'From DSC', times: m.fromDsc)),
            ])),
          ]),
        )),
    ]);
  }
}

typedef _RouteMatch = ({String routeId, String routeNumber, String routeName, List<String> toDsc, List<String> fromDsc});

class _TimeChipsRow extends StatelessWidget {
  final String label; final List<String> times;
  const _TimeChipsRow({required this.label, required this.times});
  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 62, child: Text(label,
          style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w600))),
      Expanded(child: Wrap(spacing: 6, runSpacing: 4, children: times.map((t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppColors.holoTeal.withValues(alpha:0.1), borderRadius: BorderRadius.circular(8)),
          child: Text(t, style: const TextStyle(fontSize: 11, color: AppColors.holoTeal)))).toList())),
    ]);
  }
}

class _StopDropdown extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  const _StopDropdown({required this.label, required this.icon, required this.value, required this.options, required this.onChanged});
  @override
  // Was a DropdownButtonFormField relying on Material's floating-label
  // InputDecorator -- several rounds of contentPadding tweaks still left the
  // label/value text sitting hard against the left edge (an
  // EdgeInsets.only(top:..,bottom:..) leaves left/right at zero, and the
  // decorator's internal label layout doesn't respect the icon+gap that
  // precedes it in the Row the way a plain block layout would). Rebuilt on
  // a plain DropdownButton with an always-visible label above it instead of
  // a floating one -- full explicit control over every side's spacing, no
  // InputDecorator internals to fight.
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        Container(width: 36, height: 36, alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.holoTeal.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: AppColors.holoTeal)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
              style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 10.5, height: 1.0,
                  fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          const SizedBox(height: 5),
          DropdownButtonHideUnderline(child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            isDense: true,
            hint: Text('Select a stop', style: TextStyle(color: AppColors.textMutedOf(context), fontSize: 15)),
            dropdownColor: AppColors.surfaceOf(context),
            style: TextStyle(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w600, fontSize: 15),
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondaryOf(context)),
            items: options.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: onChanged,
          )),
        ])),
      ]),
    );
  }
}

class _MyRouteTab extends StatefulWidget {
  final List<Map<String,dynamic>> routes;
  final Map<String, Map<String, dynamic>> liveStatus;
  const _MyRouteTab({required this.routes, required this.liveStatus});
  @override State<_MyRouteTab> createState() => _MyRouteTabState();
}

class _MyRouteTabState extends State<_MyRouteTab> {
  String? _selectedRoute;
  bool _autoSuggested = false;
  Timer? _tickTimer;

  // No stop in transport_stops has ever had a real GPS coordinate (the
  // source routine sheet only ever lists stop *names* -- confirmed live,
  // 0 of 174 rows have latitude/longitude). True "nearest stop by distance"
  // isn't possible on this data, so this matches the user's *registered*
  // address text against route/stop names instead -- an honest, disclosed
  // approximation, not a silent guess dressed up as GPS proximity.
  Future<void> _suggestFromAddress() async {
    final uid = SupabaseConfig.uid;
    if (uid == null) return;
    try {
      final p = await SupabaseConfig.client.from('profiles')
          .select('permanent_thana, permanent_upazila, permanent_district')
          .eq('id', uid).maybeSingle();
      if (p == null) return;
      final needles = [p['permanent_thana'], p['permanent_upazila'], p['permanent_district']]
          .whereType<String>().where((s) => s.isNotEmpty).map((s) => s.toLowerCase()).toList();
      if (needles.isEmpty) return;
      for (final r in widget.routes) {
        final haystack = ('${r['route_name'] as String? ?? ''} ${((r['stops'] as List?) ?? const []).cast<Map>().map((s) => s['name'] as String? ?? '').join(' ')}')
            .toLowerCase();
        if (needles.any((n) => haystack.contains(n))) {
          if (mounted) setState(() { _selectedRoute = r['id'] as String; _autoSuggested = true; });
          return;
        }
      }
    } catch (_) {
      // Best-effort suggestion only -- the manual dropdown always still works.
    }
  }

  @override
  void initState() {
    super.initState();
    _suggestFromAddress();
    // Drives the "next bus in Xm" countdown so it advances live without a
    // manual refresh, same pattern as the dashboard's class status card.
    _tickTimer = Timer.periodic(const Duration(minutes: 1), (_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _tickTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if(widget.routes.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.directions_bus_outlined, size: 40, color: AppColors.textSecondaryOf(context)),
        const SizedBox(height: 12),
        Text('No routes available', style: TextStyle(color: AppColors.textSecondaryOf(context))),
      ])));
    }
    final selected = widget.routes.where((r) => r['id'] == _selectedRoute).firstOrNull;
    final stops = ((selected?['stops'] as List?) ?? const []).cast<Map>().map((s) => s['name'] as String? ?? '').where((s) => s.isNotEmpty).toList();
    final toDsc = ((selected?['to_dsc_times'] as List?) ?? const []).cast<String>();
    final fromDsc = ((selected?['from_dsc_times'] as List?) ?? const []).cast<String>();
    return ListView(padding:const EdgeInsets.all(16),children:[
      Text('Select your route',
          style:AppTextStyles.headlineLarge.copyWith(color:AppColors.textPrimaryOf(context))),
      if (_autoSuggested && selected != null) ...[
        const SizedBox(height: 4),
        Text('Suggested based on your registered address — pick a different one if this isn\'t right.',
            style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context))),
      ],
      const SizedBox(height:12),
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderOf(context), width: 0.6)),
        child: Row(children: [
          Container(width: 36, height: 36, alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.holoTeal.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: const Icon(Icons.directions_bus_filled_rounded, size: 18, color: AppColors.holoTeal)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ROUTE', textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 10.5, height: 1.0,
                    fontWeight: FontWeight.w700, letterSpacing: 0.6)),
            const SizedBox(height: 5),
            DropdownButtonHideUnderline(child: DropdownButton<String>(
              value: _selectedRoute,
              isExpanded: true,
              isDense: true,
              hint: Text('Choose route', style: TextStyle(color: AppColors.textMutedOf(context), fontSize: 15)),
              dropdownColor: AppColors.surfaceOf(context),
              style: TextStyle(color: AppColors.textPrimaryOf(context), fontWeight: FontWeight.w600, fontSize: 15),
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondaryOf(context)),
              items: widget.routes.map((r) => DropdownMenuItem(value: r['id'] as String,
                  child: Text('${r['route_number']} — ${r['route_name'] ?? 'Route'}', overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() { _selectedRoute = v; _autoSuggested = false; }),
            )),
          ])),
        ]),
      ),
      if(selected!=null) ...[
        const SizedBox(height:16),
        Row(children: [
          _LiveStatusBadge(status: widget.liveStatus[selected['id']]),
        ]),
        const SizedBox(height:8),
        if (toDsc.isNotEmpty || fromDsc.isNotEmpty) ...[
          _NextDepartureCard(toDsc: toDsc, fromDsc: fromDsc),
          const SizedBox(height: 12),
        ],
        if (stops.isNotEmpty) Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.alt_route_rounded, size: 14, color: AppColors.holoTeal),
                const SizedBox(width: 6),
                Text('ROUTE PATH', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              ]),
              const SizedBox(height: 8),
              Text(stops.join('  →  '), style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimaryOf(context))),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                  onPressed: () => _openInGoogleMaps(stops),
                  icon: const Icon(Icons.directions_rounded, size: 18),
                  label: const Text('Open in Google Maps'))),
            ])),
        const SizedBox(height: 16),
        if (toDsc.isNotEmpty) _ScheduleCard(title: 'Departure Times (To DSC)', times: toDsc),
        if (fromDsc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12),
            child: _ScheduleCard(title: 'Departure Times (From DSC)', times: fromDsc)),
        if (toDsc.isEmpty && fromDsc.isEmpty) Text('No trip times uploaded for this route yet',
            style: TextStyle(color: AppColors.textSecondaryOf(context))),
      ],
    ]);
  }
}

/// Live "next bus" countdown in both directions for the selected route,
/// re-evaluated every minute (see _MyRouteTabState's _tickTimer) so it
/// advances to the following trip once the current one's time passes,
/// wrapping to tomorrow's first departure once today's are all gone.
class _NextDepartureCard extends StatelessWidget {
  final List<String> toDsc; final List<String> fromDsc;
  const _NextDepartureCard({required this.toDsc, required this.fromDsc});

  String _fmt(_NextTrip n) {
    final rel = n.minutesUntil < 60 ? '${n.minutesUntil}m' : '${n.minutesUntil ~/ 60}h ${n.minutesUntil % 60}m';
    return '${n.time} (${n.isTomorrow ? 'tomorrow, ' : ''}in $rel)';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final nextTo = _nextDeparture(toDsc, nowMin);
    final nextFrom = _nextDeparture(fromDsc, nowMin);
    if (nextTo == null && nextFrom == null) return const SizedBox.shrink();
    final textPrimary = AppColors.textPrimaryOf(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.holoTeal.withValues(alpha: 0.15), AppColors.holoBlue.withValues(alpha: 0.08)]),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.holoTeal.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.directions_bus_filled_rounded, color: AppColors.holoTeal, size: 18),
          SizedBox(width: 8),
          Text('NEXT BUS', style: TextStyle(
              color: AppColors.holoTeal, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ]),
        const SizedBox(height: 10),
        if (nextTo != null) Text('To DSC: ${_fmt(nextTo)}', style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
        if (nextTo != null && nextFrom != null) const SizedBox(height: 4),
        if (nextFrom != null) Text('From DSC: ${_fmt(nextFrom)}', style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
      ]),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  final String title; final List<String> times;
  const _ScheduleCard({required this.title, required this.times});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        ...times.map((t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
          Icon(Icons.access_time, color: AppColors.textSecondaryOf(context), size: 16),
          const SizedBox(width: 10),
          Text(t, style: AppTextStyles.titleMedium.copyWith(color: AppColors.textPrimaryOf(context))),
        ]))),
      ]),
    );
  }
}

class _AllRoutesTab extends StatelessWidget {
  final List<Map<String,dynamic>> routes;
  final Map<String, Map<String, dynamic>> liveStatus;
  final TransportRepository repo;
  final ValueChanged<String> onViewOnMap;
  const _AllRoutesTab({required this.routes, required this.liveStatus, required this.repo, required this.onViewOnMap});

  void _showRouteDetail(BuildContext context, Map<String,dynamic> route) {
    final toDsc = ((route['to_dsc_times'] as List?) ?? const []).cast<String>();
    final fromDsc = ((route['from_dsc_times'] as List?) ?? const []).cast<String>();
    final stopNames = ((route['stops'] as List?) ?? const []).cast<Map>().map((s) => s['name'] as String? ?? '').where((s) => s.isNotEmpty).toList();
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: AppColors.surfaceOf(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetCtx) => DraggableScrollableSheet(
            initialChildSize: 0.6, minChildSize: 0.3, maxChildSize: 0.9, expand: false,
            builder: (_, scrollCtrl) => SingleChildScrollView(controller: scrollCtrl,
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${route['route_number']} — ${route['route_name'] ?? 'Route'}',
                        style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx)))),
                    _LiveStatusBadge(status: liveStatus[route['id']]),
                  ]),
                  const SizedBox(height: 16),
                  if (stopNames.isNotEmpty) ...[
                    Text('Stops', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(sheetCtx), fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(stopNames.join('  →  '), style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
                    const SizedBox(height: 16),
                  ],
                  if (toDsc.isNotEmpty) _ScheduleCard(title: 'Departure Times (To DSC)', times: toDsc),
                  if (fromDsc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12),
                      child: _ScheduleCard(title: 'Departure Times (From DSC)', times: fromDsc)),
                  if (toDsc.isEmpty && fromDsc.isEmpty && stopNames.isEmpty)
                    Text('No trip data uploaded for this route yet', style: TextStyle(color: AppColors.textSecondaryOf(sheetCtx))),
                  const SizedBox(height: 24),
                  SizedBox(width: double.infinity, child: FilledButton.icon(
                      onPressed: () { Navigator.pop(sheetCtx); onViewOnMap(route['id'] as String); },
                      icon: const Icon(Icons.map_rounded, size: 18),
                      label: const Text('View on Map'))),
                  if (stopNames.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(width: double.infinity, child: OutlinedButton.icon(
                        onPressed: () => _openInGoogleMaps(stopNames),
                        icon: const Icon(Icons.directions_rounded, size: 18),
                        label: const Text('Open in Google Maps'))),
                  ],
                ]))));
  }

  @override
  Widget build(BuildContext context) {
    if(routes.isEmpty) {
      return Center(
        child:Text('No routes',style:TextStyle(color:AppColors.textSecondaryOf(context))));
    }
    return ListView.builder(padding:const EdgeInsets.all(16),itemCount:routes.length,
      itemBuilder:(ctx,i){
        final r = routes[i];
        final stops = ((r['stops'] as List?) ?? const []).cast<Map>().map((s) => s['name'] as String? ?? '').where((s) => s.isNotEmpty).toList();
        final toDsc = ((r['to_dsc_times'] as List?) ?? const []).cast<String>();
        final subtitle = stops.isNotEmpty
            ? '${stops.first} → ${stops.last} (${stops.length} stops)'
            : toDsc.isNotEmpty ? '${toDsc.length} trips/day' : 'No trip data yet';
        return Padding(padding: const EdgeInsets.only(bottom:12), child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showRouteDetail(ctx, r),
            child: RepaintBoundary(
              child: Container(
                padding: const EdgeInsets.all(1.2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [AppColors.holoTeal.withValues(alpha: AppColors.isDark(context) ? 0.3 : 0.2),
                               AppColors.holoBlue.withValues(alpha: 0.12)]),
                ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(15)),
                  child: Row(children: [
                    Container(width: 44, height: 44,
                        decoration: BoxDecoration(
                            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                                colors: [AppColors.holoTeal.withValues(alpha: 0.85), AppColors.holoBlue.withValues(alpha: 0.65)]),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [BoxShadow(color: AppColors.holoTeal.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]),
                        child: Center(child: Text(r['route_number']??'?',
                            textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                            style: const TextStyle(color: Colors.white, height: 1.0, fontWeight: FontWeight.w800, fontSize: 15)))),
                    const SizedBox(width:12),
                    Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                      Row(children: [
                        Expanded(child: Text(r['route_name']??'',style:AppTextStyles.titleMedium.copyWith(color:AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 6),
                        _LiveStatusBadge(status: liveStatus[r['id']]),
                      ]),
                      const SizedBox(height: 2),
                      Row(children: [
                        Icon(Icons.route_rounded, size: 12, color: AppColors.textSecondaryOf(context)),
                        const SizedBox(width: 4),
                        Expanded(child: Text(subtitle,style:AppTextStyles.bodyMedium.copyWith(color:AppColors.textSecondaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      ]),
                    ])),
                    Icon(Icons.chevron_right,color:AppColors.textSecondaryOf(context)),
                  ]),
                ),
              ),
            ),
          ),
        )).animate(delay: Duration(milliseconds: i * 50))
            .fadeIn(curve: Curves.easeOutCubic).slideY(begin: 0.05, curve: Curves.easeOutCubic);
      });
  }
}

class _MapTab extends StatefulWidget {
  final String? selectedRouteId;
  final TransportRepository repo;
  const _MapTab({required this.selectedRouteId, required this.repo});
  @override State<_MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<_MapTab> {
  static const _diuLat = 23.7953, _diuLng = 90.4044;
  final _mapController = MapController();
  LatLng? _myLocation;
  String? _locationError;
  bool _requestingLocation = false;
  List<Map<String,dynamic>>? _stops;
  bool _loadingStops = false;

  @override
  void initState() { super.initState(); _enableLocation(); _loadStops(); }

  @override
  void didUpdateWidget(covariant _MapTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedRouteId != widget.selectedRouteId) _loadStops();
  }

  @override
  void dispose() { _mapController.dispose(); super.dispose(); }

  Future<void> _loadStops() async {
    final routeId = widget.selectedRouteId;
    if (routeId == null) { if (mounted) setState(() => _stops = null); return; }
    setState(() => _loadingStops = true);
    try {
      final stops = await widget.repo.fetchStops(routeId);
      if (mounted) setState(() { _stops = stops; _loadingStops = false; });
    } catch (_) {
      if (mounted) setState(() { _stops = []; _loadingStops = false; });
    }
  }

  List<LatLng> get _routePoints => (_stops ?? const [])
      .where((s) => s['latitude'] != null && s['longitude'] != null)
      .map((s) => LatLng((s['latitude'] as num).toDouble(), (s['longitude'] as num).toDouble()))
      .toList();

  /// Asks for the device's live position so the user can see where they
  /// are relative to campus/routes on the map, instead of a static view.
  Future<void> _enableLocation() async {
    setState(() { _requestingLocation = true; _locationError = null; });
    final pos = await LocationHelper.getCurrentPosition(
        onError: (msg) { if (mounted) setState(() { _locationError = msg; _requestingLocation = false; }); });
    if (pos == null || !mounted) return;
    setState(() { _myLocation = LatLng(pos.latitude, pos.longitude); _requestingLocation = false; });
    _mapController.move(_myLocation!, 15);
  }

  @override
  Widget build(BuildContext context) {
    final routePoints = _routePoints;
    final showNoPathNote = widget.selectedRouteId != null && !_loadingStops && routePoints.length < 2;
    return Stack(children: [
      FlutterMap(
        mapController: _mapController,
        options: const MapOptions(
          initialCenter:LatLng(_diuLat,_diuLng), initialZoom:14),
        children:[
          TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName:'com.example.afos_v7'),
          if (routePoints.length >= 2) PolylineLayer(polylines: [
            Polyline(points: routePoints, strokeWidth: 4, color: AppColors.holoTeal),
          ]),
          MarkerLayer(markers:[
            const Marker(point:LatLng(_diuLat,_diuLng), width:40, height:40,
              child:Icon(Icons.school_rounded,color:AppColors.holoBlue,size:36)),
            ...routePoints.map((p) => Marker(point: p, width: 14, height: 14,
                child: Container(decoration: BoxDecoration(
                    color: AppColors.holoTeal, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2))))),
            if (_myLocation != null) Marker(point: _myLocation!, width: 26, height: 26,
                child: Container(decoration: BoxDecoration(
                    color: AppColors.holoTeal, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [BoxShadow(color: AppColors.holoTeal.withValues(alpha:0.5), blurRadius: 10, spreadRadius: 2)]))),
          ]),
        ],
      ),
      Positioned(right: 16, bottom: 16, child: FloatingActionButton(
          heroTag: 'my_location_fab',
          backgroundColor: AppColors.surfaceOf(context),
          onPressed: _requestingLocation ? null : _enableLocation,
          child: _requestingLocation
              ? const SupernovaLoader(size: 20, color: AppColors.holoTeal)
              : const Icon(Icons.my_location_rounded, color: AppColors.holoTeal))),
      if (_locationError != null) Positioned(left: 16, right: 90, top: 16, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderOf(context))),
          child: Text(_locationError!, style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context))))),
      if (showNoPathNote) Positioned(left: 16, right: 16, bottom: 90, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderOf(context))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.info_outline_rounded, size: 16, color: AppColors.textSecondaryOf(context)),
            const SizedBox(width: 8),
            Expanded(child: Text('Route path not available yet for this route',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondaryOf(context)))),
          ]))),
    ]);
  }
}
