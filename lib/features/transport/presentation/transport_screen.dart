import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../core/auth/role_session.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/location_helper.dart';
import '../../../shared/widgets/feature_header.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/glass_tab_bar.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/supernova_loader.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/models/transport_schedule.dart';
import '../data/repositories/transport_repository.dart';
import '../data/stop_offsets_repository.dart';
import '../data/stop_time_calculator.dart';
import 'manage_stop_times_screen.dart';

import '../../../shared/widgets/glass_bottom_nav.dart';
/// Reads a route row's per-trip objects ({time, note, status}) for one
/// direction into typed [Trip]s, dropping blanks.
List<Trip> _tripsOf(Map r, String key) =>
    (((r[key] as List?) ?? const [])
        .map((e) => Trip.fromJson(Map<String, dynamic>.from(e as Map)))
        .where((t) => !t.isEmpty)
        .toList());

/// Parses "10:50 AM" / "4:20 PM" style time strings into minutes-since-midnight.
/// Returns null for anything unparseable (e.g. a coming-soon trip) rather than
/// throwing -- source data is imported and not perfectly uniform.
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
_NextTrip? _nextDeparture(List<Trip> trips, int nowMinutes) {
  final parsed = trips
      .where((t) => t.time != null)
      .map((t) => (raw: t.time!, min: _parseTimeToMinutes(t.time!)))
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
/// Strips any stray "<"/">" separator characters that leaked into a stored
/// stop name (older imports split inconsistent delimiters imperfectly), so no
/// delimiter can ever reach a rendered widget even for pre-existing DB rows.
String _cleanStop(String s) => s.replaceAll(RegExp(r'[<>]'), '').trim();

/// Friendly message shown for a trip slot the admin hasn't finalized yet (a
/// "Coming Soon" cell) — never a blank cell or an error.
const String _kSoonMsg = 'Time being updated — check back soon';

/// Display form of a stored route name: turn the raw "<>"/">" separators into a
/// clean "›" and normalize the "DSC" shorthand to the single canonical
/// destination ([kCanonicalDestination]) so a route title never disagrees with
/// the stop list / pickers, which already only ever show "Daffodil Smart City".
String _displayRouteName(String raw) {
  var s = raw.replaceAll(RegExp(r'\s*[<>]+\s*'), ' › ');
  s = s.replaceAll(RegExp(r'\bDSC\b', caseSensitive: false), kCanonicalDestination);
  return s.trim();
}

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

typedef _PickerOption<T> = ({String label, T value});

/// Opens a floating glass bottom-sheet picker with a **searchable** list —
/// replaces the cramped Material `DropdownButton` overlay, which positions
/// badly and is painful for the 170+ transport stops. Returns the chosen
/// value, or null if dismissed.
Future<T?> _showOptionPicker<T>(BuildContext context, {
  required String title,
  required List<_PickerOption<T>> options,
  T? selected,
}) => showGlassSheet<T>(context, child: _PickerSheet<T>(title: title, options: options, selected: selected));

class _PickerSheet<T> extends StatefulWidget {
  final String title;
  final List<_PickerOption<T>> options;
  final T? selected;
  const _PickerSheet({required this.title, required this.options, required this.selected});
  @override State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.options
        : widget.options.where((o) => o.label.toLowerCase().contains(q)).toList();
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.title, style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
        const SizedBox(height: 12),
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          style: TextStyle(color: textPrimary),
          decoration: InputDecoration(
            hintText: 'Search…',
            hintStyle: TextStyle(color: textSecondary),
            prefixIcon: Icon(Icons.search_rounded, color: textSecondary),
            filled: true, fillColor: AppColors.glassFill(context),
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 8),
        Flexible(child: filtered.isEmpty
          ? Padding(padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(child: Text('No matches', style: TextStyle(color: textSecondary))))
          : ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final o = filtered[i];
                final sel = o.value == widget.selected;
                return ListTile(
                  dense: true,
                  title: Text(o.label, overflow: TextOverflow.ellipsis, style: TextStyle(
                      color: sel ? AppColors.holoTeal : textPrimary,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                  trailing: sel ? const Icon(Icons.check_rounded, color: AppColors.holoTeal, size: 20) : null,
                  onTap: () => Navigator.pop(context, o.value),
                );
              },
            )),
      ]),
    );
  }
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

  // Import metadata for the "Schedule for <semester> · Updated <date>" header.
  Map<String, dynamic>? _meta;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length:4,vsync:this);
    _repo.fetchCurrentMeta().then((m) { if (mounted) setState(() => _meta = m); });
  }

  String _scheduleSubtitle(bool loading, int routeCount) {
    final m = _meta;
    if (m != null) {
      final semester = m['semester'] as String?;
      final importedAt = DateTime.tryParse(m['imported_at'] as String? ?? '');
      final updated = importedAt != null ? AppFormatters.fullDate(importedAt.toLocal()) : null;
      final sem = (semester != null && semester != 'legacy-import') ? 'Schedule for $semester' : '$routeCount routes';
      return updated != null ? '$sem · Updated $updated' : sem;
    }
    return loading ? 'Loading routes…' : '$routeCount routes available';
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
                    subtitle: _scheduleSubtitle(loading, routes.length),
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
/// directions along it (see to_dsc_trips/from_dsc_trips), so which stop
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
  // Admin-recorded per-stop timings, keyed by StopOffset.keyFor(). Empty until
  // loaded (and stays empty if nothing has been recorded yet) — every consumer
  // treats "absent" as "unknown", never as zero.
  Map<String, StopOffset> _offsets = const {};

  @override
  void initState() {
    super.initState();
    _loadOffsets();
  }

  Future<void> _loadOffsets() async {
    final o = await StopOffsetsRepository.fetchAll();
    if (mounted && o.isNotEmpty) setState(() => _offsets = o);
  }

  List<String> get _stopNames {
    final names = <String>{};
    for (final r in widget.routes) {
      final stops = (r['stops'] as List?) ?? const [];
      for (final s in stops) {
        final name = _cleanStop((s as Map)['name'] as String? ?? '');
        if (name.isNotEmpty) names.add(name);
      }
    }
    final list = names.toList()..sort();
    return list;
  }

  List<_RouteMatch> get _matches {
    // A single picked stop is enough: resolve every route that stops there back
    // to its parent route and show that route's real to/from-DSC times (stops
    // are pickup points on a route, never independent schedule entities). When
    // both are picked, require both to be on the same route.
    if (_from == null && _to == null) return const [];
    if (_from != null && _to != null && _from == _to) return const [];
    // The stop the user is asking about: their origin if they picked one,
    // otherwise the destination they picked.
    final focus = _from ?? _to;
    final results = <_RouteMatch>[];
    for (final r in widget.routes) {
      final stops = ((r['stops'] as List?) ?? const [])
          .cast<Map>().map((s) => _cleanStop(s['name'] as String? ?? '')).toList();
      if (_from != null && !stops.contains(_from)) continue;
      if (_to != null && !stops.contains(_to)) continue;
      final routeNumber = r['route_number'] as String? ?? '?';
      final scheduleType = r['schedule_type'] as String? ?? 'regular';
      final toDsc = _tripsOf(r, 'to_dsc_trips');
      final fromDsc = _tripsOf(r, 'from_dsc_trips');
      // Where the focused stop sits in this route's running order — the index
      // was previously computed and thrown away, but it's exactly what turns
      // "this route stops there" into "your stop is 4th, after ECB Chattor".
      final idx = focus == null ? -1 : stops.indexOf(focus);
      final offset = focus == null ? null : _offsets[StopOffset.keyFor(routeNumber, scheduleType, focus)];
      results.add((
        routeId: r['id'] as String,
        routeNumber: routeNumber,
        routeName: r['route_name'] as String? ?? 'Route',
        toDsc: toDsc,
        fromDsc: fromDsc,
        stopIndex: idx,
        stopCount: stops.length,
        originName: stops.isEmpty ? null : stops.first,
        // Real per-stop times, but ONLY when an admin actually recorded the
        // offset. Null means "not known" and the UI must say so rather than
        // present the route-level time as if it were the stop's.
        stopToDsc: StopTimeCalculator.shiftAll(toDsc, offset?.minutesFromOrigin),
        stopFromDsc: StopTimeCalculator.shiftAll(fromDsc, offset?.minutesFromDsc),
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
    // The stop whose times the user is really asking about.
    final focusStop = _from ?? _to;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + GlassBottomNav.navContentClearance), children: [
      Text('Where are you, and where are you going?',
          style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
      const SizedBox(height: 4),
      Text('Pick a stop to see its route — add a destination to narrow it down.',
          style: AppTextStyles.labelSmall.copyWith(color: textSecondary)),
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
      else if ((_from != null || _to != null) && matches.isEmpty)
        Center(child: Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.route_outlined, size: 34, color: textSecondary),
          const SizedBox(height: 10),
          Text(_to == null ? 'No route stops there yet' : 'No route covers that trip', style: TextStyle(color: textSecondary)),
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
                Expanded(child: Text(_displayRouteName(m.routeName), style: AppTextStyles.titleMedium.copyWith(color: textPrimary), overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                _LiveStatusBadge(status: widget.liveStatus[m.routeId]),
              ]),
              Text(_from != null && _to != null ? '$_from → $_to' : (_from != null ? 'Stops at $_from' : 'Stops at $_to'),
                  style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
              // The plain-language answer to "when is the bus at my stop?".
              if (focusStop != null) _StopAnswerCard(match: m, stop: focusStop),
              // The route's own timetable stays below, clearly labelled as
              // to/from DSC so the two are never confused with each other.
              if (m.toDsc.isNotEmpty) _TimeChipsRow(label: 'To DSC', times: m.toDsc),
              if (m.fromDsc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
                  child: _TimeChipsRow(label: 'From DSC', times: m.fromDsc)),
            ])),
          ]),
        )),
    ]);
  }
}

/// "7:00 AM and 10:00 AM" / "1:30 PM, 4:20 PM and 6:10 PM" — times read as a
/// sentence rather than a grid. Coming-soon slots are skipped (they have no
/// time to read out).
String _readTimes(List<Trip> trips) {
  final times = trips.where((t) => t.time != null && !t.isComingSoon).map((t) => t.time!).toList();
  if (times.isEmpty) return '';
  if (times.length == 1) return times.first;
  return '${times.sublist(0, times.length - 1).join(', ')} and ${times.last}';
}

/// Normalized word tokens: lower-cased, every non-alphanumeric run treated as a
/// separator, so "Mirpur-1, 10" becomes ['mirpur', '1', '10'].
List<String> _tokens(String s) =>
    s.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((t) => t.isNotEmpty).toList();

/// Trips whose note names [stop] as a **contiguous** token run.
///
/// Deliberately strict. A loose "contains any token" test would match
/// "Mirpur 10" against the note "will go upto Mirpur-1, 10, pallabi and ECB",
/// which lists Mirpur-1 AND Mirpur-10 as separate places — and would just as
/// happily match a note that only mentioned Mirpur-1. Telling a rider the wrong
/// bus serves their stop is worse than telling them nothing, so anything short
/// of an exact phrase match stays silent.
List<Trip> _tripsNaming(List<Trip> trips, String stop) {
  final needle = _tokens(stop);
  if (needle.isEmpty) return const [];
  return trips.where((t) {
    if (t.note == null || t.note!.isEmpty || t.time == null) return false;
    final hay = _tokens(t.note!);
    for (var i = 0; i + needle.length <= hay.length; i++) {
      var ok = true;
      for (var j = 0; j < needle.length; j++) {
        if (hay[i + j] != needle[j]) { ok = false; break; }
      }
      if (ok) return true;
    }
    return false;
  }).toList();
}

/// One route that serves the picked stop(s).
///
/// [toDsc]/[fromDsc] are the ROUTE-level times straight from the sheet: the
/// start time at the route's first stop, and the departure time from campus.
/// [stopToDsc]/[stopFromDsc] are those same trips shifted to the picked stop —
/// and are **null whenever no admin offset has been recorded**, which is the
/// signal for the UI to describe the route honestly instead of presenting the
/// origin's times as if they were the stop's.
typedef _RouteMatch = ({
  String routeId,
  String routeNumber,
  String routeName,
  List<Trip> toDsc,
  List<Trip> fromDsc,
  int stopIndex,
  int stopCount,
  String? originName,
  List<Trip>? stopToDsc,
  List<Trip>? stopFromDsc,
});

/// Answers "what time is the bus at MY stop?" for one route.
///
/// Two states, and the difference between them is the whole point:
///
///  * **Timings recorded** — shows the genuine per-stop times an admin entered
///    offsets for ("From Mirpur 10 · 7:18 AM and 10:18 AM").
///  * **Not recorded** — states only what the sheet actually says: where the
///    stop sits in the running order, and that the quoted times belong to the
///    route's FIRST stop. It never relabels the origin's times as the stop's.
class _StopAnswerCard extends StatelessWidget {
  final _RouteMatch match;
  final String stop;
  const _StopAnswerCard({required this.match, required this.stop});

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final known = match.stopToDsc != null || match.stopFromDsc != null;
    final isOrigin = match.stopIndex == 0;

    final lines = <Widget>[];

    if (known) {
      final toStr = _readTimes(match.stopToDsc ?? const []);
      final fromStr = _readTimes(match.stopFromDsc ?? const []);
      if (toStr.isNotEmpty) {
        lines.add(_line(Icons.school_rounded, AppColors.holoTeal,
            'Towards campus from $stop', toStr, textPrimary, textSecondary));
      }
      if (fromStr.isNotEmpty) {
        lines.add(_line(Icons.home_rounded, AppColors.holoBlue,
            'Back from campus, reaching $stop', fromStr, textPrimary, textSecondary));
      }
    } else if (isOrigin) {
      // The picked stop IS the route's origin, so the sheet's start times are
      // literally this stop's departure times — no offset needed to say so.
      final toStr = _readTimes(match.toDsc);
      final fromStr = _readTimes(match.fromDsc);
      if (toStr.isNotEmpty) {
        lines.add(_line(Icons.school_rounded, AppColors.holoTeal,
            'Buses leave $stop at', toStr, textPrimary, textSecondary));
      }
      if (fromStr.isNotEmpty) {
        lines.add(_line(Icons.home_rounded, AppColors.holoBlue,
            'Leaving campus at', fromStr, textPrimary, textSecondary));
      }
    } else {
      final origin = match.originName;
      final toStr = _readTimes(match.toDsc);
      final position = match.stopIndex >= 0 && match.stopCount > 0
          ? '$stop is stop ${match.stopIndex + 1} of ${match.stopCount} on this route.'
          : '$stop is on this route.';
      lines.add(Text(position, style: AppTextStyles.bodyMedium.copyWith(color: textPrimary)));
      if (toStr.isNotEmpty && origin != null) {
        lines.add(const SizedBox(height: 4));
        lines.add(Text(
          'The bus starts from $origin at $toStr, so it reaches $stop a little later.',
          style: AppTextStyles.labelSmall.copyWith(color: textSecondary, height: 1.35),
        ));
      }
    }

    // Only claim a specific run serves this stop when its own note says so
    // word-for-word (see _tripsNaming).
    final naming = _tripsNaming(match.fromDsc, stop);
    if (naming.isNotEmpty) {
      lines.add(const SizedBox(height: 6));
      lines.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.verified_rounded, size: 13, color: AppColors.green),
        const SizedBox(width: 6),
        Expanded(child: Text(
          'The ${_readTimes(naming)} run${naming.length == 1 ? '' : 's'} from campus '
          'go${naming.length == 1 ? 'es' : ''} all the way to $stop.',
          style: AppTextStyles.labelSmall.copyWith(color: AppColors.green, height: 1.3),
        )),
      ]));
    }

    if (!known && !isOrigin) {
      lines.add(const SizedBox(height: 6));
      lines.add(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, size: 12, color: textSecondary),
        const SizedBox(width: 6),
        Expanded(child: Text(
          'Exact times at this stop haven\'t been set by admin yet.',
          style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
        )),
      ]));
    }

    if (lines.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (known || isOrigin ? AppColors.holoTeal : AppColors.textSecondaryOf(context))
            .withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: (known || isOrigin ? AppColors.holoTeal : AppColors.borderOf(context))
                .withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
    );
  }

  Widget _line(IconData icon, Color accent, String label, String times, Color primary, Color secondary) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 14, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(children: [
                TextSpan(text: '$label  ', style: AppTextStyles.labelSmall.copyWith(color: secondary)),
                TextSpan(text: times,
                    style: AppTextStyles.bodyMedium.copyWith(color: primary, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      );
}

/// One trip chip: the time (or "Coming soon"), with any note as a caption.
class _TripChip extends StatelessWidget {
  final Trip trip;
  const _TripChip({required this.trip});
  @override
  Widget build(BuildContext context) {
    final soon = trip.isComingSoon;
    final color = soon ? AppColors.amber : AppColors.holoTeal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(soon ? 'Being updated' : (trip.time ?? '—'),
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        if (soon)
          Text('check back soon', style: TextStyle(fontSize: 9.5, color: AppColors.textSecondaryOf(context)))
        else if (trip.note != null && trip.note!.isNotEmpty)
          Text(trip.note!, style: TextStyle(fontSize: 9.5, color: AppColors.textSecondaryOf(context))),
      ]),
    );
  }
}

class _TimeChipsRow extends StatelessWidget {
  final String label; final List<Trip> times;
  const _TimeChipsRow({required this.label, required this.times});
  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 62, child: Text(label,
          style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w600))),
      Expanded(child: Wrap(spacing: 6, runSpacing: 4,
          children: times.map((t) => _TripChip(trip: t)).toList())),
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
  // Renders as a labelled, tappable field (not a Material dropdown): tapping
  // opens a searchable glass bottom-sheet picker (_showOptionPicker) — proper
  // positioning + search for the 170+ stop list, instead of a cramped dropdown
  // overlay that anchored badly and couldn't be searched.
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final picked = await _showOptionPicker<String>(context,
                  title: 'Select a stop',
                  options: options.map((s) => (label: s, value: s)).toList(),
                  selected: value);
              if (picked != null) onChanged(picked);
            },
            child: Row(children: [
              Expanded(child: Text(value ?? 'Select a stop',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: value == null ? AppColors.textMutedOf(context) : AppColors.textPrimaryOf(context),
                      fontWeight: FontWeight.w600, fontSize: 15))),
              Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondaryOf(context)),
            ]),
          ),
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
    final stops = ((selected?['stops'] as List?) ?? const []).cast<Map>().map((s) => _cleanStop(s['name'] as String? ?? '')).where((s) => s.isNotEmpty).toList();
    final toDsc = selected == null ? <Trip>[] : _tripsOf(selected, 'to_dsc_trips');
    final fromDsc = selected == null ? <Trip>[] : _tripsOf(selected, 'from_dsc_trips');
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + GlassBottomNav.navContentClearance),children:[
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
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                final picked = await _showOptionPicker<String>(context,
                    title: 'Choose your route',
                    options: widget.routes.map((r) => (
                        label: '${r['route_number']} — ${_displayRouteName(r['route_name'] as String? ?? 'Route')}',
                        value: r['id'] as String)).toList(),
                    selected: _selectedRoute);
                if (picked != null) setState(() { _selectedRoute = picked; _autoSuggested = false; });
              },
              child: Row(children: [
                Expanded(child: Text(
                    selected == null ? 'Choose route' : '${selected['route_number']} — ${_displayRouteName(selected['route_name'] as String? ?? 'Route')}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: selected == null ? AppColors.textMutedOf(context) : AppColors.textPrimaryOf(context),
                        fontWeight: FontWeight.w600, fontSize: 15))),
                Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondaryOf(context)),
              ]),
            ),
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
              const SizedBox(height: 10),
              _StopsTimeline(stops: stops),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                  onPressed: () => _openInGoogleMaps(stops),
                  icon: const Icon(Icons.directions_rounded, size: 18),
                  label: const Text('Open in Google Maps'))),
            ])),
        const SizedBox(height: 16),
        if (toDsc.isNotEmpty) _ScheduleCard(title: 'To DSC', times: toDsc, icon: Icons.login_rounded, accent: AppColors.holoTeal),
        if (fromDsc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12),
            child: _ScheduleCard(title: 'From DSC', times: fromDsc, icon: Icons.logout_rounded, accent: AppColors.holoBlue)),
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
/// A small live-pulsing dot used to signal "this is real-time" next to the
/// NEXT BUS header.
class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});
  @override State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat(reverse: true);
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 14, height: 14,
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Stack(alignment: Alignment.center, children: [
        Container(width: 6 + 8 * _c.value, height: 6 + 8 * _c.value,
            decoration: BoxDecoration(shape: BoxShape.circle,
                color: widget.color.withValues(alpha: 0.28 * (1 - _c.value)))),
        Container(width: 7, height: 7,
            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
      ]),
    ),
  );
}

/// Live "next bus" hero — big departure time per direction with a relative
/// countdown chip and a pulsing "live" indicator.
class _NextDepartureCard extends StatelessWidget {
  final List<Trip> toDsc; final List<Trip> fromDsc;
  const _NextDepartureCard({required this.toDsc, required this.fromDsc});

  String _rel(int m) => m < 60 ? '${m}m' : '${m ~/ 60}h ${m % 60}m';

  Widget _leg(BuildContext context, String dir, _NextTrip n) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppColors.holoTeal.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(7)),
          child: Text(dir, style: const TextStyle(color: AppColors.holoTeal, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
        ),
        const SizedBox(width: 10),
        Text(n.time, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimaryOf(context))),
        const SizedBox(width: 8),
        Flexible(child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: AppColors.holoBlue.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(7)),
          child: Text('${n.isTomorrow ? 'tomorrow · ' : ''}in ${_rel(n.minutesUntil)}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.holoBlue, fontSize: 11, fontWeight: FontWeight.w700)),
        )),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final nextTo = _nextDeparture(toDsc, nowMin);
    final nextFrom = _nextDeparture(fromDsc, nowMin);
    if (nextTo == null && nextFrom == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppColors.holoTeal.withValues(alpha: 0.16), AppColors.holoBlue.withValues(alpha: 0.06)],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.holoTeal.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          _PulseDot(color: AppColors.holoTeal),
          SizedBox(width: 8),
          Text('NEXT BUS', style: TextStyle(
              color: AppColors.holoTeal, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          Spacer(),
          Icon(Icons.directions_bus_filled_rounded, color: AppColors.holoTeal, size: 20),
        ]),
        if (nextTo != null) _leg(context, 'TO DSC', nextTo),
        if (nextFrom != null) _leg(context, 'FROM DSC', nextFrom),
      ]),
    );
  }
}

/// One departure time rendered as a compact pill (amber for "coming soon").
class _TimePill extends StatelessWidget {
  final Trip trip; final Color accent;
  const _TimePill({required this.trip, required this.accent});
  @override
  Widget build(BuildContext context) {
    final soon = trip.isComingSoon;
    final c = soon ? AppColors.amber : accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.32)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(soon ? Icons.hourglass_bottom_rounded : Icons.access_time_rounded, size: 13, color: c),
        const SizedBox(width: 5),
        Text(soon ? 'Being updated' : (trip.time ?? '—'),
            style: TextStyle(color: c, fontSize: 12.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Departure times as a scannable pill grid with a count badge and direction
/// accent. Trips that carry a note are shown on their own line below so the
/// exception text (e.g. "Only 1 bus assigned") is never lost.
class _ScheduleCard extends StatelessWidget {
  final String title; final List<Trip> times;
  final IconData icon; final Color accent;
  const _ScheduleCard({required this.title, required this.times,
    this.icon = Icons.schedule_rounded, this.accent = AppColors.holoTeal});
  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondaryOf(context);
    final plain = times.where((t) => t.note == null || t.note!.isEmpty).toList();
    final noted = times.where((t) => t.note != null && t.note!.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 7),
          Expanded(child: Text(title.toUpperCase(), style: AppTextStyles.labelSmall.copyWith(
              color: textSecondary, fontWeight: FontWeight.w800, letterSpacing: 0.4))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text('${times.length}', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 12),
        if (plain.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: plain.map((t) => _TimePill(trip: t, accent: accent)).toList()),
        if (noted.isNotEmpty) ...[
          if (plain.isNotEmpty) const SizedBox(height: 10),
          ...noted.map((t) => Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(children: [
              _TimePill(trip: t, accent: accent),
              const SizedBox(width: 10),
              Expanded(child: Text(t.note!, style: AppTextStyles.labelSmall.copyWith(color: textSecondary))),
            ]),
          )),
        ],
        // Friendly, never-blank message when a slot's time hasn't been set yet.
        if (times.any((t) => t.isComingSoon)) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.hourglass_bottom_rounded, size: 13, color: AppColors.amber),
            const SizedBox(width: 6),
            Expanded(child: Text(_kSoonMsg,
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.amber, fontWeight: FontWeight.w600))),
          ]),
        ],
      ]),
    );
  }
}

/// Vertical route timeline: connected stop nodes from origin (blue START) down
/// to the campus destination (teal DESTINATION), replacing the old flat
/// "A -> B -> C" text so the full route path reads at a glance.
class _StopsTimeline extends StatelessWidget {
  final List<String> stops;
  const _StopsTimeline({required this.stops});
  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (int i = 0; i < stops.length; i++)
        _row(stops[i], i == 0, i == stops.length - 1, textPrimary, textSecondary),
    ]);
  }

  Widget _row(String name, bool isFirst, bool isLast, Color textPrimary, Color textSecondary) {
    final endpoint = isFirst || isLast;
    final nodeColor = isLast ? AppColors.holoTeal : (isFirst ? AppColors.holoBlue : textSecondary);
    const line = Color(0x593ECF8E); // teal @ ~0.35, connector
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(width: 24, child: Column(children: [
          Expanded(child: Container(width: 2, color: isFirst ? Colors.transparent : line)),
          Container(
            width: endpoint ? 14 : 9, height: endpoint ? 14 : 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: endpoint ? nodeColor : nodeColor.withValues(alpha: 0.55),
              boxShadow: endpoint ? [BoxShadow(color: nodeColor.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1)] : null,
            ),
          ),
          Expanded(child: Container(width: 2, color: isLast ? Colors.transparent : line)),
        ])),
        const SizedBox(width: 12),
        Expanded(child: Padding(
          padding: EdgeInsets.symmetric(vertical: endpoint ? 5 : 4.5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(name, style: TextStyle(
                color: endpoint ? textPrimary : textSecondary,
                fontWeight: endpoint ? FontWeight.w700 : FontWeight.w500,
                fontSize: endpoint ? 14 : 13)),
            if (isFirst) const Text('START', style: TextStyle(color: AppColors.holoBlue, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5))
            else if (isLast) const Text('DESTINATION', style: TextStyle(color: AppColors.holoTeal, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
          ]),
        )),
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
    final toDsc = _tripsOf(route, 'to_dsc_trips');
    final fromDsc = _tripsOf(route, 'from_dsc_trips');
    final stopNames = ((route['stops'] as List?) ?? const []).cast<Map>().map((s) => _cleanStop(s['name'] as String? ?? '')).where((s) => s.isNotEmpty).toList();
    showGlassSheet(context, child: Builder(builder: (sheetCtx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetCtx).size.height * 0.78),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: Text('${route['route_number']} — ${_displayRouteName(route['route_name'] as String? ?? 'Route')}',
                  style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx)))),
              _LiveStatusBadge(status: liveStatus[route['id']]),
            ]),
            const SizedBox(height: 16),
            if (stopNames.isNotEmpty) ...[
              Row(children: [
                const Icon(Icons.alt_route_rounded, size: 15, color: AppColors.holoTeal),
                const SizedBox(width: 7),
                Text('ROUTE PATH', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(sheetCtx), fontWeight: FontWeight.w800, letterSpacing: 0.4)),
              ]),
              const SizedBox(height: 10),
              _StopsTimeline(stops: stopNames),
              const SizedBox(height: 16),
            ],
            if (toDsc.isNotEmpty) _ScheduleCard(title: 'To DSC', times: toDsc, icon: Icons.login_rounded, accent: AppColors.holoTeal),
            if (fromDsc.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12, bottom: GlassBottomNav.navContentClearance),
                child: _ScheduleCard(title: 'From DSC', times: fromDsc, icon: Icons.logout_rounded, accent: AppColors.holoBlue)),
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
              // Admin-only: record how many minutes into each leg the bus
              // reaches each stop. Without this the app can only quote the
              // route's start/campus times, never the rider's own stop.
              if (RoleSession.role == 'admin' || RoleSession.role == 'super_admin') ...[
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.holoviolet),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ManageStopTimesScreen(
                          routeNumber: route['route_number'] as String? ?? '?',
                          scheduleType: route['schedule_type'] as String? ?? 'regular',
                          routeName: _displayRouteName(route['route_name'] as String? ?? 'Route'),
                          stops: stopNames,
                        ),
                      ));
                    },
                    icon: const Icon(Icons.more_time_rounded, size: 18),
                    label: const Text('Set stop times'))),
              ],
            ],
          ]),
        ),
      )));
  }

  @override
  Widget build(BuildContext context) {
    if(routes.isEmpty) {
      return Center(
        child:Text('No routes',style:TextStyle(color:AppColors.textSecondaryOf(context))));
    }
    // Group by schedule_type into the source document's own sections
    // (Regular / Shuttle / Friday). On Fridays the Friday schedule is what
    // actually applies today, so surface it FIRST and flag it; other days keep
    // the document's Regular → Shuttle → Friday order.
    final isFriday = DateTime.now().weekday == DateTime.friday;
    final order = isFriday
        ? const [ScheduleType.friday, ScheduleType.regular, ScheduleType.shuttle]
        : const [ScheduleType.regular, ScheduleType.shuttle, ScheduleType.friday];
    final grouped = <ScheduleType, List<Map<String,dynamic>>>{};
    for (final r in routes) {
      final type = ScheduleTypeX.fromWire(r['schedule_type'] as String?);
      grouped.putIfAbsent(type, () => []).add(r);
    }
    final children = <Widget>[];
    var idx = 0;
    if (isFriday && (grouped[ScheduleType.friday]?.isNotEmpty ?? false)) {
      children.add(Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          const Icon(Icons.event_available_rounded, size: 16, color: AppColors.amber),
          const SizedBox(width: 8),
          Expanded(child: Text("It's Friday — the Friday schedule applies today.",
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.amber, fontWeight: FontWeight.w700))),
        ]),
      ));
    }
    for (final type in order) {
      final group = grouped[type];
      if (group == null || group.isEmpty) continue;
      final isTodaySection = isFriday && type == ScheduleType.friday;
      // Only label sections when more than one exists, so a single-section
      // schedule doesn't get a redundant header.
      if (grouped.length > 1) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
          child: Text('${type.label.toUpperCase()}${isTodaySection ? '  ·  TODAY' : ''}',
              style: AppTextStyles.labelSmall.copyWith(
                  letterSpacing: 1.5,
                  fontWeight: isTodaySection ? FontWeight.w800 : null,
                  color: isTodaySection ? AppColors.amber : AppColors.textSecondaryOf(context))),
        ));
      }
      for (final r in group) {
        children.add(_routeCard(context, r, idx++));
      }
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16 + GlassBottomNav.navContentClearance), children: children);
  }

  Widget _routeCard(BuildContext context, Map<String,dynamic> r, int i) {
    final ctx = context;
    final stops = ((r['stops'] as List?) ?? const []).cast<Map>().map((s) => _cleanStop(s['name'] as String? ?? '')).where((s) => s.isNotEmpty).toList();
    final toDsc = _tripsOf(r, 'to_dsc_trips');
    final subtitle = stops.isNotEmpty
        ? '${stops.first} → ${stops.last} · ${stops.length} stops'
        : toDsc.isNotEmpty ? '${toDsc.length} trips/day' : 'No trip data yet';
    final accent = _accentFor(ScheduleTypeX.fromWire(r['schedule_type'] as String?));
    // App-consistent glass surface (SurfaceCard = signature cut-corner, list-row
    // safe with blur:false), replacing the old bespoke gradient-border card so
    // the transport screen matches the rest of the redesign.
    return SurfaceCard(
      margin: const EdgeInsets.only(bottom: 12),
      blur: false,
      radius: 18,
      accent: accent,
      onTap: () => _showRouteDetail(ctx, r),
      child: Row(children: [
        Container(width: 44, height: 44,
            decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                    colors: [accent.withValues(alpha: 0.9), accent.withValues(alpha: 0.6)]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))]),
            child: Center(child: Text(r['route_number']??'?',
                textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
                style: const TextStyle(color: Colors.white, height: 1.0, fontWeight: FontWeight.w800, fontSize: 15)))),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children: [
            Expanded(child: Text(_displayRouteName(r['route_name'] as String? ?? ''),style:AppTextStyles.titleMedium.copyWith(color:AppColors.textPrimaryOf(context), fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 6),
            _LiveStatusBadge(status: liveStatus[r['id']]),
          ]),
          const SizedBox(height: 3),
          Row(children: [
            Icon(Icons.route_rounded, size: 12, color: AppColors.textSecondaryOf(context)),
            const SizedBox(width: 4),
            Expanded(child: Text(subtitle,style:AppTextStyles.bodyMedium.copyWith(color:AppColors.textSecondaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ])),
        Icon(Icons.chevron_right,color:AppColors.textSecondaryOf(context)),
      ]),
    ).animate(delay: Duration(milliseconds: i * 50))
        .fadeIn(curve: Curves.easeOutCubic).slideY(begin: 0.05, curve: Curves.easeOutCubic);
  }
}

/// One accent per schedule type, so Regular / Shuttle / Friday read distinctly
/// across route cards and the schedule chips.
Color _accentFor(ScheduleType t) => switch (t) {
      ScheduleType.regular => AppColors.holoTeal,
      ScheduleType.shuttle => AppColors.holoBlue,
      ScheduleType.friday => AppColors.amber,
    };

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
      Positioned(right: 16, bottom: 16 + MediaQuery.of(context).padding.bottom, child: FloatingActionButton(
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
      if (showNoPathNote) Positioned(left: 16, right: 16, bottom: 90 + MediaQuery.of(context).padding.bottom, child: Container(
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
