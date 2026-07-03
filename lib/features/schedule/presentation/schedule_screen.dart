import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/models/class_slot.dart';
import '../data/repositories/schedule_repository.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override State<ScheduleScreen> createState() => _ScheduleState();
}

class _ScheduleState extends State<ScheduleScreen> with SingleTickerProviderStateMixin {
  int _day = DateTime.now().weekday - 1; // Mon=0
  UserModel? _user;
  bool _loading = true;
  final _repo = ScheduleRepository();
  static const _days = ['Mon','Tue','Wed','Thu','Fri','Sat'];

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final uid = SupabaseConfig.uid;
    if(uid==null) { setState(()=>_loading=false); return; }
    final p = await SupabaseConfig.client.from('profiles').select().eq('id',uid).single();
    if(mounted) setState(()=>_user=UserModel.fromJson(p));
    setState(()=>_loading=false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: AfosAppBar(title:'Class Schedule'),
      body: Column(children:[
        _DaySelector(selected:_day, onTap:(i)=>setState(()=>_day=i)),
        Expanded(child: _loading
          ? const Padding(padding:EdgeInsets.all(16),child:ShimmerList())
          : _user==null
            ? Center(child:Text('Could not load profile',
                style:TextStyle(color:AppColors.textSecondaryOf(context))))
            : StreamBuilder<List<ClassSlot>>(
                stream: _repo.watchSchedule(_user!.department, _user!.semester, _day),
                builder:(ctx,snap) {
                  if(snap.connectionState==ConnectionState.waiting)
                    return const Padding(padding:EdgeInsets.all(16),child:ShimmerList());
                  final slots = snap.data??[];
                  if(slots.isEmpty) return EmptyState(
                    icon:Icons.calendar_today_rounded,
                    title:'No classes ${_days[_day]}',
                    subtitle:'Enjoy your free day!');
                  return ListView.builder(
                    padding:const EdgeInsets.all(16),
                    itemCount:slots.length,
                    itemBuilder:(ctx,i)=>_ClassCard(slot:slots[i],index:i));
                })),
      ]),
    );
  }
}

class _DaySelector extends StatelessWidget {
  final int selected; final ValueChanged<int> onTap;
  const _DaySelector({required this.selected, required this.onTap});
  static const _days = ['Mon','Tue','Wed','Thu','Fri','Sat'];
  @override
  Widget build(BuildContext context) {
    return Container(
      height:52, color:AppColors.surfaceOf(context),
      child: ListView.builder(
        scrollDirection:Axis.horizontal, padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),
        itemCount:_days.length,
        itemBuilder:(ctx,i) {
          final sel = selected==i;
          return GestureDetector(
            onTap:()=>onTap(i),
            child: AnimatedContainer(
              duration:200.ms, curve: Curves.easeOutCubic, margin:const EdgeInsets.only(right:8),
              padding:const EdgeInsets.symmetric(horizontal:16,vertical:6),
              decoration:BoxDecoration(
                gradient: sel ? AppColors.holoGradient : null,
                color:sel?null:AppColors.glassFill(context),
                borderRadius:BorderRadius.circular(20),
                border:Border.all(color:sel?Colors.transparent:AppColors.glassBorder(context),width:0.5)),
              child:Text(_days[i],style:TextStyle(color:sel?Colors.white:AppColors.textSecondaryOf(context),
                fontSize:13,fontWeight:sel?FontWeight.w600:FontWeight.w400)),
            ),
          );
        }),
    );
  }
}

class _ClassCard extends StatelessWidget {
  final ClassSlot slot; final int index;
  const _ClassCard({required this.slot,required this.index});
  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    return RepaintBoundary(
      child: Container(
        margin:const EdgeInsets.only(bottom:12),
        decoration:BoxDecoration(
          borderRadius:BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [AppColors.holoBlue.withOpacity(AppColors.isDark(context)?0.3:0.2),
                     AppColors.holoTeal.withOpacity(0.12)]),
        ),
        padding: const EdgeInsets.all(1),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(15)),
          child: Stack(children:[
            Padding(
              padding:const EdgeInsets.all(16),
              child: Row(children:[
                Column(children:[
                  Text(slot.startTime,style:AppTextStyles.monoSmall.copyWith(color:AppColors.holoBlue)),
                  Container(margin:const EdgeInsets.symmetric(vertical:4),width:1,height:24,color:AppColors.borderOf(context)),
                  Text(slot.endTime,style:AppTextStyles.monoSmall.copyWith(color:textSecondary)),
                ]),
                const SizedBox(width:14),
                Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(slot.subject,style:AppTextStyles.titleMedium.copyWith(color:textPrimary),maxLines:2),
                  const SizedBox(height:6),
                  Row(children:[
                    Icon(Icons.location_on_rounded,size:13,color:textSecondary),
                    const SizedBox(width:3),
                    Text('${slot.building} · ${slot.roomNumber}',style:AppTextStyles.bodyMedium.copyWith(color:textSecondary)),
                  ]),
                  const SizedBox(height:3),
                  Row(children:[
                    Icon(Icons.person_outline,size:13,color:textSecondary),
                    const SizedBox(width:3),
                    Text(slot.teacherName,style:AppTextStyles.bodyMedium.copyWith(color:textSecondary)),
                  ]),
                ])),
                Container(
                  padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
                  decoration:BoxDecoration(color:AppColors.holoBlue.withOpacity(0.12),borderRadius:BorderRadius.circular(6)),
                  child:Text('${slot.creditHours}cr',style:const TextStyle(color:AppColors.holoBlue,fontSize:11,fontWeight:FontWeight.w600))),
              ]),
            ),
            if(slot.isCancelled) Positioned.fill(
              child:Container(
                decoration:BoxDecoration(color:AppColors.red.withOpacity(0.88),borderRadius:BorderRadius.circular(15)),
                alignment:Alignment.center,
                child:Column(mainAxisSize:MainAxisSize.min,children:[
                  const Icon(Icons.cancel_rounded,color:Colors.white,size:32),
                  const SizedBox(height:6),
                  const Text('CLASS CANCELLED',style:TextStyle(color:Colors.white,fontSize:16,fontWeight:FontWeight.w800,letterSpacing:1.5)),
                  if(slot.cancelledReason!=null) Padding(padding:const EdgeInsets.only(top:4),
                    child:Text(slot.cancelledReason!,style:const TextStyle(color:Colors.white70,fontSize:12))),
                ]),
              ),
            ),
          ]),
        ),
      ),
    ).animate(delay:Duration(milliseconds:index*80))
        .fadeIn(curve: Curves.easeOutCubic).slideY(begin:0.05, curve: Curves.easeOutCubic);
  }
}
