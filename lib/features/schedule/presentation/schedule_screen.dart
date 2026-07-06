import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/shimmer_card.dart';
import '../../notifications/data/repositories/notification_service.dart';
import '../../shell/presentation/top_app_bar.dart';
import '../data/models/class_slot.dart';
import '../data/repositories/schedule_repository.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override State<ScheduleScreen> createState() => _ScheduleState();
}

class _ScheduleState extends State<ScheduleScreen> with SingleTickerProviderStateMixin {
  // schedule_slots.day_of_week is stored Sat=0..Thu=5 (Fri=6, DIU's weekly
  // holiday, matching parse-routine's dayMap/DAY_NAMES) — NOT the ISO
  // Mon=1..Sun=7 that DateTime.weekday uses, so this remaps rather than
  // just subtracting 1 (which both pointed at the wrong day's classes and
  // overflowed the 6-entry label list on a Sunday: weekday=7 → index 6).
  int _day = (DateTime.now().weekday + 1) % 7;
  UserModel? _user;
  String? _myBatch, _mySection, _myTeacherInitial;
  bool _loading = true;
  late TabController _tab;
  final _repo = ScheduleRepository();
  Map<String, ({String fullName, String? avatarUrl})> _teacherDirectory = const {};
  static const _days = ['Sat','Sun','Mon','Tue','Wed','Thu','Fri'];

  bool get _isFacultyRole => _user?.role == 'teacher';
  // Class schedule only ever meant anything for a student's own
  // batch+section or a teacher's own taught classes — admin/staff/
  // super_admin/dept_admin/exam_controller have neither, so the old
  // fallback to `watchSchedule(department, semester, day)` was showing
  // that role a semi-arbitrary department-wide list using their profile's
  // leftover default department/semester values, which reads as "fake/mock
  // data" to someone who has no personal schedule to begin with.
  bool get _scheduleNotApplicable => _user != null && !_isFacultyRole && _user!.role != 'student';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _loadUser();
    _repo.getTeacherDirectory().then((dir) { if (mounted) setState(() => _teacherDirectory = dir); });
  }

  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  Future<void> _loadUser() async {
    final uid = SupabaseConfig.uid;
    if(uid==null) { setState(()=>_loading=false); return; }
    final p = await SupabaseConfig.client.from('profiles').select().eq('id',uid).single();
    if(mounted) setState(() {
      _user = UserModel.fromJson(p);
      _myBatch = p['batch'] as String?;
      _mySection = p['section'] as String?;
      _myTeacherInitial = p['teacher_initial'] as String?;
    });
    setState(()=>_loading=false);
  }

  Stream<List<ClassSlot>> _classesStream() {
    if (_isFacultyRole && _myTeacherInitial != null && _myTeacherInitial!.isNotEmpty) {
      return _repo.watchMyClassesAsTeacher(_myTeacherInitial!, _day);
    }
    if (!_isFacultyRole && _myBatch != null && _myBatch!.isNotEmpty && _mySection != null && _mySection!.isNotEmpty) {
      return _repo.watchMyClassesAsStudent(_user!.department, _myBatch!, _mySection!, _day);
    }
    return _repo.watchSchedule(_user!.department, _user!.semester, _day);
  }

  @override
  Widget build(BuildContext context) {
    final hasRoutineInfo = _isFacultyRole
        ? (_myTeacherInitial?.isNotEmpty ?? false)
        : ((_myBatch?.isNotEmpty ?? false) && (_mySection?.isNotEmpty ?? false));

    if (_scheduleNotApplicable) {
      return Scaffold(
        backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
        appBar: AfosAppBar(title:'Class Schedule'),
        body: EmptyState(icon: Icons.calendar_today_outlined, title: 'Not applicable for your role',
            subtitle: 'Class schedules are personal to students and teachers only.'),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.isDark(context) ? AppColors.background : AppColors.lightBg,
      appBar: AfosAppBar(title:'Class Schedule'),
      body: Column(children:[
        Container(color: AppColors.surfaceOf(context), child: TabBar(
            controller: _tab, labelColor: AppColors.blue,
            unselectedLabelColor: AppColors.textSecondaryOf(context), indicatorColor: AppColors.blue,
            tabs: const [Tab(text: 'Class Routine'), Tab(text: 'Exam Routine')])),
        if (!_loading && !hasRoutineInfo) Container(
            width: double.infinity, color: AppColors.gold.withOpacity(0.08),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Text(
                _isFacultyRole
                    ? 'Set your teacher initials in Settings to see only your own classes.'
                    : 'Set your batch/section in Settings to see only your own classes.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.gold.withOpacity(0.9), fontSize: 12))),
        Expanded(child: TabBarView(controller: _tab, children: [
          Column(children:[
            _DaySelector(selected:_day, onTap:(i)=>setState(()=>_day=i)),
            Expanded(child: _loading
              ? const Padding(padding:EdgeInsets.all(16),child:ShimmerList())
              : _user==null
                ? Center(child:Text('Could not load profile',
                    style:TextStyle(color:AppColors.textSecondaryOf(context))))
                : StreamBuilder<List<ClassSlot>>(
                    stream: _classesStream(),
                    builder:(ctx,snap) {
                      if(snap.connectionState==ConnectionState.waiting)
                        return const Padding(padding:EdgeInsets.all(16),child:ShimmerList());
                      final slots = snap.data??[];
                      if(slots.isEmpty) return EmptyState(
                        icon:AppIcons.schedule,
                        title:'No classes ${_days[_day]}',
                        subtitle:'Enjoy your free day!');
                      return Column(children: [
                        if (_isFacultyRole) Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Text('${slots.length} class${slots.length == 1 ? '' : 'es'} on ${_days[_day]}',
                              style: AppTextStyles.bodyMedium.copyWith(
                                  color: AppColors.textSecondaryOf(context), fontWeight: FontWeight.w600))),
                        Expanded(child: ListView.builder(
                          padding:const EdgeInsets.all(16),
                          itemCount:slots.length,
                          itemBuilder:(ctx,i)=>_ClassCard(slot:slots[i],index:i,teacherDirectory:_teacherDirectory,
                            isTeacher:_isFacultyRole, repo:_repo))),
                      ]);
                    })),
          ]),
          _loading || _user == null
              ? const Padding(padding: EdgeInsets.all(16), child: ShimmerList())
              : _ExamRoutineTab(repo: _repo, department: _user!.department, batch: _myBatch),
        ])),
      ]),
    );
  }
}

class _ExamRoutineTab extends StatefulWidget {
  final ScheduleRepository repo; final String department; final String? batch;
  const _ExamRoutineTab({required this.repo, required this.department, required this.batch});
  @override State<_ExamRoutineTab> createState() => _ExamRoutineTabState();
}

class _ExamRoutineTabState extends State<_ExamRoutineTab> {
  List<Map<String, dynamic>> _exams = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await widget.repo.getMyExams(dept: widget.department, batch: widget.batch);
      if (mounted) setState(() { _exams = res; _loading = false; });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(16), child: ShimmerList());
    if (_exams.isEmpty) return EmptyState(icon: Icons.assignment_outlined,
        title: 'No exam routine yet', subtitle: 'Mid/final term exams will appear here once published');
    return RefreshIndicator(onRefresh: _load, color: AppColors.blue,
        child: ListView.builder(padding: const EdgeInsets.all(16), itemCount: _exams.length + 1,
            itemBuilder: (ctx, i) {
              if (i == 0) return Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [
                Icon(Icons.info_outline_rounded, size: 14, color: AppColors.textSecondaryOf(context)),
                const SizedBox(width: 6),
                Expanded(child: Text('This exam routine stays valid until the next one is uploaded by admin.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondaryOf(context)))),
              ]));
              return _ExamCard(exam: _exams[i - 1], index: i - 1);
            }));
  }
}

class _ExamCard extends StatelessWidget {
  final Map<String, dynamic> exam; final int index;
  const _ExamCard({required this.exam, required this.index});
  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final examType = exam['exam_type'] as String? ?? 'final';
    final color = examType == 'mid' ? AppColors.holoTeal : AppColors.holoBlue;
    final date = exam['exam_date'] != null ? DateTime.tryParse(exam['exam_date']) : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceOf(context), borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3), width: 0.7)),
      child: Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(examType.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(exam['subject'] ?? exam['subject_code'] ?? '', style: AppTextStyles.titleMedium.copyWith(color: textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Row(children: [
            if (date != null) ...[
              Icon(Icons.event_rounded, size: 12, color: textSecondary),
              const SizedBox(width: 3),
              Text('${date.day}/${date.month}/${date.year}', style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
              const SizedBox(width: 10),
            ],
            if (exam['start_time'] != null) ...[
              Icon(Icons.access_time_rounded, size: 12, color: textSecondary),
              const SizedBox(width: 3),
              Text(exam['start_time'].toString().substring(0, 5), style: AppTextStyles.bodyMedium.copyWith(color: textSecondary)),
            ],
          ]),
        ])),
      ]),
    ).animate(delay: Duration(milliseconds: index * 60)).fadeIn().slideY(begin: 0.05);
  }
}

class _DaySelector extends StatelessWidget {
  final int selected; final ValueChanged<int> onTap;
  const _DaySelector({required this.selected, required this.onTap});
  static const _days = ['Sat','Sun','Mon','Tue','Wed','Thu','Fri'];
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
  final Map<String, ({String fullName, String? avatarUrl})> teacherDirectory;
  final bool isTeacher;
  final ScheduleRepository? repo;
  const _ClassCard({required this.slot,required this.index, this.teacherDirectory = const {},
    this.isTeacher = false, this.repo});

  Future<void> _messageCr(BuildContext context) async {
    if (repo == null || slot.batch == null || slot.section == null) return;
    final cr = await repo!.findSectionCr(slot.department, slot.batch!, slot.section!);
    if (!context.mounted) return;
    if (cr == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No CR set for this section yet'), backgroundColor: AppColors.amber));
      return;
    }
    final msgCtrl = TextEditingController();
    await showModalBottomSheet(
        context: context, isScrollControlled: true,
        backgroundColor: AppColors.surfaceOf(context),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (sheetCtx) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Message ${cr['full_name']}', style: AppTextStyles.headlineLarge.copyWith(color: AppColors.textPrimaryOf(sheetCtx))),
              const SizedBox(height: 6),
              Text('CR · ${slot.subject} · Batch ${slot.batch} · Section ${slot.section}',
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondaryOf(sheetCtx))),
              const SizedBox(height: 16),
              TextField(controller: msgCtrl, maxLines: 3, style: TextStyle(color: AppColors.textPrimaryOf(sheetCtx)),
                  decoration: const InputDecoration(hintText: 'Message for the class...')),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: ElevatedButton(
                  onPressed: () async {
                    if (msgCtrl.text.trim().isEmpty) return;
                    Navigator.pop(sheetCtx);
                    await NotificationService.sendToUsers(
                      userIds: [cr['id'] as String],
                      title: '${slot.subject} — message from your teacher',
                      message: msgCtrl.text.trim(),
                      category: 'general',
                    );
                  },
                  child: const Text('Send'))),
            ])));
  }

  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    final textSecondary = AppColors.textSecondaryOf(context);
    final teacher = teacherDirectory[slot.teacherName.toLowerCase()];
    final teacherLabel = teacher?.fullName ?? slot.teacherName;
    final teacherAvatar = teacher?.avatarUrl;
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
                  const SizedBox(height:5),
                  Row(children:[
                    CircleAvatar(radius:9, backgroundColor:AppColors.holoBlue.withOpacity(0.15),
                      backgroundImage: teacherAvatar!=null ? CachedNetworkImageProvider(teacherAvatar) : null,
                      child: teacherAvatar==null
                        ? Icon(Icons.person_outline, size:11, color:AppColors.holoBlue)
                        : null),
                    const SizedBox(width:5),
                    Expanded(child: Text(teacherLabel,style:AppTextStyles.bodyMedium.copyWith(color:textSecondary),
                      maxLines:1, overflow:TextOverflow.ellipsis)),
                  ]),
                ])),
                Container(
                  padding:const EdgeInsets.symmetric(horizontal:8,vertical:4),
                  decoration:BoxDecoration(color:AppColors.holoBlue.withOpacity(0.12),borderRadius:BorderRadius.circular(6)),
                  child:Text('${slot.creditHours}cr',style:const TextStyle(color:AppColors.holoBlue,fontSize:11,fontWeight:FontWeight.w600))),
                if (isTeacher && slot.batch != null && slot.section != null)
                  IconButton(icon: const Icon(Icons.forum_outlined, size: 18, color: AppColors.holoTeal),
                      tooltip: 'Message Section CR', onPressed: () => _messageCr(context)),
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
