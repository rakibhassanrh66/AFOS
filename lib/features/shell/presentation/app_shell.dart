import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme/app_colors.dart';
import '../../../config/theme/app_icons.dart';
import '../../../config/theme/liquid_glass_tokens.dart';
import '../../../core/layout/immersive_scope.dart';
import '../../../core/navigation/back_press_tracker.dart';
import '../../../core/navigation/router_location.dart';
import '../../../core/utils/responsive.dart';
import '../../../shared/widgets/glass_bottom_nav.dart';
import '../../../shared/widgets/glass_sheet.dart';
import '../../../shared/widgets/liquid_backdrop.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../sos/presentation/sos_floating_button.dart';
import '../bloc/shell_bloc.dart';
import 'command_palette.dart';
import '../../web/presentation/web_sidebar.dart';
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
    // Was one BlocBuilder<ShellBloc,ShellState> wrapping this entire method
    // (desktop AND mobile Scaffold, SosGate, bottom nav, the routed screen
    // itself) — but only the dim overlay + AnimatedPositioned menu near the
    // bottom actually read `state.isOpen`. Every open/close toggle was
    // rebuilding the whole authenticated shell for nothing; that pair is now
    // the only thing scoped to a BlocBuilder, further down.
    //
    // Web-only: a tablet or a foldable running the native Android/iOS
    // app should still get the normal touch drawer at any width -- this
    // is specifically about a mouse-and-keyboard browser window, not
    // "wide screen" in general.
    final isDesktop = kIsWeb && Responsive.isExpanded(context);

    // CONTENT WIDTH ON DESKTOP: 1440, not 1100, and not unlimited.
    //
    // `AdaptiveContentWidth` centres everything in a 1100px column above
    // 600px. On a 1920px monitor that threw away 800px and rendered a
    // thirty-item queue as a ribbon down the middle — the single clearest
    // reason the web build read as "a phone app someone forgot to resize".
    //
    // The first fix here was to remove it on desktop entirely. That was wrong
    // in the other direction: a list of cards stretched to 1900px is not
    // denser, it is just a line of text with 1700px of dead space after it,
    // and long line lengths are harder to read, not easier. Neither extreme is
    // the answer.
    //
    // 1440 is the working width: wide enough for a real table, a master/detail
    // split, or four columns of a grid, and narrow enough that a line of body
    // text stays readable. Screens that want more say so with `WebFullBleed`;
    // screens that want less say so with `WebPage(maxContentWidth:)`. The
    // shell sets a sane default instead of deciding for everyone.
    //
    // Below the desktop breakpoint nothing changes: tablets and narrow browser
    // windows keep the 1100px letterbox they had.
    Widget content = OfflineBanner(
      child: isDesktop
          ? Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: child,
              ),
            )
          : AdaptiveContentWidth(child: child),
    );

    // Ctrl/Cmd+K anywhere in the authenticated shell.
    //
    // `kIsWeb` is a compile-time constant, so this whole branch — and with it
    // CommandPalette and everything it references — is eliminated from the
    // Android AOT build. Phase 6's rule is that web features must not grow the
    // APK, and this is the mechanism that makes that true rather than hoped
    // for. Verified by measuring the APK before and after, not by assertion.
    //
    // Wrapped around the CONTENT rather than the whole shell so the shortcut
    // is live wherever focus is, including inside a routed screen's own
    // Shortcuts scope, which would otherwise swallow the key first.
    if (kIsWeb) {
      content = _PaletteShortcut(child: content);
    }
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
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          _handleBack(context);
        },
        child: Scaffold(
          backgroundColor: AppColors.surfaceOf(context),
          // WebSidebar, not SlideMenu(permanent: true).
          //
          // The rail was the phone drawer stood on its end: every capability
          // in one flat list, which for a super_admin is twenty-five identical
          // rows. Finding "Manage Exam Seats" meant reading twenty-five labels
          // in order. The sidebar groups them (You / Academics / Campus /
          // Operations / Oversight) from the same capability model the menu
          // now reads, so the two cannot disagree.
          //
          // 264 rather than 248: the group headings need the room, and a
          // sidebar that ellipsises "Course Offerings" is not navigation.
          body: LiquidBackdrop(child: Row(children: [
            const SizedBox(width: 264, child: WebSidebar()),
            Expanded(child: Stack(children: [
              content,
              const SosGate(),
            ])),
          ])),
        ),
      );
    }
    // Mobile/tablet: reserve space at the bottom (via a MediaQuery inset)
    // so screens that honor bottom padding clear the floating bar, and
    // highlight whichever of the 4 quick destinations is the active route.
    final mq = MediaQuery.of(context);
    // ── The single source of floating-nav clearance ────────────────────
    //
    // Clearance is handed down as a MediaQuery BOTTOM INSET, never as
    // physical Padding on the routed content, and screens read it back
    // through `NavInsets` (core/layout/nav_insets.dart) — which is the ONLY
    // supported way to ask for it. `GlassBottomNav.navContentClearance` used
    // to be a second, competing mechanism that screens hard-coded on top of
    // this inset; the two double-counted, which is what ended content
    // 145-219px above the bar. Nothing was then left behind the glass, and a
    // BackdropFilter with nothing behind it to blur renders as a plain opaque
    // slab ("a rectangle inside a rectangle"). That constant is gone.
    //
    // Clearance reaches naive screens for free because `BoxScrollView`
    // (ListView/GridView) with a null `padding` adopts MediaQuery's vertical
    // padding automatically, and SafeArea consumes it too.
    final keyboard = mq.viewInsets.bottom;
    // Drawer width: the old hard-coded 300 left only ~20px of scrim on a small
    // phone, so the menu read as a full-screen takeover with no visible way
    // back to the content behind it.
    final menuWidth = mq.size.width * 0.86 < 300 ? mq.size.width * 0.86 : 300.0;

    // Immersive routes (the chats) drop the bar AND its clearance together.
    // Both have to move as one: hiding the bar while still reserving its
    // height would leave a dead band across the bottom of the conversation,
    // and dropping the clearance while the bar still painted would put it back
    // on top of the composer. See core/layout/immersive_scope.dart.
    return ValueListenableBuilder<int>(
      valueListenable: immersiveRouteCount,
      builder: (context, immersiveCount, _) {
        final immersive = immersiveCount > 0;
        // While the keyboard is up the nav is BEHIND it (see
        // resizeToAvoidBottomInset: false below — the bar stays pinned to the
        // physical screen bottom instead of re-anchoring onto the IME and
        // covering the bottom 129px of every search result list). A hidden bar
        // needs no clearance, so the inset collapses and search gets the space
        // back. The device's own gesture inset is kept either way — that one is
        // physical and does not go away because the bar did.
        final bottomInset = keyboard > 0
            ? 0.0
            : mq.padding.bottom +
                (immersive ? 0.0 : GlassBottomNav.contentClearance);
        return _buildMobile(
          context,
          mq: mq,
          keyboard: keyboard,
          bottomInset: bottomInset,
          menuWidth: menuWidth,
          immersive: immersive,
          content: content,
        );
      },
    );
  }

  Widget _buildMobile(
    BuildContext context, {
    required MediaQueryData mq,
    required double keyboard,
    required double bottomInset,
    required double menuWidth,
    required bool immersive,
    required Widget content,
  }) {
    final mobileContent = Padding(
      // The shell lifts content off the keyboard itself, because Scaffold's
      // own resize would also drag the nav up with it.
      padding: EdgeInsets.only(bottom: keyboard),
      child: MediaQuery(
        data: mq.copyWith(
          padding: mq.padding.copyWith(bottom: bottomInset),
          viewPadding: mq.viewPadding.copyWith(bottom: bottomInset),
          // Consumed by the Padding above, so hand down what's LEFT — exactly
          // what Scaffold does internally. Without this, the ~24 screens that
          // pad by viewInsets themselves would lift twice.
          viewInsets: mq.viewInsets.copyWith(bottom: 0),
        ),
        child: content,
      ),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.surfaceOf(context),
        // The shell resizes `mobileContent` itself. Letting Scaffold do it
        // would shrink the whole Stack, which re-anchors the Positioned nav
        // onto the top edge of the keyboard — the bar then floats over the
        // search results it is supposed to sit below.
        resizeToAvoidBottomInset: false,
        body: LiquidBackdrop(child: Stack(children:[
          mobileContent,
          // Persistent across every authenticated screen -- only reachable
          // once the router's profile-completed/verified gates have
          // already passed, since AppShell itself is only ever built for
          // routes inside the gated ShellRoute.
          const SosGate(),
          // Floating quick-access bottom nav (mobile/tablet). Placed before
          // the scrim + drawer so an open drawer overlays it.
          // Hidden while any glass sheet is open. Sheets sit on the SHELL
          // navigator (deliberately -- see showGlassSheet), which makes them a
          // sibling of this Positioned rather than a child of it, and this one
          // comes later in the Stack so it painted straight over them. On the
          // New Course Offering form that put the frosted bar on top of the
          // Submit button, which read as "an extra square box" cutting the
          // form off. GlassSheet drops the matching bottom clearance for the
          // same window, so nothing is left reserving space for a hidden bar.
          ValueListenableBuilder<int>(
            valueListenable: openGlassSheetCount,
            // `immersive` joins the same test rather than getting a branch of
            // its own: both mean "there is no bar right now", and the clearance
            // above was already dropped to match.
            builder: (_, sheetCount, __) => (sheetCount > 0 || immersive)
                ? const SizedBox.shrink()
                : Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: SafeArea(
                      top: false,
                      // Rebuilt off the router delegate (a ChangeNotifier) rather than
                      // off this Bloc build, so the indicator is guaranteed to re-read
                      // after ANY navigation -- imperative pushes included -- instead of
                      // depending on the shell happening to rebuild.
                      child: ListenableBuilder(
                        listenable: GoRouter.of(context).routerDelegate,
                        builder: (_, __) => GlassBottomNav(
                          destinations: kQuickNavDestinations,
                          currentIndex: navIndexForRouter(GoRouter.of(context)),
                          // `go` for the 4 quick destinations specifically: these are
                          // top-level tabs, so re-selecting one should replace, not
                          // stack Home on top of Home.
                          onTap: (i) => context.go(kQuickNavDestinations[i].route),
                        ),
                      ),
                    ),
                  ),
          ),
          // The only part of this shell that reads ShellBloc's isOpen state
          // — scoped here (not around the whole build method above) so
          // opening/closing the menu only rebuilds this small Positioned.fill,
          // not the routed screen, SosGate, or bottom nav alongside it.
          Positioned.fill(
            child: BlocBuilder<ShellBloc, ShellState>(
              builder: (ctx, state) => Stack(children: [
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
                      // Full-bleed on purpose: the dim SHOULD cover the status
                      // and gesture bars, so the whole window reads as
                      // "behind" the menu. It is the panel below that must not.
                      child: Container(color: Colors.black.withValues(alpha: 0.45)),
                    ),
                  ),
                // Slide menu — a floating glass panel, not a full-height slab.
                //
                // It used to be pinned `top: 0, bottom: 0`, so with the app
                // running edge-to-edge (targetSdk 36 forces it on Android 15+)
                // the glass surface, its right-hand border and its glow all
                // painted straight through the status bar and the gesture bar.
                // Insetting by the real safe area instead keeps it clear of
                // both and lets it read as the same floating material as the
                // bottom nav. Width is clamped so it never swallows a narrow
                // screen whole.
                AnimatedPositioned(
                  duration: LiquidGlass.motionStandard,
                  curve: LiquidGlass.motionCurve,
                  left: state.isOpen ? 0 : -(menuWidth + 20),
                  top: mq.padding.top + 8,
                  bottom: mq.padding.bottom + 8,
                  width: menuWidth,
                  child: const SlideMenu(),
                ),
              ]),
            ),
          ),
        ])),
      ),
    );
  }
}

/// Binds Ctrl/Cmd+K to the command palette for everything beneath it.
///
/// WEB ONLY — mounted behind `kIsWeb` in [_ShellBody.build], so the Android AOT
/// build drops it and the APK never carries a palette nobody on a phone can
/// open.
///
/// Both Control and Meta are bound rather than detecting the platform: a web
/// app is opened from Windows, macOS and Linux by the same build, and a user
/// who reaches for the wrong modifier should still get the palette rather than
/// learn that this app is the one that disagrees.
class _PaletteShortcut extends StatelessWidget {
  final Widget child;
  const _PaletteShortcut({required this.child});

  @override
  Widget build(BuildContext context) => Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.keyK, control: true): _OpenPaletteIntent(),
          SingleActivator(LogicalKeyboardKey.keyK, meta: true): _OpenPaletteIntent(),
        },
        child: Actions(
          actions: {
            _OpenPaletteIntent: CallbackAction<_OpenPaletteIntent>(
              onInvoke: (_) {
                // Guard against stacking: Ctrl+K with the palette already open
                // must not push a second one behind the first.
                if (ModalRoute.of(context)?.isCurrent ?? true) {
                  CommandPalette.show(context);
                }
                return null;
              },
            ),
          },
          // Focus so the shortcut is live without the user first clicking
          // something. `skipTraversal` keeps it out of the Tab order — it is a
          // listener, not a stop on the way through the page.
          child: Focus(autofocus: true, skipTraversal: true, child: child),
        ),
      );
}

class _OpenPaletteIntent extends Intent {
  const _OpenPaletteIntent();
}
