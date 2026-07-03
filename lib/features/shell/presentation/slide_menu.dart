import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../bloc/shell_bloc.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/models/user_model.dart';

class SlideMenu extends StatefulWidget {
  const SlideMenu({super.key});
  @override State<SlideMenu> createState() => _SlideMenuState();
}

class _SlideMenuState extends State<SlideMenu> {
  UserModel? _user;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = SupabaseConfig.uid;
    if(uid==null) return;
    try {
      final p = await SupabaseConfig.client.from('profiles').select().eq('id',uid).single();
      if(mounted) setState(()=>_user=UserModel.fromJson(p));
    } catch(_) {}
  }

  static const _items = [
    _MenuItem('Dashboard',      Icons.home_rounded,          '/home',          AppColors.blue),
    _MenuItem('Class Schedule', Icons.calendar_today_rounded,'/schedule',      Color(0xFF1E6FFF)),
    _MenuItem('Hall Allocation',Icons.apartment_rounded,     '/hall',          AppColors.amber),
    _MenuItem('Transport',      Icons.directions_bus_rounded,'/transport',     AppColors.teal),
    _MenuItem('Payment',        Icons.payment_rounded,       '/payment',       AppColors.gold),
    _MenuItem('Library',        Icons.menu_book_rounded,     '/library',       AppColors.purple),
    _MenuItem('Lost & Found',   Icons.search_rounded,        '/lost-found',    AppColors.coral),
    _MenuItem('Clubs',          Icons.groups_rounded,        '/clubs',         AppColors.pink),
    _MenuItem('Mentorship',     Icons.school_rounded,        '/mentorship',    Color(0xFF60A5FA)),
    _MenuItem('Dept Chat',      Icons.chat_rounded,          '/dept-chat',     AppColors.indigo),
    _MenuItem('Exam Seat Plan', Icons.event_seat_rounded,    '/exam-seat',     AppColors.orange),
    _MenuItem('Notifications',  Icons.notifications_rounded, '/notifications', AppColors.red),
    _MenuItem('Settings',       Icons.settings_rounded,      '/settings',      AppColors.textSecondary),
  ];

  @override
  Widget build(BuildContext context) {
    final surface = AppColors.surfaceOf(context);
    final border = AppColors.borderOf(context);
    return BlocBuilder<ShellBloc,ShellState>(
      builder:(ctx,state) => Container(
        decoration: BoxDecoration(
          color: surface,
          border: Border(right:BorderSide(color:border,width:0.5)),
          boxShadow: [
            BoxShadow(color: AppColors.holoBlue.withOpacity(0.08), blurRadius:24, spreadRadius:-4),
          ],
        ),
        child: SafeArea(
          child: Column(children:[
            _buildHeader(ctx),
            Expanded(child: ListView(padding:const EdgeInsets.symmetric(vertical:8), children:[
              ...List.generate(_items.length, (i) =>
                _MenuTile(item:_items[i], isActive:state.selectedIndex==i, index:i, delay:i*40)),
              Divider(color:border, height:24),
              _buildLogout(ctx),
            ])),
            _buildFooter(context),
          ]),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext ctx) {
    final textPrimary = AppColors.textPrimaryOf(ctx);
    final textSecondary = AppColors.textSecondaryOf(ctx);
    final border = AppColors.borderOf(ctx);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(bottom:BorderSide(color:border,width:0.5))),
      child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
        Row(children:[
          _Avatar(url:_user?.avatarUrl, initials:_user?.initials??'?'),
          const Spacer(),
          IconButton(icon:Icon(Icons.close,color:textSecondary),
            onPressed:()=>ctx.read<ShellBloc>().add(CloseMenu())),
        ]),
        const SizedBox(height:12),
        Text(_user?.fullName??'Loading...', style:AppTextStyles.titleLarge.copyWith(color: textPrimary)),
        const SizedBox(height:2),
        Text(_user?.studentId??'', style:AppTextStyles.monoSmall.copyWith(color: textSecondary)),
        const SizedBox(height:8),
        Row(children:[
          _Chip(_user?.department??'', AppColors.holoBlue),
          const SizedBox(width:6),
          _Chip('Sem ${_user?.semester??1}', AppColors.green),
        ]),
        const SizedBox(height:12),
        GestureDetector(
          onTap:()=>ctx.go('/vr-id'),
          child: Container(
            padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),
            decoration:BoxDecoration(
              border:Border.all(color:AppColors.gold.withOpacity(0.5)),
              borderRadius:BorderRadius.circular(8),
              gradient: LinearGradient(colors:[
                AppColors.gold.withOpacity(0.08), Colors.transparent,
              ]),
            ),
            child: Row(mainAxisSize:MainAxisSize.min, children:[
              const Icon(Icons.qr_code_rounded,color:AppColors.gold,size:16),
              const SizedBox(width:8),
              Text('My VR-ID', style:AppTextStyles.labelSmall.copyWith(color:AppColors.gold)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildLogout(BuildContext ctx) {
    return ListTile(
      leading:Container(width:36,height:36,
        decoration:BoxDecoration(color:AppColors.red.withOpacity(0.1),borderRadius:BorderRadius.circular(10)),
        child:const Icon(Icons.logout_rounded,color:AppColors.red,size:18)),
      title:const Text('Logout',style:TextStyle(color:AppColors.red,fontWeight:FontWeight.w600,fontSize:14)),
      onTap:() async {
        final surface = AppColors.surfaceOf(ctx);
        final textPrimary = AppColors.textPrimaryOf(ctx);
        final textSecondary = AppColors.textSecondaryOf(ctx);
        final confirm = await showDialog<bool>(
          context:ctx,
          builder:(_)=>AlertDialog(
            backgroundColor:surface,
            title:Text('Log out?',style:TextStyle(color:textPrimary)),
            content:Text('Are you sure you want to sign out?',
              style:TextStyle(color:textSecondary)),
            actions:[
              TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancel')),
              TextButton(onPressed:()=>Navigator.pop(ctx,true),
                child:const Text('Logout',style:TextStyle(color:AppColors.red))),
            ],
          ),
        );
        if(confirm==true) {
          await Supabase.instance.client.auth.signOut();
          if(ctx.mounted) ctx.go('/auth/login');
        }
      },
    );
  }

  Widget _buildFooter(BuildContext context) {
    final textSecondary = AppColors.textSecondaryOf(context);
    return Container(
      padding:const EdgeInsets.all(16),
      child:Column(children:[
        Text('AFOS v1.0.0', style:AppTextStyles.monoSmall.copyWith(color: textSecondary)),
        const SizedBox(height:2),
        Text('Daffodil International University', style:AppTextStyles.labelSmall.copyWith(color: textSecondary)),
      ]),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final _MenuItem item;
  final bool isActive;
  final int index, delay;
  const _MenuTile({required this.item,required this.isActive,required this.index,required this.delay});
  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    return Padding(
      padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),
      child: Material(
        color:isActive?item.color.withOpacity(0.12):Colors.transparent,
        borderRadius:BorderRadius.circular(10),
        child: InkWell(
          borderRadius:BorderRadius.circular(10),
          onTap:(){
            context.read<ShellBloc>().add(SelectItem(index));
            context.go(item.route);
          },
          child: Container(
            padding:const EdgeInsets.symmetric(horizontal:12,vertical:10),
            decoration:isActive?BoxDecoration(
              border:Border(left:BorderSide(color:item.color,width:3)),
            ):null,
            child: Row(children:[
              Container(width:34,height:34,
                decoration:BoxDecoration(
                  color:item.color.withOpacity(0.15),
                  borderRadius:BorderRadius.circular(9)),
                child:Icon(item.icon,color:item.color,size:18)),
              const SizedBox(width:12),
              Text(item.label, style:TextStyle(
                color:isActive?item.color:textPrimary,
                fontSize:14, fontWeight:isActive?FontWeight.w600:FontWeight.w400)),
            ]),
          ),
        ),
      ),
    ).animate(delay:Duration(milliseconds:delay)).fadeIn(duration:280.ms,curve:Curves.easeOutCubic).slideX(begin:-0.05,curve:Curves.easeOutCubic);
  }
}

class _Avatar extends StatelessWidget {
  final String? url; final String initials;
  const _Avatar({this.url, required this.initials});
  @override
  Widget build(BuildContext context) {
    return Container(
      width:52,height:52,
      decoration:BoxDecoration(shape:BoxShape.circle,
        border:Border.all(color:AppColors.holoBlue.withOpacity(0.5),width:2),
        boxShadow:[BoxShadow(color:AppColors.holoBlue.withOpacity(0.2),blurRadius:12,spreadRadius:-2)]),
      child: ClipOval(child: url!=null && url!.isNotEmpty
        ? CachedNetworkImage(imageUrl:url!,fit:BoxFit.cover,
            errorWidget:(_,__,___)=>_initials(context, initials))
        : _initials(context, initials)),
    );
  }
  Widget _initials(BuildContext context, String i) => Container(color:AppColors.surfaceOf(context),
    child:Center(child:Text(i,style:const TextStyle(color:AppColors.holoBlue,fontSize:18,fontWeight:FontWeight.bold))));
}

class _Chip extends StatelessWidget {
  final String label; final Color color;
  const _Chip(this.label,this.color);
  @override
  Widget build(BuildContext context) => Container(
    padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
    decoration:BoxDecoration(color:color.withOpacity(0.15),borderRadius:BorderRadius.circular(20),
      border:Border.all(color:color.withOpacity(0.3))),
    child:Text(label,style:TextStyle(color:color,fontSize:11,fontWeight:FontWeight.w600)),
  );
}

class _MenuItem {
  final String label, route;
  final IconData icon;
  final Color color;
  const _MenuItem(this.label,this.icon,this.route,this.color);
}
