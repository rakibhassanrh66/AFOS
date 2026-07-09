import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../config/theme/app_colors.dart';
import '../../../core/navigation/back_press_tracker.dart';
import '../../../shared/widgets/offline_banner.dart';
import '../../sos/presentation/sos_floating_button.dart';
import '../bloc/shell_bloc.dart';
import 'slide_menu.dart';

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
  void _handleBack(BuildContext context) {
    final router = GoRouter.of(context);
    final loc = GoRouterState.of(context).matchedLocation;
    if (loc == '/home') {
      _confirmExit(context);
      return;
    }
    final tracker = BackPressTracker.instance;
    if (tracker.consecutiveBackPresses >= 3) {
      tracker.consecutiveBackPresses = 0;
      router.go('/home');
      return;
    }
    tracker.consecutiveBackPresses++;
    if (router.canPop()) {
      router.pop();
    } else {
      tracker.consecutiveBackPresses = 0;
      router.go('/home');
    }
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
      builder:(ctx,state) => Scaffold(
        backgroundColor: AppColors.surfaceOf(context),
        body: Stack(children:[
          OfflineBanner(child: child),
          // Persistent across every authenticated screen -- only reachable
          // once the router's profile-completed/verified gates have
          // already passed, since AppShell itself is only ever built for
          // routes inside the gated ShellRoute.
          const SosFloatingButton(),
          // Dim + blur overlay behind the slide menu
          if(state.isOpen)
            GestureDetector(
              onTap:()=>ctx.read<ShellBloc>().add(CloseMenu()),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds:250),
                curve: Curves.easeOutCubic,
                opacity: state.isOpen ? 1 : 0,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                  child: Container(
                    color: Colors.black.withOpacity(0.45),
                  ),
                ),
              ),
            ),
          // Slide menu
          AnimatedPositioned(
            duration: const Duration(milliseconds:300),
            curve: Curves.easeOutCubic,
            left: state.isOpen ? 0 : -320,
            top:0, bottom:0, width:300,
            child: const SlideMenu(),
          ),
        ]),
      ),
      ),
    );
  }
}
