import 'package:flutter/foundation.dart' show listEquals;

import '../../../config/theme/depth.dart';
import '../../../config/theme/motion.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../bloc/shell_bloc.dart';
import '../../../config/app_config.dart';
import '../../../config/supabase_config.dart';
import '../../../core/auth/permission_session.dart';
import '../../../core/navigation/nav_destinations.dart';
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

/// The routes a staff member or officer may see, given the permissions
/// delegated to them, in menu order.
///
/// Top-level and public for the same reason `joinRequestMatchesSection` is:
/// this decides what a whole class of employees can reach, which makes it the
/// one piece of this screen that has to be pinned by a test rather than
/// eyeballed. The widget below builds its items from exactly this list, so
/// there is no second copy of the rule to drift.
///
/// The first six and the last are unconditional — what anyone gets for being
/// an employee. Everything between them is delegated per person by a
/// super_admin (Manage Users -> "Distribute admin work"). The resource:action
/// pairs match app_router.dart's guards for the same routes exactly; if the
/// two ever disagree, the menu offers a door the router slams.
@visibleForTesting
List<String> staffMenuRoutes(Set<String> grants) {
  bool can(String resource, String action) => grants.contains('$resource:$action');
  return [
    '/home',
    '/transport',
    '/lost-found',
    '/sos/nearby',
    '/notifications',
    '/settings',
    // One screen, three grants that each unlock it — mirrors the router, which
    // admits any one of them.
    if (can('routine', 'upload') || can('transport', 'upload') || can('exam_seat', 'upload'))
      '/admin/upload',
    if (can('course_offerings', 'manage')) '/admin/course-offerings',
    if (can('hall', 'manage')) '/admin/hall',
    if (can('library', 'manage')) '/admin/library',
    if (can('conference', 'manage')) '/conference-room',
    if (can('sos', 'manage')) '/admin/sos',
    if (can('notice', 'publish')) '/manage-notices',
    if (can('exam_seat', 'upload')) '/manage-exam-seats',
    '/feedback',
  ];
}

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
  /// "resource:action" grants for this user, from `list_my_permissions` (which
  /// unions their ROLE's permissions with anything a super_admin delegated to
  /// them individually).
  ///
  /// The menu used to be a pure switch on `role`, which made delegation
  /// half-work: app_router.dart already lets a delegated user through to
  /// /admin/upload and friends, but nothing ever put those entries in their
  /// menu — so a granted permission was reachable only by typing the URL.
  /// Loading the set here closes that, and lets the staff branch below start
  /// from nothing and add only what has actually been granted.
  Set<String> _grants = const {};

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
          .select('*, teachers(designation), staff(designation, office), students(is_cr)').eq('id',uid).single();
      final isCr = (p['students'] as Map?)?['is_cr'] as bool? ?? false;
      // Loaded alongside the profile rather than in its own effect so the menu
      // never renders once with the role's items and then visibly grows a
      // second time as delegated entries arrive.
      //
      // reload(), not ensureLoaded(): this method re-runs every time the drawer
      // opens (see the BlocConsumer listener below), and the whole point of
      // that is to pick up changes made since app start. A cached read would
      // make a freshly-granted permission invisible until the next sign-in.
      final grants = await PermissionSession.reload();
      if(mounted) setState(() { _user=UserModel.fromJson(p); _isCr=isCr; _grants=grants; });
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
    // Was a stray Color(0xFF60A5FA) — the only literal in this list, and it
    // DISAGREED with AppColors.moduleColors['mentorship'] (blueLight), so the
    // module had two identities depending on where you looked at it.
    _MenuItem('Mentorship',     AppIcons.mentorship,  '/mentorship',    AppColors.blueLight),
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

  static const _myOfferingsItem =
    _MenuItem('My Course Offerings', AppIcons.schedule, '/schedule/my-offerings', AppColors.blue);

  // Teacher-only: the register is scoped to offerings they own, so it has
  // nothing to show anyone else.
  static const _attendanceItem =
    _MenuItem('Attendance', Icons.how_to_reg_rounded, '/attendance', AppColors.green);

  // Shown to every teacher rather than only to appointed module leaders: the
  // appointment lives in a table, not in RoleSession, so the menu cannot know
  // without a query. The screen itself says "Not a module leader" to anyone
  // who opens it without the appointment.
  // Its own menu entry, not just a tab inside My Course Offerings. As a tab it
  // was undiscoverable, and it reproducibly rendered blank while its title
  // showed a live count -- see JoinRequestsScreen for why that path was
  // abandoned rather than patched.
  static const _joinRequestsItem =
    _MenuItem('Join Requests', Icons.how_to_reg_rounded, '/schedule/join-requests', AppColors.green);

  static const _teachingLoadItem =
    _MenuItem('Teaching Load', Icons.assignment_ind_rounded, '/schedule/teaching-load', AppColors.indigo);

  // Student-facing counterpart to the teacher's register. The RLS policy for
  // it shipped with attendance and nothing ever called it, so a student had no
  // way to see their own record until it showed up as a lost Attendance mark.
  static const _myAttendanceItem =
    _MenuItem('My Attendance', Icons.fact_check_outlined, '/my-attendance', AppColors.green);

  static const _browseCoursesItem =
    _MenuItem('Browse Courses', Icons.menu_book_rounded, '/schedule/browse-courses', AppColors.blue);

  static const _adminItems = [
    _MenuItem('Upload Routine/Transport', AppIcons.uploadRoutine, '/admin/upload', AppColors.holoBlue),
    _MenuItem('Course Offerings', AppIcons.schedule, '/admin/course-offerings', AppColors.blue),
    _MenuItem('Manage Hall', AppIcons.hall, '/admin/hall', AppColors.amber),
    _MenuItem('Manage Library', AppIcons.library, '/admin/library', AppColors.purple),
    _MenuItem('Moderate Dept Chats', AppIcons.moderateChat, '/admin/dept-chat', AppColors.indigo),
    _MenuItem('Manage Faculties', AppIcons.faculties, '/admin/faculties', AppColors.holoviolet),
    _MenuItem('Manage Departments', AppIcons.hall, '/admin/departments', AppColors.holoTeal),
    _MenuItem('Notices & Rules', AppIcons.notices, '/manage-notices', AppColors.red),
    _MenuItem('Manage Exam Seats', AppIcons.examSeat, '/manage-exam-seats', AppColors.orange),
    _sosAdminItem,
  ];

  // What a staff member or officer gets purely for being an employee, before
  // anyone has delegated them anything. Transport and Lost & Found are
  // campus-wide services, Nearby SOS is a personal-safety feature every role
  // has (and is separately gated by the app-wide SOS toggle), and the rest is
  // their own account. Nothing here is an administrative tool.
  static const _staffBaseItems = [
    _MenuItem('Dashboard',         AppIcons.dashboard,     '/home',          AppColors.blue),
    _MenuItem('Transport',         AppIcons.transport,     '/transport',     AppColors.teal),
    _MenuItem('Lost & Found',      AppIcons.lostFound,     '/lost-found',    AppColors.coral),
    _MenuItem('Nearby SOS Alerts', Icons.sos_rounded,      '/sos/nearby',    AppColors.red),
    _MenuItem('Notifications',     AppIcons.notifications, '/notifications', AppColors.red),
    _MenuItem('Settings',          AppIcons.settings,      '/settings',      AppColors.textSecondary),
  ];

  // Every item a staff member could possibly see, in menu order. Which of them
  // actually render is decided by staffMenuRoutes(); this is only the
  // route -> presentation lookup.
  static const _staffCandidateItems = [
    ..._staffBaseItems,
    _uploadRoutineItem,
    _courseOfferingsAdminItem,
    _hallAdminItem,
    _libraryAdminItem,
    _conferenceRoomItem,
    _sosAdminItem,
    _noticesItem,
    _examSeatsItem,
    _feedbackItem,
  ];

  // Individually-grantable admin entries. These already existed inside
  // _adminItems as list literals; pulling the delegatable ones out as named
  // constants lets the staff branch include exactly one of them without
  // duplicating the route or the icon and letting the two copies drift.
  static const _uploadRoutineItem =
    _MenuItem('Upload Routine/Transport', AppIcons.uploadRoutine, '/admin/upload', AppColors.holoBlue);

  static const _courseOfferingsAdminItem =
    _MenuItem('Course Offerings', AppIcons.schedule, '/admin/course-offerings', AppColors.blue);

  static const _hallAdminItem =
    _MenuItem('Manage Hall', AppIcons.hall, '/admin/hall', AppColors.amber);

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
    if (_user!.isStaff) return _user!.designation ?? 'Staff/Officer';
    switch (role) {
      case 'super_admin': return 'Super Admin';
      case 'dept_admin': return 'Dept Admin';
      case 'admin': return 'Admin';
      case 'exam_controller': return 'Exam Controller';
      default: return role;
    }
  }

  List<_MenuItem> get _effectiveItems {
    var items = _roleItems;
    // "Nearby SOS Alerts" is gated behind the campus-emergency SOS toggle:
    // general users see it only when a super-admin has switched SOS ON;
    // super_admin always sees it. Pure visibility filter — the route/RLS are
    // unchanged.
    final sosVisible = _user?.role == 'super_admin' || AppConfigService.instance.sosEnabled.value;
    if (!sosVisible) {
      items = items.where((it) => it.route != '/sos/nearby').toList();
    }

    // On the web rail ONLY, drop anything the pinned quick-access strip is
    // already showing.
    //
    // The rail pins Home/Search/Profile/Settings at the top and then lists the
    // role's menu underneath — and that menu opens with 'Dashboard' → /home and
    // ends with 'Settings' → /settings. Same routes, same icons, different
    // labels. So on /home BOTH "Home" and "Dashboard" highlighted at once, and
    // the second copy sat further down the rail behind the divider looking like
    // a stray entry. Same for Settings.
    //
    // Filtered by route, not by label, because that is what actually makes them
    // the same destination — 'Home' and 'Dashboard' were never going to match
    // on text.
    //
    // Only when `permanent`: on a phone the quick-access four are the floating
    // bottom bar, not part of this drawer, so removing them here would leave no
    // way to reach Dashboard or Settings from the menu at all.
    if (widget.permanent) {
      final pinned = _quickAccessItems.map((it) => it.route).toSet();
      items = items.where((it) => !pinned.contains(it.route)).toList();
    }
    _publishDestinations(items);
    return items;
  }

  /// Hand the resolved list to anything else that needs to know where this user
  /// may go — currently the web command palette.
  ///
  /// Published rather than recomputed. `_roleItems` above encodes the role
  /// matrix, the delegated `resource:action` grants, the CR flag and the SOS
  /// toggle, and its grants deliberately match the ones `app_router.dart`
  /// guards each route with. A second implementation of that is how a palette
  /// ends up offering a destination the router then refuses.
  ///
  /// Includes the pinned quick-access four even on the web rail, where the
  /// menu itself hides them: the rail hides them because they are ALREADY on
  /// screen above, which is not a reason for the palette to be unable to reach
  /// Settings.
  void _publishDestinations(List<_MenuItem> items) {
    final all = <_MenuItem>[..._quickAccessItems, ...items];
    final seen = <String>{};
    final next = <NavDestination>[
      for (final m in all)
        if (seen.add(m.route)) NavDestination(m.label, m.icon, m.route, m.color),
    ];
    // Built during build(), so defer the notify — mutating a ValueNotifier
    // whose listeners are also building would throw.
    if (listEquals(navDestinations.value, next)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) navDestinations.value = next;
    });
  }

  List<_MenuItem> get _roleItems {
    final role = _user?.role;
    // Admin-tier roles get oversight tools (Manage Hall, etc.), not the
    // student-personal-record screens themselves — an admin has no hall
    // room, exam seat, or payment of their own to apply for, so showing
    // those would be nonsensical, not just redundant.
    if (role == 'super_admin') {
      return [..._commonItems, ..._adminItems, _teachingLoadItem, ..._superAdminItems, _feedbackItem];
    }
    if (const ['admin', 'dept_admin'].contains(role)) {
      return [..._commonItems, ..._adminItems, _teachingLoadItem, _feedbackItem];
    }
    if (role == 'teacher') {
      // Teachers can author course notices/rules but don't get the rest
      // of the admin toolset (routine upload, faculty/department registry).
      return [..._commonItems, _myOfferingsItem, _joinRequestsItem, _attendanceItem, _teachingLoadItem, _noticesItem, _conferenceRoomItem, _roomAvailabilityItem, _feedbackItem];
    }
    if (role == 'staff') {
      // Staff/officers start from almost nothing and earn the rest.
      //
      // This branch used to be `[..._commonItems, _conferenceRoomItem,
      // _libraryAdminItem, _sosAdminItem, _feedbackItem]`, which handed every
      // staff member Class Schedule, Clubs, Results, Assignments, Mentorship
      // and Dept Chat (all of _commonItems) plus Conference Room, Manage
      // Library and Manage SOS Alerts — unconditionally. A Registrar has no
      // classes, no club membership, no results and no assignments; and
      // "Manage Library" being handed out with the job title rather than with
      // a decision is the opposite of least privilege.
      //
      // What remains below is what any employee needs regardless of posting.
      // Everything else is delegated per person by a super_admin through
      // Manage Users -> "Distribute admin work", and appears here the moment
      // it is granted. The resource:action pairs are exactly the ones
      // app_router.dart guards the matching routes with, so the menu and the
      // router can never disagree about who may open what.
      // Built from staffMenuRoutes() rather than repeating the conditions, so
      // the tested rule and the rendered menu cannot disagree.
      final byRoute = {for (final m in _staffCandidateItems) m.route: m};
      return [
        for (final route in staffMenuRoutes(_grants))
          if (byRoute[route] != null) byRoute[route]!,
      ];
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
      return [..._commonItems, ..._studentOnlyItems, _browseCoursesItem, _myAttendanceItem, _roomAvailabilityItem, _feedbackItem];
    }
    return [..._commonItems, ..._studentOnlyItems, _browseCoursesItem, _myAttendanceItem, _feedbackItem];
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
      // The builder below never actually reads `state` — confirmed by
      // reading its full body (header, BackdropFilter blur, up-to-25-item
      // menu list, footer all come from `ctx`/instance fields only) — so
      // without this it was rerunning a BackdropFilter blur (one of the
      // most expensive Flutter render ops) plus a full List.generate on
      // every single ShellBloc emission, i.e. twice per menu open/close.
      buildWhen: (_, __) => false,
      builder:(ctx,state) => ClipRRect(
        // Rounded on the trailing edge only — the leading edge runs off-screen,
        // so rounding it would just show a notch. `ClipRRect` here had NO
        // borderRadius at all, which is why the drawer read as a hard square
        // slab next to a design system built entirely on soft glass.
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(LiquidGlass.radiusSheet),
          bottomRight: Radius.circular(LiquidGlass.radiusSheet),
        ),
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
            // No SafeArea here any more. AppShell now positions this panel
            // INSIDE the system bars (top: padding.top + 8, bottom:
            // padding.bottom + 8), so a SafeArea would inset the content a
            // second time — and when the panel spanned the full window it was
            // the reason the glass surface itself painted under the status bar
            // while only its contents were pushed clear.
            child: Column(children:[
                _buildHeader(ctx),
                Expanded(child: ListenableBuilder(
                  // Highlighting is route-derived, so it has to rebuild on
                  // navigation. This widget is permanently mounted and its Bloc
                  // state does not change when the route does, so without this
                  // the highlight would simply never update.
                  listenable: GoRouter.of(ctx).routerDelegate,
                  // No nav clearance: the drawer is the LAST layer in AppShell's
                  // Stack, so it paints over the floating bar rather than under
                  // it, and it is already positioned clear of the gesture bar.
                  // Adding the inset here just put ~107px of dead space under
                  // the last menu item.
                  builder: (ctx, _) => ListView(padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 0, 8), children:[
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
                  // Logout is the LAST ITEM of this same scrolling list, not a
                  // separately pinned row below it (tried in a previous round —
                  // pinning it outside the Expanded ListView fixed "Logout
                  // floats mid-screen for a short role's menu", but introduced
                  // a worse problem: Logout sat at a FIXED height regardless of
                  // scroll position, so it visually detached from the item list
                  // while scrolling — "feedback and ideas [i.e. the real last
                  // menu item] looks weird" during scroll was that Logout
                  // wasn't moving WITH the content above it. Back inside the
                  // list, Logout scrolls naturally right after the last real
                  // item — any leftover blank space for a short menu now falls
                  // in the normal, expected place (below Logout, before
                  // reaching the fixed footer), not as a jarring gap ABOVE a
                  // detached Logout row.
                  Divider(color: border, height: 1),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 6),
                    // Builder so the tile gets its OWN context: the radial
                    // menu reads that render box to place the burst origin.
                    child: Builder(
                      builder: (tileCtx) =>
                          LogoutTile(label: 'Logout', onTap: () => _confirmLogout(tileCtx)),
                    ),
                  ),
                ]))),
                // Only the lightweight version/university footer stays pinned
                // outside the scroll, so it's always visible without needing
                // to scroll all the way down for a long menu (super_admin).
                _buildFooter(context),
              ]),
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
      padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 22),
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
          // Only drawn when there is something to say. This was
          // `_Chip(_user?.department ?? '')` — unconditional — and staff rows
          // carried department = '' (an empty STRING, so `??` never fired).
          // The result was a chip with padding, a background and no text: a
          // small blank blob parked next to the user's name. A field with no
          // value should occupy no space, not draw an empty container.
          if (_user?.affiliation != null) ...[
            Flexible(child: _Chip(_user!.affiliation!, AppColors.holoBlue)),
            const SizedBox(width:8),
          ],
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
              borderRadius: AppDepth.radius(1),
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
          duration: AppMotion.tight,
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            borderRadius: AppDepth.radius(1),
            color: isActive
                ? item.color.withValues(alpha: 0.12)
                : (_hover ? item.color.withValues(alpha: 0.07) : Colors.transparent),
            border: _hover && !isActive
                ? Border.all(color: item.color.withValues(alpha: 0.25))
                : Border.all(color: Colors.transparent),
          ),
          child: Material(
        color: Colors.transparent,
        borderRadius: AppDepth.radius(1),
        child: InkWell(
          borderRadius: AppDepth.radius(1),
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
            duration: AppMotion.tight,
            curve: AppMotion.standard,
            padding: EdgeInsetsDirectional.fromSTEB(
                _hover && !isActive ? 14 : 12, 10, 12, 10),
            decoration:isActive?BoxDecoration(
              border:Border(left:BorderSide(color:item.color,width:3)),
            ):null,
            child: Row(children:[
              AnimatedScale(
                duration: AppMotion.tight,
                curve: AppMotion.standard,
                scale: _hover && !isActive ? 1.08 : 1.0,
                child: Container(width:34,height:34, alignment: Alignment.center,
                decoration: isActive
                    ? BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                            colors: [item.color, item.color.withValues(alpha: 0.7)]),
                        borderRadius: AppDepth.radius(1),
                        boxShadow: [BoxShadow(color: item.color.withValues(alpha: 0.35), blurRadius: 8, offset: const Offset(0, 3))])
                    : BoxDecoration(
                        color:item.color.withValues(alpha: _hover ? 0.22 : 0.15),
                        borderRadius: AppDepth.radius(1)),
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
    // The caller passes `(i*15).clamp(0,90)` — its own hand-rolled stagger.
    // Routed through the ladder so reduced motion collapses the whole menu's
    // entrance instead of only its durations.
    ).animate(delay: AppMotion.isReduced(context)
              ? Duration.zero
              : Duration(milliseconds: widget.delay))
      .fadeIn(duration: AppMotion.durationOf(context, AppMotion.tight), curve: AppMotion.standard)
      .slideX(begin:-0.05,
          duration: AppMotion.durationOf(context, AppMotion.tight), curve: AppMotion.standard);
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
        ? CachedNetworkImage(imageUrl:url!,fit:BoxFit.cover,memCacheWidth:128,
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
    decoration:BoxDecoration(color:color.withValues(alpha:0.15),borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
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
          borderRadius: AppDepth.radius(1),
          onTap: () => context.go(item.route),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: AppDepth.radius(1),
              color: active ? item.color.withValues(alpha: 0.14) : Colors.transparent,
              border: active ? Border(left: BorderSide(color: item.color, width: 3)) : null,
            ),
            child: Row(children: [
              Container(width: 34, height: 34, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: active ? 0.22 : 0.15),
                  borderRadius: AppDepth.radius(1)),
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
