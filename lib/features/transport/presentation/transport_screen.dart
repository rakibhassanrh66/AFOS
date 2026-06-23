import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';

class TransportScreen extends StatefulWidget {
  const TransportScreen({super.key});
  @override State<TransportScreen> createState() => _TransportState();
}

class _TransportState extends State<TransportScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  List<Map<String,dynamic>> _routes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length:3,vsync:this);
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await SupabaseConfig.client.from('transport_routes').select().eq('is_active',true) as List;
      if(mounted) setState(()=>_routes=r.cast<Map<String,dynamic>>());
    } catch(_) {}
    if(mounted) setState(()=>_loading=false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:AppColors.background,
      appBar:AfosAppBar(title:'Transport'),
      body:Column(children:[
        Container(color:AppColors.surface,child:TabBar(controller:_tab,
          labelColor:AppColors.blue,unselectedLabelColor:AppColors.textSecondary,
          indicatorColor:AppColors.blue,
          tabs:const [Tab(text:'My Route'),Tab(text:'All Routes'),Tab(text:'Map')])),
        Expanded(child:TabBarView(controller:_tab,children:[
          _loading?const Padding(padding:EdgeInsets.all(16),child:ShimmerList()):_MyRouteTab(routes:_routes),
          _loading?const Padding(padding:EdgeInsets.all(16),child:ShimmerList()):_AllRoutesTab(routes:_routes),
          _MapTab(),
        ])),
      ]),
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
    if(widget.routes.isEmpty) return const Center(
      child:Text('No routes available',style:TextStyle(color:AppColors.textSecondary)));
    return ListView(padding:const EdgeInsets.all(16),children:[
      Text('Select your route',style:AppTextStyles.headlineLarge),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(
        value:_selectedRoute,
        decoration:InputDecoration(hintText:'Choose route',filled:true,fillColor:AppColors.card,
          border:OutlineInputBorder(borderRadius:BorderRadius.circular(12),borderSide:const BorderSide(color:AppColors.border))),
        dropdownColor:AppColors.card,style:const TextStyle(color:AppColors.textPrimary),
        items:widget.routes.map((r)=>DropdownMenuItem(value:r['id'] as String,
          child:Text(r['route_name'] as String? ??'Route'))).toList(),
        onChanged:(v)=>setState(()=>_selectedRoute=v),
      ),
      if(_selectedRoute!=null) ...[
        const SizedBox(height:20),
        _StatusCard(),
        const SizedBox(height:16),
        ..._buildSchedule(),
      ],
    ]);
  }

  Widget _StatusCard() {
    return Container(padding:const EdgeInsets.all(16),
      decoration:BoxDecoration(color:AppColors.green.withOpacity(0.1),borderRadius:BorderRadius.circular(14),
        border:Border.all(color:AppColors.green.withOpacity(0.3))),
      child:Row(children:[
        Container(width:12,height:12,decoration:const BoxDecoration(color:AppColors.green,shape:BoxShape.circle)),
        const SizedBox(width:10),
        Text('On Time',style:AppTextStyles.titleLarge.copyWith(color:AppColors.green)),
        const Spacer(),
        Text('Next: 8:00 AM',style:AppTextStyles.bodyMedium),
      ]));
  }

  List<Widget> _buildSchedule() {
    final times = ['8:00 AM','10:00 AM','12:00 PM','2:00 PM','5:00 PM'];
    return times.map((t)=>Container(margin:const EdgeInsets.only(bottom:8),
      padding:const EdgeInsets.all(12),
      decoration:BoxDecoration(color:AppColors.card,borderRadius:BorderRadius.circular(10),
        border:Border.all(color:AppColors.border,width:0.5)),
      child:Row(children:[
        const Icon(Icons.access_time,color:AppColors.textSecondary,size:16),
        const SizedBox(width:10),
        Text(t,style:AppTextStyles.titleMedium),
      ]))).toList();
  }
}

class _AllRoutesTab extends StatelessWidget {
  final List<Map<String,dynamic>> routes;
  const _AllRoutesTab({required this.routes});
  @override
  Widget build(BuildContext context) {
    if(routes.isEmpty) return const Center(child:Text('No routes',style:TextStyle(color:AppColors.textSecondary)));
    return ListView.builder(padding:const EdgeInsets.all(16),itemCount:routes.length,
      itemBuilder:(ctx,i){
        final r = routes[i];
        return Container(margin:const EdgeInsets.only(bottom:12),
          padding:const EdgeInsets.all(14),
          decoration:BoxDecoration(color:AppColors.card,borderRadius:BorderRadius.circular(14),
            border:Border.all(color:AppColors.border,width:0.5)),
          child:Row(children:[
            Container(width:40,height:40,decoration:BoxDecoration(color:AppColors.teal.withOpacity(0.15),borderRadius:BorderRadius.circular(10)),
              child:Center(child:Text(r['route_number']??'?',style:const TextStyle(color:AppColors.teal,fontWeight:FontWeight.bold)))),
            const SizedBox(width:12),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(r['route_name']??'',style:AppTextStyles.titleMedium),
              Text('Daily service',style:AppTextStyles.bodyMedium),
            ])),
            const Icon(Icons.chevron_right,color:AppColors.textSecondary),
          ]));
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
            child:const Icon(Icons.school_rounded,color:AppColors.blue,size:36)),
        ]),
      ],
    );
  }
}
