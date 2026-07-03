import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/repositories/transport_repository.dart';

class TransportScreen extends StatefulWidget {
  const TransportScreen({super.key});
  @override State<TransportScreen> createState() => _TransportState();
}

class _TransportState extends State<TransportScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _repo = TransportRepository();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length:4,vsync:this);
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
            return TabBarView(controller:_tab,children:[
              loading?const Padding(padding:EdgeInsets.all(16),child:ShimmerList()):_FindRouteTab(routes:routes),
              loading?const Padding(padding:EdgeInsets.all(16),child:ShimmerList()):_MyRouteTab(routes:routes),
              loading?const Padding(padding:EdgeInsets.all(16),child:ShimmerList()):_AllRoutesTab(routes:routes),
              _MapTab(),
            ]);
          },
        )),
      ]),
    );
  }
}

/// Lets a user pick where they are and where they want to go, then shows
/// every route whose stop list contains both (origin appearing before
/// destination) along with the boarding/arrival time at each stop.
class _FindRouteTab extends StatefulWidget {
  final List<Map<String,dynamic>> routes;
  const _FindRouteTab({required this.routes});
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
          .cast<Map>().map((s) => (name: s['name'] as String?, time: s['time'] as String?)).toList();
      final fromIdx = stops.indexWhere((s) => s.name == _from);
      final toIdx = stops.indexWhere((s) => s.name == _to);
      if (fromIdx == -1 || toIdx == -1 || fromIdx >= toIdx) continue;
      results.add((
        routeNumber: r['route_number'] as String? ?? '?',
        routeName: r['route_name'] as String? ?? 'Route',
        boardTime: stops[fromIdx].time ?? '-',
        arriveTime: stops[toIdx].time ?? '-',
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
        ...matches.map((m) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderOf(context), width: 0.5)),
          child: Row(children: [
            Container(width: 40, height: 40,
              decoration: BoxDecoration(color: AppColors.holoTeal.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text(m.routeNumber, style: const TextStyle(color: AppColors.holoTeal, fontWeight: FontWeight.bold)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.routeName, style: AppTextStyles.titleMedium.copyWith(color: textPrimary)),
              Text('Board $_from at ${m.boardTime} → arrive $_to at ${m.arriveTime}',
                  style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
            ])),
          ]),
        )),
    ]);
  }
}

typedef _RouteMatch = ({String routeNumber, String routeName, String boardTime, String arriveTime});

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
      decoration: InputDecoration(hintText: label, filled: true, fillColor: AppColors.glassFill(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.glassBorder(context)))),
      dropdownColor: AppColors.surfaceOf(context),
      style: TextStyle(color: AppColors.textPrimaryOf(context)),
      items: options.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
      onChanged: onChanged,
    );
  }
}

class _MyRouteTab extends StatefulWidget {
  final List<Map<String,dynamic>> routes;
  const _MyRouteTab({required this.routes});
  @override State<_MyRouteTab> createState() => _MyRouteTabState();
}

class _MyRouteTabState extends State<_MyRouteTab> {
  String? _selectedRoute;
  @override
  Widget build(BuildContext context) {
    if(widget.routes.isEmpty) return Center(
      child:Text('No routes available',style:TextStyle(color:AppColors.textSecondaryOf(context))));
    return ListView(padding:const EdgeInsets.all(16),children:[
      Text('Select your route',
          style:AppTextStyles.headlineLarge.copyWith(color:AppColors.textPrimaryOf(context))),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(
        value:_selectedRoute,
        decoration:InputDecoration(hintText:'Choose route',filled:true,fillColor:AppColors.glassFill(context),
          border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),
            borderSide:BorderSide(color:AppColors.glassBorder(context)))),
        dropdownColor:AppColors.surfaceOf(context),style:TextStyle(color:AppColors.textPrimaryOf(context)),
        items:widget.routes.map((r)=>DropdownMenuItem(value:r['id'] as String,
          child:Text(r['route_name'] as String? ??'Route'))).toList(),
        onChanged:(v)=>setState(()=>_selectedRoute=v),
      ),
      if(_selectedRoute!=null) ...[
        const SizedBox(height:20),
        _buildStatusCard(context),
        const SizedBox(height:16),
        ..._buildSchedule(context),
      ],
    ]);
  }

  Widget _buildStatusCard(BuildContext context) {
    return RepaintBoundary(
      child: Container(padding:const EdgeInsets.all(16),
        decoration:BoxDecoration(color:AppColors.green.withOpacity(0.1),borderRadius:BorderRadius.circular(14),
          border:Border.all(color:AppColors.green.withOpacity(0.3))),
        child:Row(children:[
          Container(width:12,height:12,decoration:const BoxDecoration(color:AppColors.green,shape:BoxShape.circle)),
          const SizedBox(width:10),
          Text('On Time',style:AppTextStyles.titleLarge.copyWith(color:AppColors.green)),
          const Spacer(),
          Text('Next: 8:00 AM',style:AppTextStyles.bodyMedium.copyWith(color:AppColors.textSecondaryOf(context))),
        ])),
    );
  }

  List<Widget> _buildSchedule(BuildContext context) {
    final times = ['8:00 AM','10:00 AM','12:00 PM','2:00 PM','5:00 PM'];
    return times.map((t)=>Container(margin:const EdgeInsets.only(bottom:8),
      padding:const EdgeInsets.all(12),
      decoration:BoxDecoration(color:AppColors.surfaceOf(context),borderRadius:BorderRadius.circular(10),
        border:Border.all(color:AppColors.borderOf(context),width:0.5)),
      child:Row(children:[
        Icon(Icons.access_time,color:AppColors.textSecondaryOf(context),size:16),
        const SizedBox(width:10),
        Text(t,style:AppTextStyles.titleMedium.copyWith(color:AppColors.textPrimaryOf(context))),
      ]))).toList();
  }
}

class _AllRoutesTab extends StatelessWidget {
  final List<Map<String,dynamic>> routes;
  const _AllRoutesTab({required this.routes});
  @override
  Widget build(BuildContext context) {
    if(routes.isEmpty) return Center(
        child:Text('No routes',style:TextStyle(color:AppColors.textSecondaryOf(context))));
    return ListView.builder(padding:const EdgeInsets.all(16),itemCount:routes.length,
      itemBuilder:(ctx,i){
        final r = routes[i];
        return RepaintBoundary(
          child: Container(margin:const EdgeInsets.only(bottom:12),
            padding:const EdgeInsets.all(14),
            decoration:BoxDecoration(color:AppColors.surfaceOf(context),borderRadius:BorderRadius.circular(14),
              border:Border.all(color:AppColors.borderOf(context),width:0.5)),
            child:Row(children:[
              Container(width:40,height:40,decoration:BoxDecoration(color:AppColors.holoTeal.withOpacity(0.15),borderRadius:BorderRadius.circular(10)),
                child:Center(child:Text(r['route_number']??'?',style:const TextStyle(color:AppColors.holoTeal,fontWeight:FontWeight.bold)))),
              const SizedBox(width:12),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                Text(r['route_name']??'',style:AppTextStyles.titleMedium.copyWith(color:AppColors.textPrimaryOf(context))),
                Text('Daily service',style:AppTextStyles.bodyMedium.copyWith(color:AppColors.textSecondaryOf(context))),
              ])),
              Icon(Icons.chevron_right,color:AppColors.textSecondaryOf(context)),
            ])),
        );
      });
  }
}

class _MapTab extends StatelessWidget {
  static const _diuLat = 23.7953, _diuLng = 90.4044;
  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: const MapOptions(
        initialCenter:LatLng(_diuLat,_diuLng), initialZoom:14),
      children:[
        TileLayer(urlTemplate:'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName:'com.example.afos_v7'),
        MarkerLayer(markers:[
          Marker(point:const LatLng(_diuLat,_diuLng), width:40, height:40,
            child:const Icon(Icons.school_rounded,color:AppColors.holoBlue,size:36)),
        ]),
      ],
    );
  }
}
