import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../../shared/widgets/supernova_loader.dart';
import '../../../shared/widgets/surface_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/transport_repository.dart';

class TransportScreen extends StatefulWidget {
  const TransportScreen({super.key});
  @override State<TransportScreen> createState() => _TransportState();
}

class _TransportState extends State<TransportScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _repo = TransportRepository();
  String? _selectedRouteId;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length:4,vsync:this);
  }

  void _viewOnMap(String routeId) {
    setState(() => _selectedRouteId = routeId);
    _tab.animateTo(3);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar:AfosAppBar(title:'Transport'),
      body:Column(children:[
        Container(color:AppColors.surfaceOf(context),child:TabBar(controller:_tab,
          labelColor:AppColors.holoTeal,unselectedLabelColor:AppColors.textSecondaryOf(context),
          indicatorColor:AppColors.holoTeal,
          tabs:const [Tab(text:'Find Route'),Tab(text:'My Route'),Tab(text:'All Routes'),Tab(text:'Map')])),
        Expanded(child: StreamBuilder<List<Map<String,dynamic>>>(
          stream: _repo.watchRoutes(),
          builder: (ctx, snap) {
            final loading = snap.connectionState==ConnectionState.waiting;
            final routes = snap.data ?? const <Map<String,dynamic>>[];
            return StreamBuilder<Map<String, Map<String, dynamic>>>(
              stream: _repo.watchLiveStatus(),
              builder: (ctx2, statusSnap) {
                final liveStatus = statusSnap.data ?? const <String, Map<String, dynamic>>{};
                return TabBarView(controller:_tab,children:[
                  loading?const Padding(padding:EdgeInsets.all(16),child:ShimmerList()):_FindRouteTab(routes:routes, liveStatus: liveStatus),
                  loading?const Padding(padding:EdgeInsets.all(16),child:ShimmerList()):_MyRouteTab(routes:routes, liveStatus: liveStatus),
                  loading?const Padding(padding:EdgeInsets.all(16),child:ShimmerList()):_AllRoutesTab(routes:routes, liveStatus: liveStatus, repo: _repo, onViewOnMap: _viewOnMap),
                  _MapTab(selectedRouteId: _selectedRouteId, repo: _repo),
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
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Lets a user pick where they are and where they want to go, then shows
/// every route whose stop list contains both (origin appearing before
/// destination) along with the boarding/arrival time at each stop.
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
      if (fromIdx == -1 || toIdx == -1 || fromIdx >= toIdx) continue;
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
      return Center(child: Text('No stop data uploaded yet',
          style: TextStyle(color: textSecondary)));
    }
    final matches = _matches;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Where are you, and where are you going?',
          style: AppTextStyles.headlineLarge.copyWith(color: textPrimary)),
      const SizedBox(height: 16),
      _StopDropdown(label: 'From', value: _from, options: stopNames,
          onChanged: (v) => setState(() => _from = v)),
      const SizedBox(height: 12),
      _StopDropdown(label: 'To', value: _to, options: stopNames,
          onChanged: (v) => setState(() => _to = v)),
      const SizedBox(height: 20),
      if (_from != null && _to != null && _from == _to)
        Text('Pick two different stops', style: TextStyle(color: textSecondary))
      else if (_from != null && _to != null && matches.isEmpty)
        Text('No route covers that trip', style: TextStyle(color: textSecondary))
      else
        ...matches.map((m) => SurfaceCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.holoTeal.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text(m.routeNumber, style: const TextStyle(color: AppColors.holoTeal, fontWeight: FontWeight.bold)))),
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
          decoration: BoxDecoration(color: AppColors.holoTeal.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Text(t, style: const TextStyle(fontSize: 11, color: AppColors.holoTeal)))).toList())),
    ]);
  }
}

class _StopDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;
  const _StopDropdown({required this.label, required this.value, required this.options, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(hintText: label, filled: true, fillColor: AppColors.glassFill(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.glassBorder(context)))),
      dropdownColor: AppColors.surfaceOf(context),
      style: TextStyle(color: AppColors.textPrimaryOf(context)),
      items: options.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: onChanged,
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
  @override
  Widget build(BuildContext context) {
    if(widget.routes.isEmpty) return Center(
      child:Text('No routes available',style:TextStyle(color:AppColors.textSecondaryOf(context))));
    final selected = widget.routes.where((r) => r['id'] == _selectedRoute).firstOrNull;
    final stops = ((selected?['stops'] as List?) ?? const []).cast<Map>().map((s) => s['name'] as String? ?? '').where((s) => s.isNotEmpty).toList();
    final toDsc = ((selected?['to_dsc_times'] as List?) ?? const []).cast<String>();
    final fromDsc = ((selected?['from_dsc_times'] as List?) ?? const []).cast<String>();
    return ListView(padding:const EdgeInsets.all(16),children:[
      Text('Select your route',
          style:AppTextStyles.headlineLarge.copyWith(color:AppColors.textPrimaryOf(context))),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(
        value:_selectedRoute,
        isExpanded: true,
        decoration:InputDecoration(hintText:'Choose route',filled:true,fillColor:AppColors.glassFill(context),
          border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),
            borderSide:BorderSide(color:AppColors.glassBorder(context)))),
        dropdownColor:AppColors.surfaceOf(context),style:TextStyle(color:AppColors.textPrimaryOf(context)),
        items:widget.routes.map((r)=>DropdownMenuItem(value:r['id'] as String,
          child:Text('${r['route_number']} — ${r['route_name'] ?? 'Route'}', overflow: TextOverflow.ellipsis))).toList(),
        onChanged:(v)=>setState(()=>_selectedRoute=v),
      ),
      if(selected!=null) ...[
        const SizedBox(height:16),
        Row(children: [
          _LiveStatusBadge(status: widget.liveStatus[selected['id']]),
        ]),
        const SizedBox(height:8),
        if (stops.isNotEmpty) Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Route Path', style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(stops.join('  →  '), style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimaryOf(context))),
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
                ]))));
  }

  @override
  Widget build(BuildContext context) {
    if(routes.isEmpty) return Center(
        child:Text('No routes',style:TextStyle(color:AppColors.textSecondaryOf(context))));
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
            borderRadius: BorderRadius.circular(14),
            onTap: () => _showRouteDetail(ctx, r),
            child: RepaintBoundary(
              child: Container(
                padding:const EdgeInsets.all(14),
                decoration:BoxDecoration(color:AppColors.surfaceOf(context),borderRadius:BorderRadius.circular(14),
                  border:Border.all(color:AppColors.borderOf(context),width:0.5)),
                child:Row(children:[
                  Container(width:40,height:40,decoration:BoxDecoration(color:AppColors.holoTeal.withOpacity(0.15),borderRadius:BorderRadius.circular(10)),
                    child:Center(child:Text(r['route_number']??'?',style:const TextStyle(color:AppColors.holoTeal,fontWeight:FontWeight.bold)))),
                  const SizedBox(width:12),
                  Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                    Row(children: [
                      Expanded(child: Text(r['route_name']??'',style:AppTextStyles.titleMedium.copyWith(color:AppColors.textPrimaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 6),
                      _LiveStatusBadge(status: liveStatus[r['id']]),
                    ]),
                    Text(subtitle,style:AppTextStyles.bodyMedium.copyWith(color:AppColors.textSecondaryOf(context)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ])),
                  Icon(Icons.chevron_right,color:AppColors.textSecondaryOf(context)),
                ])),
            ),
          ),
        ));
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
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() { _locationError = 'Turn on location services to see your position'; _requestingLocation = false; });
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() { _locationError = 'Location permission denied'; _requestingLocation = false; });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (!mounted) return;
      setState(() { _myLocation = LatLng(pos.latitude, pos.longitude); _requestingLocation = false; });
      _mapController.move(_myLocation!, 15);
    } catch (e) {
      if (mounted) setState(() { _locationError = 'Could not get your location'; _requestingLocation = false; });
    }
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
            Marker(point:const LatLng(_diuLat,_diuLng), width:40, height:40,
              child:const Icon(Icons.school_rounded,color:AppColors.holoBlue,size:36)),
            ...routePoints.map((p) => Marker(point: p, width: 14, height: 14,
                child: Container(decoration: BoxDecoration(
                    color: AppColors.holoTeal, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2))))),
            if (_myLocation != null) Marker(point: _myLocation!, width: 26, height: 26,
                child: Container(decoration: BoxDecoration(
                    color: AppColors.holoTeal, shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: [BoxShadow(color: AppColors.holoTeal.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)]))),
          ]),
        ],
      ),
      Positioned(right: 16, bottom: 16, child: FloatingActionButton(
          heroTag: 'my_location_fab',
          backgroundColor: AppColors.surfaceOf(context),
          onPressed: _requestingLocation ? null : _enableLocation,
          child: _requestingLocation
              ? const SupernovaLoader(size: 20, color: AppColors.holoTeal)
              : Icon(Icons.my_location_rounded, color: AppColors.holoTeal))),
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
