import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../bloc/shell_bloc.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
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
      final p = await SupabaseConfig.client.from('profiles')
          .select('*, teachers(designation), staff(designation)').eq('id',uid).single();
      if(mounted) setState(()=>_user=UserModel.fromJson(p));
    } catch(_) {}
  }

  // Base items every role gets. Everyone can browse Clubs (read-only for
  // non-students — the Join/Apply actions inside are gated to role==student
  // both client-side and at the RLS layer). Library stays student-only
  // (see _studentOnlyItems) since it's a personal borrowing record, not
  // something to just "view".
  static const _commonItems = [
    _MenuItem('Dashboard',      AppIcons.dashboard,   '/home',          AppColors.blue),
    _MenuItem('Class Schedule', AppIcons.schedule,    '/schedule',      Color(0xFF1E6FFF)),
    _MenuItem('Transport',      AppIcons.transport,   '/transport',     AppColors.teal),
    _MenuItem('Lost & Found',   AppIcons.lostFound,   '/lost-found',    AppColors.coral),
    _MenuItem('Clubs',          AppIcons.clubs,       '/clubs',         AppColors.pink),
    _MenuItem('Results',        AppIcons.results,     '/grades',        AppColors.gold),
    _MenuItem('Assignments',    AppIcons.assignments, '/assignments',   AppColors.holoTeal),
    _MenuItem('Mentorship',     AppIcons.mentorship,  '/mentorship',    Color(0xFF60A5FA)),
    _MenuItem('Dept Chat',      AppIcons.deptChat,    '/dept-chat',     AppColors.indigo),
    _MenuItem('Nearby SOS Alerts', Icons.sos_rounded, '/sos/nearby',    AppColors.red),
    _MenuItem('Notifications',  AppIcons.notifications, '/notifications', AppColors.red),
    _MenuItem('Settings',       AppIcons.settings,    '/settings',      AppColors.textSecondary),
  ];

  // Student-only: hall allocation, payment, exam seating, and library are
  // student-personal records — a teacher/staff member has none of their own.
  static const _studentOnlyItems = [
    _MenuItem('Library',        AppIcons.library,     '/library',       AppColors.purple),
    _MenuItem('Hall Allocation',AppIcons.hall,         '/hall',          AppColors.amber),
    _MenuItem('Payment',        AppIcons.payment,      '/payment',       AppColors.gold),
    _MenuItem('Exam Seat Plan', AppIcons.examSeat,     '/exam-seat',     AppColors.orange),
  ];

  static const _conferenceRoomItem =
    _MenuItem('Conference Room', AppIcons.conferenceRoom, '/conference-room', AppColors.holoTeal);

  static const _roomAvailabilityItem =
    _MenuItem('Room Availability', AppIcons.schedule, '/room-availability', AppColors.holoTeal);

  static const _adminItems = [
    _MenuItem('Upload Routine/Transport', AppIcons.uploadRoutine, '/admin/upload', AppColors.holoBlue),
    _MenuItem('Manage Hall', AppIcons.hall, '/admin/hall', AppColors.amber),
    _MenuItem('Manage Library', AppIcons.library, '/admin/library', AppColors.purple),
    _MenuItem('Moderate Dept Chats', AppIcons.moderateChat, '/admin/dept-chat', AppColors.indigo),
    _MenuItem('Manage Faculties', AppIcons.faculties, '/admin/faculties', AppColors.holoviolet),
    _MenuItem('Manage Departments', AppIcons.hall, '/admin/departments', AppColors.holoTeal),
    _MenuItem('Notices & Rules', AppIcons.notices, '/manage-notices', AppColors.red),
    _MenuItem('Manage Exam Seats', AppIcons.examSeat, '/manage-exam-seats', AppColors.orange),
    _sosAdminItem,
  ];

  static const _libraryAdminItem =
    _MenuItem('Manage Library', AppIcons.library, '/admin/library', AppColors.purple);

  // Staff should be able to run and help too, same as any other admin-tier
  // role -- but the staff branch below doesn't fall through to
  // _adminItems, so this needs adding to both places explicitly.
  static const _sosAdminItem =
    _MenuItem('Manage SOS Alerts', Icons.sos_rounded, '/admin/sos', AppColors.red);

  static const _noticesItem =
    _MenuItem('Notices & Rules', AppIcons.notices, '/manage-notices', AppColors.red);

  static const _examSeatsItem =
    _MenuItem('Manage Exam Seats', AppIcons.examSeat, '/manage-exam-seats', AppColors.orange);

  // super_admin only — not even ordinary admin/dept_admin get this (see the
  // dedicated /admin/users redirect guard in app_router.dart).
  static const _superAdminItems = [
    _MenuItem('Manage Users', AppIcons.manageUsers, '/admin/users', AppColors.holoviolet),
    _MenuItem('Manage Clubs', AppIcons.manageClubs, '/admin/clubs', AppColors.holoviolet),
    _MenuItem('Conference Rooms', AppIcons.conferenceRoom, '/admin/conference-rooms', AppColors.holoviolet),
    _MenuItem('Feedback & Contributions', Icons.feedback_outlined, '/admin/feedback', AppColors.holoviolet),
  ];

  // Semester only means something for a student — a teacher/staff/admin
  // profile row still carries a leftover default `semester` value, so show
  // role-appropriate info instead for everyone else.
  String get _secondaryChipLabel {
    final role = _user?.role;
    if (role == null) return '';
    if (_user!.isStudent) return 'Sem ${_user!.semester}';
    if (_user!.isTeacher) return _user!.designation ?? 'Faculty';
    if (_user!.isStaff) return _user!.designation ?? 'Staff';
    switch (role) {
      case 'super_admin': return 'Super Admin';
      case 'dept_admin': return 'Dept Admin';
      case 'admin': return 'Admin';
      case 'exam_controller': return 'Exam Controller';
      default: return role;
    }
  }

  List<_MenuItem> get _effectiveItems {
    final role = _user?.role;
    // Admin-tier roles get oversight tools (Manage Hall, etc.), not the
    // student-personal-record screens themselves — an admin has no hall
    // room, exam seat, or payment of their own to apply for, so showing
    // those would be nonsensical, not just redundant.
    if (role == 'super_admin') {
      return [..._commonItems, ..._adminItems, ..._superAdminItems];
    }
    if (const ['admin', 'dept_admin'].contains(role)) {
      return [..._commonItems, ..._adminItems];
    }
    if (role == 'teacher') {
      // Teachers can author course notices/rules but don't get the rest
      // of the admin toolset (routine upload, faculty/department registry).
      return [..._commonItems, _noticesItem, _conferenceRoomItem, _roomAvailabilityItem];
    }
    if (role == 'staff') {
      return [..._commonItems, _conferenceRoomItem, _libraryAdminItem, _sosAdminItem];
    }
    if (role == 'exam_controller') {
      // Was previously falling through to the student branch below,
      // showing personal-record items (Hall/Payment/Library) that make no
      // sense for this role — same class of bug as the admin-tier fix
      // above, just never caught for this specific role until now.
      return [..._commonItems, _examSeatsItem];
    }
    return [..._commonItems, ..._studentOnlyItems];
  }

  @override
  Widget build(BuildContext context) {
    final surface = AppColors.surfaceOf(context);
    final border = AppColors.borderOf(context);
    return BlocConsumer<ShellBloc,ShellState>(
      // The menu is a permanently-mounted, just-translated-offscreen widget
      // (see app_shell.dart's AnimatedPositioned) rather than being rebuilt
      // per open — without this, editing batch/section/designation via
      // Settings or Complete Profile and returning here would keep showing
      // whatever was fetched once at app start.
      listenWhen: (prev, curr) => !prev.isOpen && curr.isOpen,
      listener: (ctx, state) => _loadUser(),
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
              ...List.generate(_effectiveItems.length, (i) =>
                _MenuTile(item:_effectiveItems[i], isActive:state.selectedIndex==i, index:i, delay:i*40)),
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
          GestureDetector(
            onTap: () { ctx.read<ShellBloc>().add(CloseMenu()); ctx.push('/complete-profile'); },
            child: _Avatar(url:_user?.avatarUrl, initials:_user?.initials??'?', isSuperAdmin: _user?.role == 'super_admin')),
          const Spacer(),
          IconButton(icon:Icon(AppIcons.close,color:textSecondary),
            onPressed:()=>ctx.read<ShellBloc>().add(CloseMenu())),
        ]),
        const SizedBox(height:12),
        Text(_user?.fullName??'Loading...', style:AppTextStyles.titleLarge.copyWith(color: textPrimary),
          maxLines:1, overflow:TextOverflow.ellipsis),
        const SizedBox(height:2),
        Text(_user?.studentId??'', style:AppTextStyles.monoSmall.copyWith(color: textSecondary),
          maxLines:1, overflow:TextOverflow.ellipsis),
        const SizedBox(height:8),
        Row(children:[
          Flexible(child: _Chip(_user?.department??'', AppColors.holoBlue)),
          const SizedBox(width:6),
          _Chip(_secondaryChipLabel, AppColors.green),
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
              const Icon(AppIcons.vrId,color:AppColors.gold,size:16),
              const SizedBox(width:8),
              Text('My VR-ID', style:AppTextStyles.labelSmall.copyWith(color:AppColors.gold)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildLogout(BuildContext ctx) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _confirmLogout(ctx),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: [
                  AppColors.red.withOpacity(0.14),
                  AppColors.red.withOpacity(0.05),
                ]),
                border: Border.all(color: AppColors.red.withOpacity(0.25))),
            child: Row(children: [
              Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: AppColors.red.withOpacity(0.16), shape: BoxShape.circle),
                  child: const Icon(AppIcons.logout, color: AppColors.red, size: 18)),
              const SizedBox(width: 12),
              const Text('Logout', style: TextStyle(color: AppColors.red, fontWeight: FontWeight.w700, fontSize: 14)),
              const Spacer(),
              Icon(Icons.chevron_right_rounded, color: AppColors.red.withOpacity(0.6), size: 20),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext ctx) async {
    final surface = AppColors.surfaceOf(ctx);
    final textPrimary = AppColors.textPrimaryOf(ctx);
    final textSecondary = AppColors.textSecondaryOf(ctx);
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: surface,
        title: Text('Log out?', style: TextStyle(color: textPrimary)),
        content: Text('Are you sure you want to sign out?', style: TextStyle(color: textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Logout', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await Supabase.instance.client.auth.signOut();
      if (ctx.mounted) ctx.go('/auth/login');
    }
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
            context.push(item.route);
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
  final String? url; final String initials; final bool isSuperAdmin;
  const _Avatar({this.url, required this.initials, this.isSuperAdmin = false});
  @override
  Widget build(BuildContext context) {
    final ringColor = isSuperAdmin ? AppColors.holoviolet : AppColors.holoBlue;
    return Container(
      width:52,height:52,
      decoration:BoxDecoration(shape:BoxShape.circle,
        border:Border.all(color:ringColor.withOpacity(0.6),width: isSuperAdmin ? 3 : 2),
        boxShadow:[BoxShadow(color:ringColor.withOpacity(0.25),blurRadius:12,spreadRadius:-2)]),
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
    child:Text(label,style:TextStyle(color:color,fontSize:11,fontWeight:FontWeight.w600),
      maxLines:1,overflow:TextOverflow.ellipsis),
  );
}

class _MenuItem {
  final String label, route;
  final IconData icon;
  final Color color;
  const _MenuItem(this.label,this.icon,this.route,this.color);
}
