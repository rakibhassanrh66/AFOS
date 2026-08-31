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
import '../../../core/auth/capabilities.dart';
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

/// Re-exported from the capability model so the two cannot drift.
///
/// These two functions ARE the tested contract (29 cases in
/// `test/staff_menu_permissions_test.dart`), so their signatures do not move.
/// What moved is where the answer comes from: `lib/core/auth/capabilities.dart`
/// now owns it, and the web sidebar, the role consoles and the command palette
/// read the same source. Before this, the dashboard answered the same question
/// with a hardcoded twelve-tile grid that never consulted a grant at all.
export '../../../core/auth/capabilities.dart' show staffMenuRoutes, delegatedRoutes;


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

  // THE CATALOGUE MOVED.
  //
  // Everything from `_quickAccessItems` to `_baseRoleItems` used to live here:
  // a second copy of every route, icon, label and colour in the app, kept in
  // step with the dashboard's own twelve-tile copy by hand. They did not stay
  // in step -- Mentorship carried a stray Color(0xFF60A5FA) here that
  // disagreed with AppColors.moduleColors['mentorship'], so the module had two
  // identities depending on which screen you looked at.
  //
  // It now lives in lib/core/auth/capabilities.dart, which the web sidebar,
  // the role consoles and the command palette read as well. This widget is a
  // renderer again rather than a second source of truth.

  /// The four destinations pinned at the top of the web rail. They are the
  /// floating bottom bar's items on mobile, which is why they are a rail
  /// concern and not part of the capability model.
  static const _quickAccessItems = [
    Caps.dashboard,
    AppCapability(label: 'Search', route: '/search', icon: Icons.search_rounded,
        accent: AppColors.holoTeal, group: CapabilityGroup.personal),
    Caps.profile,
    Caps.settings,
  ];

  List<AppCapability> get _roleItems =>
      capabilitiesFor(role: _user?.role, grants: _grants, isCr: _isCr);

  // Semester only means something for a student -- a teacher/staff/admin
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

  /// The role's list, minus anything this context should not show.
  ///
  /// Both filters are pure VISIBILITY -- the route guards and RLS are
  /// unchanged either way.
  List<AppCapability> get _effectiveItems {
    var items = _roleItems;
    // "Nearby SOS Alerts" is gated behind the campus-emergency SOS toggle:
    // general users see it only when a super-admin has switched SOS ON;
    // super_admin always sees it.
    final sosVisible = _user?.role == 'super_admin' || AppConfigService.instance.sosEnabled.value;
    if (!sosVisible) {
      items = items.where((it) => it.route != Caps.nearbySos.route).toList();
    }

    // On the web rail ONLY, drop anything the pinned quick-access strip is
    // already showing. The rail pins Home/Search/Profile/Settings at the top
    // and then lists the role's menu underneath -- and that menu opens with
    // 'Dashboard' -> /home and ends with 'Settings' -> /settings. Same routes,
    // different labels, so on /home BOTH highlighted at once.
    //
    // Filtered by ROUTE, not label: that is what actually makes them the same
    // destination -- 'Home' and 'Dashboard' were never going to match on text.
    //
    // Only when `permanent`: on a phone the quick-access four are the floating
    // bottom bar, not part of this drawer, so removing them here would leave
    // no way to reach Dashboard or Settings from the menu at all.
    if (widget.permanent) {
      final pinned = _quickAccessItems.map((it) => it.route).toSet();
      items = items.where((it) => !pinned.contains(it.route)).toList();
    }
    _publishDestinations(items);
    return items;
  }

  /// Hand the resolved list to anything else that needs to know where this
  /// user may go -- currently the web command palette.
  ///
  /// Published rather than recomputed. The capability model encodes the role
  /// matrix, the delegated `resource:action` grants and the CR flag, and its
  /// grants deliberately match the ones app_router.dart guards each route
  /// with. A second implementation of that is how a palette ends up offering a
  /// destination the router then refuses.
  ///
  /// Includes the pinned quick-access four even on the web rail, where the
  /// menu itself hides them: the rail hides them because they are ALREADY on
  /// screen above, which is not a reason for the palette to be unable to
  /// reach Settings.
  void _publishDestinations(List<AppCapability> items) {
    final all = <AppCapability>[..._quickAccessItems, ...items];
    final seen = <String>{};
    final next = <NavDestination>[
      for (final m in all)
        if (seen.add(m.route)) NavDestination(m.label, m.icon, m.route, m.accent),
    ];
    // Built during build(), so defer the notify -- mutating a ValueNotifier
    // whose listeners are also building would throw.
    if (listEquals(navDestinations.value, next)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) navDestinations.value = next;
    });
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
                  // A staff account with no areas assigned is not a small menu
                  // — it is an unfinished setup, and it looked identical to a
                  // finished one. A staff member sat waiting to upload routines
                  // while `user_permissions` was empty app-wide, seeing a short
                  // menu that gave no hint anything was missing.
                  if (_user?.role == 'staff' && _grants.isEmpty) const _NoAreasNotice(),
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
  final AppCapability item;
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
                ? item.accent.withValues(alpha: 0.12)
                : (_hover ? item.accent.withValues(alpha: 0.07) : Colors.transparent),
            border: _hover && !isActive
                ? Border.all(color: item.accent.withValues(alpha: 0.25))
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
              borderRadius: AppDepth.radius(1),
              border:Border(left:BorderSide(color:item.accent,width:3)),
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
                            colors: [item.accent, item.accent.withValues(alpha: 0.7)]),
                        borderRadius: AppDepth.radius(1),
                        boxShadow: [BoxShadow(color: item.accent.withValues(alpha: 0.35), blurRadius: 8, offset: AppDepth.litOffset(3))])
                    : BoxDecoration(
                        color:item.accent.withValues(alpha: _hover ? 0.22 : 0.15),
                        borderRadius: AppDepth.radius(1)),
                child:Icon(item.icon,color: isActive ? Colors.white : item.accent,size:18)),
              ),
              const SizedBox(width:12),
              // Expanded + ellipsis, not a bare Text: long labels ("Upload
              // Routine/Transport", "Feedback & Contributions") were
              // painting straight past the rounded hover/active box.
              Expanded(child: Text(item.label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style:TextStyle(
                color:isActive?item.accent:textPrimary,
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

// _MenuItem is gone. It was a fourth definition of "a thing you can navigate
// to" -- alongside the dashboard's _Module, the palette's NavDestination and
// the router's own table -- and the one that carried a colour disagreeing with
// AppColors.moduleColors. AppCapability replaces it; `.color` became `.accent`
// because the value is an accent, not the widget's colour.

/// A pinned quick-access tile for the web rail: highlights by the active route
/// and navigates with `go` (no ShellBloc index side effects).
class _QuickRailTile extends StatelessWidget {
  final AppCapability item;
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
              color: active ? item.accent.withValues(alpha: 0.14) : Colors.transparent,
              border: active ? Border(left: BorderSide(color: item.accent, width: 3)) : null,
            ),
            child: Row(children: [
              Container(width: 34, height: 34, alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: item.accent.withValues(alpha: active ? 0.22 : 0.15),
                  borderRadius: AppDepth.radius(1)),
                child: Icon(item.icon, color: item.accent, size: 18)),
              const SizedBox(width: 12),
              Expanded(child: Text(item.label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: active ? item.accent : textPrimary,
                  fontSize: 14, fontWeight: active ? FontWeight.w700 : FontWeight.w500))),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Shown in a `staff` menu that has no delegated areas at all.
///
/// WHY IT MATTERS. `staff` is the one role whose tools come entirely from
/// per-person grants. Before this, an account with nothing assigned rendered a
/// short menu that looked exactly like a finished setup — so a staff member
/// waiting to upload routines had no way to tell whether the app was broken,
/// their permission had not been granted, or that was simply all they got.
/// Saying it plainly turns a mystery into a message they can act on.
class _NoAreasNotice extends StatelessWidget {
  const _NoAreasNotice();

  @override
  Widget build(BuildContext context) {
    final textSecondary = AppColors.textSecondaryOf(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.amber.withValues(alpha: 0.10),
          borderRadius: AppDepth.radius(1),
          border: Border.all(color: AppColors.amber.withValues(alpha: 0.3)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.info_outline_rounded,
                  size: 16, color: AppColors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text('No work areas assigned yet',
                    style: AppTextStyles.titleMedium.copyWith(
                        color: AppColors.textPrimaryOf(context), fontSize: 13)),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              'Your account is set up as staff, but no admin area has been '
              'assigned to it. Ask a super-admin to assign yours — the tools '
              'appear here as soon as they do, without signing out.',
              style: AppTextStyles.labelSmall.copyWith(color: textSecondary),
            ),
          ]),
        ),
      ),
    );
  }
}
