import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/shell_bloc.dart';
import '../../../config/app_config.dart';
import '../../../config/supabase_config.dart';
import '../../../core/navigation/router_location.dart';
import '../../../core/services/app_config_service.dart';
import 'dart:ui' show ImageFilter;
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/app_text_styles.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../shared/models/user_model.dart';
import '../../../shared/widgets/logout_tile.dart';
import '../../../shared/widgets/radial_logout_menu.dart';

import '../../../shared/widgets/glass_bottom_nav.dart';
class SlideMenu extends StatefulWidget {
  // True when rendered as the permanent desktop nav rail (app_shell.dart,
  // >=1024px) instead of the mobile/tablet hide-show overlay drawer -- a
  // permanent rail has nothing to "close" (no close button) and sits
  // narrower/more compact than the touch-sized mobile drawer.
  final bool permanent;
  const SlideMenu({super.key, this.permanent = false});
  @override State<SlideMenu> createState() => _SlideMenuState();
}

class _SlideMenuState extends State<SlideMenu> {
  UserModel? _user;
  bool _isCr = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
    AppConfigService.instance.ensureInit();
    // Rebuild the menu when the SOS toggle flips so the item appears/disappears
    // live without needing to reopen the drawer.
    AppConfigService.instance.sosEnabled.addListener(_onConfigChanged);
  }

  void _onConfigChanged() { if (mounted) setState(() {}); }

  @override
  void dispose() {
    AppConfigService.instance.sosEnabled.removeListener(_onConfigChanged);
    super.dispose();
  }

  Future<void> _loadUser() async {
    final uid = SupabaseConfig.uid;
    if(uid==null) return;
    try {
      final p = await SupabaseConfig.client.from('profiles')
          .select('*, teachers(designation), staff(designation), students(is_cr)').eq('id',uid).single();
      final isCr = (p['students'] as Map?)?['is_cr'] as bool? ?? false;
      if(mounted) setState(() { _user=UserModel.fromJson(p); _isCr=isCr; });
    } catch(_) {}
  }

  // Base items every role gets. Everyone can browse Clubs (read-only for
  // non-students — the Join/Apply actions inside are gated to role==student
  // both client-side and at the RLS layer). Library stays student-only
  // (see _studentOnlyItems) since it's a personal borrowing record, not
  // something to just "view".
  // The 4 quick-access destinations pinned at the top of the web rail (they
  // are the floating bottom bar's items on mobile).
  static const _quickAccessItems = [
    _MenuItem('Home',     AppIcons.dashboard, '/home',     AppColors.blue),
    _MenuItem('Search',   Icons.search_rounded, '/search', AppColors.holoTeal),
    _MenuItem('Profile',  Icons.person_rounded, '/profile', AppColors.holoBlue),
    _MenuItem('Settings', AppIcons.settings,  '/settings', AppColors.textSecondary),
  ];

  static const _commonItems = [
    _MenuItem('Dashboard',      AppIcons.dashboard,   '/home',          AppColors.blue),
    _MenuItem('Class Schedule', AppIcons.schedule,    '/schedule',      AppColors.blue),
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

  // Deliberately last in every role's list, not folded into _commonItems
  // (which every role branch below inserts more items after) -- the user
  // asked for it at the true end of the menu, not buried in the middle.
  static const _feedbackItem =
    _MenuItem('Feedback & Ideas', Icons.lightbulb_outline_rounded, '/feedback', AppColors.teal);

  // Student-only: hall allocation, payment, exam seating, and library are
  // student-personal records — a teacher/staff member has none of their own.
  static const _studentOnlyItems = [
    // ONE entry, not nine. It opens a hub listing the DIU portal pages
    // (ledger, waiver, transport card, notice board, ...). Student-only
    // because those are the student's own portal records — a teacher or staff
    // member has no ledger, waiver or transport card of their own.
    _MenuItem('DIU Portal',     Icons.language_rounded, '/portal',      AppColors.holoBlue),
    _MenuItem('Library',        AppIcons.library,     '/library',       AppColors.indigo),
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
    final items = _roleItems;
    // "Nearby SOS Alerts" is gated behind the campus-emergency SOS toggle:
    // general users see it only when a super-admin has switched SOS ON;
    // super_admin always sees it. Pure visibility filter — the route/RLS are
    // unchanged.
    final sosVisible = _user?.role == 'super_admin' || AppConfigService.instance.sosEnabled.value;
    return sosVisible ? items : items.where((it) => it.route != '/sos/nearby').toList();
  }

  List<_MenuItem> get _roleItems {
    final role = _user?.role;
    // Admin-tier roles get oversight tools (Manage Hall, etc.), not the
    // student-personal-record screens themselves — an admin has no hall
    // room, exam seat, or payment of their own to apply for, so showing
    // those would be nonsensical, not just redundant.
    if (role == 'super_admin') {
      return [..._commonItems, ..._adminItems, ..._superAdminItems, _feedbackItem];
    }
    if (const ['admin', 'dept_admin'].contains(role)) {
      return [..._commonItems, ..._adminItems, _feedbackItem];
    }
    if (role == 'teacher') {
      // Teachers can author course notices/rules but don't get the rest
      // of the admin toolset (routine upload, faculty/department registry).
      return [..._commonItems, _noticesItem, _conferenceRoomItem, _roomAvailabilityItem, _feedbackItem];
    }
    if (role == 'staff') {
      return [..._commonItems, _conferenceRoomItem, _libraryAdminItem, _sosAdminItem, _feedbackItem];
    }
    if (role == 'exam_controller') {
      // Was previously falling through to the student branch below,
      // showing personal-record items (Hall/Payment/Library) that make no
      // sense for this role — same class of bug as the admin-tier fix
      // above, just never caught for this specific role until now.
      return [..._commonItems, _examSeatsItem, _feedbackItem];
    }
    // A CR (Class Representative) is a per-section flag on the `students`
    // row, not a distinct `role` — so this is the one student-branch case
    // that needs an extra check rather than a role switch. The server-side
    // RLS policy on empty_room_requests already allows CR inserts; without
    // this the menu item simply never existed for them to reach it.
    if (_isCr) {
      return [..._commonItems, ..._studentOnlyItems, _roomAvailabilityItem, _feedbackItem];
    }
    return [..._commonItems, ..._studentOnlyItems, _feedbackItem];
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
      builder:(ctx,state) => ClipRRect(
        // Frosted glass drawer — real blur behind a translucent fill so the
        // dimmed content shows through as glass; tinted (never grey) hairline.
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: LiquidGlass.blurRaised, sigmaY: LiquidGlass.blurRaised),
          child: Container(
            decoration: BoxDecoration(
              color: Color.alphaBlend(AppColors.glassFill(context), surface.withValues(alpha: 0.62)),
              border: Border(right:BorderSide(color:AppColors.glassBorder(context),width:1)),
              boxShadow: [
                BoxShadow(color: AppColors.holoBlue.withValues(alpha:0.08), blurRadius:24, spreadRadius:-4),
              ],
            ),
            child: SafeArea(
              child: Column(children:[
                _buildHeader(ctx),
                Expanded(child: ListenableBuilder(
                  // Highlighting is route-derived, so it has to rebuild on
                  // navigation. This widget is permanently mounted and its Bloc
                  // state does not change when the route does, so without this
                  // the highlight would simply never update.
                  listenable: GoRouter.of(ctx).routerDelegate,
                  builder: (ctx, _) => ListView(padding: const EdgeInsets.fromLTRB(0, 8, 0, 8 + GlassBottomNav.navContentClearance), children:[
                  // Web rail: pin the 4 quick-access destinations at the top
                  // (the mobile floating bottom bar covers these on phones).
                  if (widget.permanent) ...[
                    for (final it in _quickAccessItems)
                      // Was `GoRouterState.of(ctx).matchedLocation == it.route`,
                      // which is stale under an imperative push -- so on desktop
                      // web, reaching a screen from a dashboard tile left the
                      // rail highlighting the previous entry.
                      _QuickRailTile(item: it, active: isRouteActive(GoRouter.of(ctx), it.route)),
                    Divider(color: border, height: 16),
                  ],
                  // Capped, not i*40 uncapped -- a role with a long menu (25
                  // items for super_admin) meant the last tile's fade-in didn't
                  // even START until ~960ms after the menu opened. Scrolling
                  // down before that elapsed (easy to do in under a second)
                  // caught later items still invisible/mid-fade, reading as
                  // "icons take time to load" rather than a deliberate
                  // animation. Capping keeps the same staggered-entrance feel
                  // for the first several tiles while guaranteeing the whole
                  // list finishes animating well within any real scroll.
                  // Was `state.selectedIndex == i` -- a ShellBloc index that only
                  // a MENU TAP ever set. Reaching the same screen from a
                  // dashboard tile, a search result or a notification left the
                  // menu highlighting whatever was last tapped in the menu, so
                  // it could point at a screen you were no longer on. Derived
                  // from the actual route now, like every other highlight.
                  ...List.generate(_effectiveItems.length, (i) =>
                    _MenuTile(
                      item: _effectiveItems[i],
                      isActive: isRouteActive(GoRouter.of(ctx), _effectiveItems[i].route),
                      index: i,
                      delay: (i*15).clamp(0,90))),
                  Divider(color:border, height:24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    // Builder so the tile gets its OWN context: the radial
                    // menu reads that render box to place the burst origin.
                    child: Builder(
                      builder: (tileCtx) =>
                          LogoutTile(label: 'Logout', onTap: () => _confirmLogout(tileCtx)),
                    ),
                  ),
                ]))),
                _buildFooter(context),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext ctx) {
    final textPrimary = AppColors.textPrimaryOf(ctx);
    final textSecondary = AppColors.textSecondaryOf(ctx);
    final isSuperAdmin = _user?.role == 'super_admin';
    final ringColor = isSuperAdmin ? AppColors.holoviolet : AppColors.holoBlue;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [ringColor.withValues(alpha:0.14), Colors.transparent]),
        border: Border(bottom: BorderSide(color: AppColors.borderOf(ctx), width: 0.5)),
      ),
      child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
        Row(children:[
          GestureDetector(
            onTap: () {
              if (!widget.permanent) ctx.read<ShellBloc>().add(CloseMenu());
              ctx.push('/complete-profile');
            },
            child: _Avatar(url:_user?.avatarUrl, initials:_user?.initials??'?', isSuperAdmin: isSuperAdmin)),
          const Spacer(),
          // A permanent rail has nothing to close.
          if (!widget.permanent)
            IconButton(icon:Icon(AppIcons.close,color:textSecondary),
              onPressed:()=>ctx.read<ShellBloc>().add(CloseMenu())),
        ]),
        const SizedBox(height:14),
        Text(_user?.fullName??'Loading...', style:AppTextStyles.titleLarge.copyWith(color: textPrimary),
          maxLines:1, overflow:TextOverflow.ellipsis),
        const SizedBox(height:3),
        Text(_user?.studentId??'', style:AppTextStyles.monoSmall.copyWith(color: textSecondary),
          maxLines:1, overflow:TextOverflow.ellipsis),
        const SizedBox(height:10),
        Row(children:[
          Flexible(child: _Chip(_user?.department??'', AppColors.holoBlue)),
          const SizedBox(width:8),
          _Chip(_secondaryChipLabel, AppColors.green),
        ]),
        const SizedBox(height:14),
        GestureDetector(
          onTap:()=>ctx.go('/vr-id'),
          child: Container(
            width: double.infinity,
            padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),
            decoration:BoxDecoration(
              border:Border.all(color:AppColors.gold.withValues(alpha:0.4)),
              borderRadius:BorderRadius.circular(12),
              gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors:[
                AppColors.gold.withValues(alpha:0.12), Colors.transparent,
              ]),
            ),
            child: Row(children:[
              Container(width: 28, height: 28, alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.gold.withValues(alpha:0.16), shape: BoxShape.circle),
                  child: const Icon(AppIcons.vrId,color:AppColors.gold,size:15)),
              const SizedBox(width:10),
              Expanded(child: Text('My VR-ID', style:AppTextStyles.labelSmall.copyWith(color:AppColors.gold, fontWeight: FontWeight.w700))),
              Icon(Icons.chevron_right_rounded, color: AppColors.gold.withValues(alpha:0.6), size: 18),
            ]),
          ),
        ),
      ]),
    );
  }

  /// [tileCtx] is the Logout row's own context — the radial fan uses its render
  /// box as the burst origin, so the options visibly spring out of the row that
  /// was tapped.
  Future<void> _confirmLogout(BuildContext tileCtx) async {
    final choice = await showRadialLogoutMenu(tileCtx);
    if (!tileCtx.mounted) return;
    await applyLogoutChoice(tileCtx, choice);
  }

  Widget _buildFooter(BuildContext context) {
    final textSecondary = AppColors.textSecondaryOf(context);
    return Container(
      padding:const EdgeInsets.all(16),
      child:Column(children:[
        Text('AFOS v${AppConfig.appVersion}', style:AppTextStyles.monoSmall.copyWith(color: textSecondary)),
        const SizedBox(height:2),
        Text('Daffodil International University', style:AppTextStyles.labelSmall.copyWith(color: textSecondary)),
      ]),
    );
  }
}

class _MenuTile extends StatefulWidget {
  final _MenuItem item;
  final bool isActive;
  final int index, delay;
  const _MenuTile({required this.item,required this.isActive,required this.index,required this.delay});
  @override State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isActive = widget.isActive;
    final textPrimary = AppColors.textPrimaryOf(context);
    return Padding(
      padding:const EdgeInsets.symmetric(horizontal:8,vertical:2),
      // MouseRegion is a no-op on touch (Android/iOS), so this only ever
      // fires with an actual mouse on web/desktop -- no platform branching
      // needed for the hover glow to stay touch-safe.
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: isActive
                ? item.color.withValues(alpha: 0.12)
                : (_hover ? item.color.withValues(alpha: 0.07) : Colors.transparent),
            border: _hover && !isActive
                ? Border.all(color: item.color.withValues(alpha: 0.25))
                : Border.all(color: Colors.transparent),
          ),
          child: Material(
        color: Colors.transparent,
        borderRadius:BorderRadius.circular(10),
        child: InkWell(
          borderRadius:BorderRadius.circular(10),
          onTap:(){
            context.read<ShellBloc>().add(CloseMenu());
            // `push`, matching every other in-shell entry point (dashboard
            // tiles, search results, notification taps). This was briefly
            // changed to `go` to fix the bottom-nav indicator, but that treated
            // a symptom: the indicator was reading `matchedLocation`, which an
            // imperative push leaves stale by design. `go` did move the
            // indicator -- by destroying the back stack, since these are all
            // flat siblings in one ShellRoute, so `go` replaces instead of
            // stacking and canPop() went false everywhere. The indicator is now
            // fixed at its source in app_shell.dart's _navIndexOf, so the verb
            // is free to be the one that preserves back behaviour.
            context.push(item.route);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.fromLTRB(
                _hover && !isActive ? 14 : 12, 10, 12, 10),
            decoration:isActive?BoxDecoration(
              border:Border(left:BorderSide(color:item.color,width:3)),
            ):null,
            child: Row(children:[
              AnimatedScale(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                scale: _hover && !isActive ? 1.08 : 1.0,
                child: Container(width:34,height:34, alignment: Alignment.center,
                decoration: isActive
                    ? BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                            colors: [item.color, item.color.withValues(alpha: 0.7)]),
                        borderRadius:BorderRadius.circular(10),
                        boxShadow: [BoxShadow(color: item.color.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))])
                    : BoxDecoration(
                        color:item.color.withValues(alpha: _hover ? 0.22 : 0.15),
                        borderRadius:BorderRadius.circular(10)),
                child:Icon(item.icon,color: isActive ? Colors.white : item.color,size:18)),
              ),
              const SizedBox(width:12),
              // Expanded + ellipsis, not a bare Text: long labels ("Upload
              // Routine/Transport", "Feedback & Contributions") were
              // painting straight past the rounded hover/active box.
              Expanded(child: Text(item.label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style:TextStyle(
                color:isActive?item.color:textPrimary,
                fontSize:14, fontWeight:isActive?FontWeight.w600:FontWeight.w400))),
            ]),
          ),
        ),
      ),
        ),
      ),
    ).animate(delay:Duration(milliseconds:widget.delay))
      .fadeIn(duration:140.ms,curve:Curves.easeOutCubic)
      .slideX(begin:-0.05,duration:140.ms,curve:Curves.easeOutCubic);
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
        border:Border.all(color:ringColor.withValues(alpha:0.6),width: isSuperAdmin ? 3 : 2),
        boxShadow:[BoxShadow(color:ringColor.withValues(alpha:0.25),blurRadius:12,spreadRadius:-2)]),
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
  // Container's own `alignment` was tried here first -- it fixed the text's
  // vertical centering, but this chip is used both bare in a Row AND wrapped
  // in Flexible (the department chip); a Container with alignment but no
  // explicit size EXPANDS to fill all available space once its parent's
  // constraints are bounded (which Flexible imposes), so the Flexible-wrapped
  // department chip ballooned to fill most of the row's width. Centering the
  // text's own line box instead (height:1.0 + textHeightBehavior) fixes the
  // same vertical-centering issue without touching how the Container sizes
  // itself, so both the bare and Flexible-wrapped usages stay tightly
  // wrapped around their text.
  Widget build(BuildContext context) => Container(
    padding:const EdgeInsets.symmetric(horizontal:8,vertical:3),
    decoration:BoxDecoration(color:color.withValues(alpha:0.15),borderRadius:BorderRadius.circular(20),
      border:Border.all(color:color.withValues(alpha:0.3))),
    child:Text(label, textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
      style:TextStyle(color:color,fontSize:11,height: 1.0,fontWeight:FontWeight.w600),
      maxLines:1,overflow:TextOverflow.ellipsis),
  );
}

class _MenuItem {
  final String label, route;
  final IconData icon;
  final Color color;
  const _MenuItem(this.label,this.icon,this.route,this.color);
}

/// A pinned quick-access tile for the web rail: highlights by the active route
/// and navigates with `go` (no ShellBloc index side effects).
class _QuickRailTile extends StatelessWidget {
  final _MenuItem item;
  final bool active;
  const _QuickRailTile({required this.item, required this.active});
  @override
  Widget build(BuildContext context) {
    final textPrimary = AppColors.textPrimaryOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => context.go(item.route),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: active ? item.color.withValues(alpha: 0.14) : Colors.transparent,
              border: active ? Border(left: BorderSide(color: item.color, width: 3)) : null,
            ),
            child: Row(children: [
              Container(width: 34, height: 34, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: active ? 0.22 : 0.15),
                  borderRadius: BorderRadius.circular(10)),
                child: Icon(item.icon, color: item.color, size: 18)),
              const SizedBox(width: 12),
              Expanded(child: Text(item.label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: active ? item.color : textPrimary,
                  fontSize: 14, fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
            ]),
          ),
        ),
      ),
    );
  }
}
