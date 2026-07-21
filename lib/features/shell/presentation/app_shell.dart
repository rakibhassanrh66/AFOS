import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/navigation/back_press_tracker.dart';
import '../../../core/navigation/router_location.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/glass_bottom_nav.dart';
import '../../../shared/widgets/liquid_backdrop.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../sos/presentation/sos_floating_button.dart';
import '../bloc/shell_bloc.dart';
import 'slide_menu.dart';

/// The 4 quick-access destinations shown in the floating bottom nav (mobile/
/// tablet) and pinned at the top of the web nav rail.
const List<BottomNavDest> kQuickNavDestinations = [
  BottomNavDest(label: 'Home', icon: Icons.home_outlined, activeIcon: AppIcons.dashboard, route: '/home'),
  BottomNavDest(label: 'Search', icon: Icons.search_rounded, route: '/search'),
  BottomNavDest(label: 'Profile', icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, route: '/profile'),
  BottomNavDest(label: 'Settings', icon: Icons.settings_outlined, activeIcon: AppIcons.settings, route: '/settings'),
];

/// Which of [kQuickNavDestinations] (if any) is actually on screen, or -1.
///
/// The truthful-location reasoning lives in `currentRouteLocation` — the short
/// version is that `matchedLocation` is stale under an imperative push, so it
/// reported the screen you came FROM. That, not the navigation verb, was the
/// indicator bug; changing slide_menu's verb to `go` only traded it for the
/// back stack.
///
/// `navigation_indicator_test.dart` pins the underlying go_router behaviour, so
/// an upgrade that changes it fails loudly instead of silently reintroducing
/// the stale indicator.
@visibleForTesting
int navIndexForRouter(GoRouter router) =>
    kQuickNavDestinations.indexWhere((d) => isRouteActive(router, d.route));

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create:(_)=>ShellBloc(),
      child: Builder(builder:(ctx)=>_ShellBody(child:child)),
    );
  }
}

class _ShellBody extends StatelessWidget {
  final Widget child;
  const _ShellBody({required this.child});

  // Every in-app navigation action pushes onto one shared shell Navigator
  // with no depth cap, which is what made "back" feel like it jumped to a
  // random screen -- wandering several modules deep and backing out one
  // screen at a time no longer matches user intent past a point. Capped at
  // 3 real pops, then a direct jump to Dashboard; pressing back again while
  // already on Dashboard (the true app root) asks for exit confirmation
  // instead, rather than silently closing.
  // Ordering matters here: ask "is anything stacked above us?" BEFORE asking
  // "where are we?". Inside a ShellRoute an imperative `push` deliberately
  // leaves the match list's uri untouched (go_router's own comment: "Imperative
  // route match doesn't change the uri and path parameters"), so
  // `matchedLocation` can still read '/home' while a pushed screen sits on top
  // -- the old location-first order therefore offered to EXIT THE APP instead
  // of popping that screen. canPop() reflects the real navigator stack, so it
  // is the trustworthy signal; the location is only consulted once we know
  // there is nothing left to pop.
  void _handleBack(BuildContext context) {
    final router = GoRouter.of(context);
    final tracker = BackPressTracker.instance;
    if (router.canPop()) {
      if (tracker.consecutiveBackPresses >= 3) {
        tracker.consecutiveBackPresses = 0;
        router.go('/home');
        return;
      }
      tracker.consecutiveBackPresses++;
      router.pop();
      return;
    }
    tracker.consecutiveBackPresses = 0;
    // currentRouteLocation, not matchedLocation. Both are correct HERE (we only
    // reach this line when canPop() is false, which means nothing was pushed and
    // so nothing is stale), but relying on that ordering invariant is exactly
    // how this class of bug keeps coming back. The truthful read is correct
    // regardless of how the code above it is later rearranged.
    if (currentRouteLocation(router) == '/home') {
      _confirmExit(context);
      return;
    }
    router.go('/home');
  }

  Future<void> _confirmExit(BuildContext context) async {
    final exit = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(dialogCtx),
        title: Text('Exit AFOS?', style: TextStyle(color: AppColors.textPrimaryOf(dialogCtx))),
        content: Text('Are you sure you want to leave the app?',
            style: TextStyle(color: AppColors.textSecondaryOf(dialogCtx))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text('Stay', style: TextStyle(color: AppColors.textSecondaryOf(dialogCtx)))),
          TextButton(onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('Exit', style: TextStyle(color: AppColors.red))),
        ],
      ),
    );
    if (exit == true) SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack(context);
      },
      child: BlocBuilder<ShellBloc,ShellState>(
      builder:(ctx,state) {
        // Web-only: a tablet or a foldable running the native Android/iOS
        // app should still get the normal touch drawer at any width -- this
        // is specifically about a mouse-and-keyboard browser window, not
        // "wide screen" in general.
        final isDesktop = kIsWeb && Responsive.isExpanded(context);
        final content = OfflineBanner(child: AdaptiveContentWidth(child: child));
        // On a desktop-width browser window, the hide/show drawer pattern
        // (a slide-in panel over a dimmed scrim, meant for a hand reaching
        // across a phone screen) doesn't make sense with a mouse and a
        // window that's wide enough to just show it permanently -- it read
        // as the app "shrinking to phone size and blocking the rest of the
        // screen" rather than actually using the space. >=1024px on web
        // gets a fixed nav rail sitting beside the content instead; native
        // apps and narrower widths keep the original overlay drawer exactly
        // as it was.
        if (isDesktop) {
          return Scaffold(
            backgroundColor: AppColors.surfaceOf(context),
            body: LiquidBackdrop(child: Row(children: [
              const SizedBox(width: 248, child: SlideMenu(permanent: true)),
              Expanded(child: Stack(children: [
                content,
                const SosGate(),
              ])),
            ])),
          );
        }
        // Mobile/tablet: reserve space at the bottom (via a MediaQuery inset)
        // so screens that honor bottom padding clear the floating bar, and
        // highlight whichever of the 4 quick destinations is the active route.
        final mq = MediaQuery.of(context);
        // Systemic clearance for the floating bottom nav: PHYSICAL bottom
        // padding on the routed content so every screen — including ones that
        // never read the inset (e.g. a plain ListView with fixed padding) —
        // keeps its last element above the bar. This replaces the old
        // MediaQuery-inset-only reservation that naive screens silently ignored
        // (the Settings "Log out" regression). The floating "planet" nav needs
        // clearance for the bar itself AND the planet that floats above it —
        // reservedHeight already sums bar + planet lift + margins; + safe-area
        // so it also clears the gesture bar.
        const barSpace = GlassBottomNav.reservedHeight;
        // Clearance is handed down as a MediaQuery BOTTOM INSET, never as
        // physical Padding on the routed content.
        //
        // Physical padding is what made the floating bar look like "a rectangle
        // inside a rectangle": it ended the content above the bar, so the only
        // thing left behind the glass was flat Scaffold background, and a
        // BackdropFilter with nothing behind it to blur renders as a plain
        // opaque slab. Content now runs full-bleed to the bottom of the screen
        // and genuinely scrolls UNDER the bar, which is what gives the frosted
        // read-through.
        //
        // Clearance still works because `BoxScrollView` (ListView/GridView)
        // with a null `padding` automatically adopts MediaQuery's vertical
        // padding, and SafeArea consumes it too. The screens that need a manual
        // pass are the ones that hard-code their own scroll padding or pin a
        // widget to the bottom — they opt out of the inset by construction.
        final mobileContent = MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(bottom: mq.padding.bottom + barSpace),
            viewPadding: mq.viewPadding.copyWith(bottom: mq.viewPadding.bottom + barSpace),
          ),
          child: content,
        );
        return Scaffold(
        backgroundColor: AppColors.surfaceOf(context),
        body: LiquidBackdrop(child: Stack(children:[
          mobileContent,
          // Persistent across every authenticated screen -- only reachable
          // once the router's profile-completed/verified gates have
          // already passed, since AppShell itself is only ever built for
          // routes inside the gated ShellRoute.
          const SosGate(),
          // Floating quick-access bottom nav (mobile/tablet). Placed before
          // the scrim + drawer so an open drawer overlays it.
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: SafeArea(
              top: false,
              // Rebuilt off the router delegate (a ChangeNotifier) rather than
              // off this Bloc build, so the indicator is guaranteed to re-read
              // after ANY navigation -- imperative pushes included -- instead of
              // depending on the shell happening to rebuild.
              child: ListenableBuilder(
                listenable: GoRouter.of(ctx).routerDelegate,
                builder: (_, __) => GlassBottomNav(
                  destinations: kQuickNavDestinations,
                  currentIndex: navIndexForRouter(GoRouter.of(ctx)),
                  // `go` for the 4 quick destinations specifically: these are
                  // top-level tabs, so re-selecting one should replace, not
                  // stack Home on top of Home.
                  onTap: (i) => ctx.go(kQuickNavDestinations[i].route),
                ),
              ),
            ),
          ),
          // Dim overlay behind the slide menu. Used to also run a
          // BackdropFilter blur here -- BackdropFilter is one of the most
          // expensive operations in Flutter's rendering pipeline (a full
          // framebuffer readback + Gaussian blur + recomposite), and this
          // one covered the ENTIRE screen for the whole time the menu
          // stayed open, not just a single frame -- a real, continuous
          // rendering cost live in both debug and release builds, reported
          // as the whole app "feeling heavy" specifically while the menu
          // was open and being scrolled. A plain dim has no such cost.
          if(state.isOpen)
            GestureDetector(
              onTap:()=>ctx.read<ShellBloc>().add(CloseMenu()),
              child: AnimatedOpacity(
                duration: LiquidGlass.motionStandard,
                curve: LiquidGlass.motionCurve,
                opacity: state.isOpen ? 1 : 0,
                child: Container(color: Colors.black.withValues(alpha: 0.45)),
              ),
            ),
          // Slide menu
          AnimatedPositioned(
            duration: LiquidGlass.motionStandard,
            curve: LiquidGlass.motionCurve,
            left: state.isOpen ? 0 : -320,
            top:0, bottom:0, width:300,
            child: const SlideMenu(),
          ),
        ])),
        );
      },
      ),
    );
  }
}
