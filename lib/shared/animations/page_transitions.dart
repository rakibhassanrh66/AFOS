import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme/liquid_glass_tokens.dart';

// Every page transition shares one duration + curve + entrance-scale
// (LiquidGlass.motionStandard / motionCurve / entranceScaleFrom); only the
// translate/fade character differs per style, so navigation feels like one
// consistent system.

CustomTransitionPage<T> fadeScalePage<T>(Widget child, GoRouterState state) =>
  CustomTransitionPage<T>(key:state.pageKey, child:child,
    transitionDuration: LiquidGlass.motionStandard,
    transitionsBuilder: (_,a,__,c) => FadeTransition(
      opacity: CurvedAnimation(parent:a,curve:LiquidGlass.motionCurve),
      child: ScaleTransition(
        scale: Tween(begin:LiquidGlass.entranceScaleFrom,end:1.0)
            .animate(CurvedAnimation(parent:a,curve:LiquidGlass.motionCurve)),
        child: c)));

CustomTransitionPage<T> slideRightPage<T>(Widget child, GoRouterState state) =>
  CustomTransitionPage<T>(key:state.pageKey, child:child,
    transitionDuration: LiquidGlass.motionStandard,
    transitionsBuilder: (_,a,__,c) => SlideTransition(
      position: Tween(begin:const Offset(-0.08,0),end:Offset.zero)
        .animate(CurvedAnimation(parent:a,curve:LiquidGlass.motionCurve)),
      child: FadeTransition(opacity:CurvedAnimation(parent:a,curve:LiquidGlass.motionCurve),child:c)));

CustomTransitionPage<T> slideUpPage<T>(Widget child, GoRouterState state) =>
  CustomTransitionPage<T>(key:state.pageKey, child:child,
    transitionDuration: LiquidGlass.motionStandard,
    transitionsBuilder: (_,a,__,c) => SlideTransition(
      position: Tween(begin:const Offset(0,0.06),end:Offset.zero)
        .animate(CurvedAnimation(parent:a,curve:LiquidGlass.motionCurve)),
      child: FadeTransition(opacity:CurvedAnimation(parent:a,curve:LiquidGlass.motionCurve),child:c)));

/// Shared route for imperative `Navigator.push` of nested screens that live
/// outside the go_router table (chat rooms, the payment webview) — so they
/// get the exact same slide+fade as `slideRightPage` instead of the default
/// platform MaterialPageRoute transition. Honors reduced motion.
Route<T> appPageRoute<T>(Widget child) => PageRouteBuilder<T>(
      transitionDuration: LiquidGlass.motionStandard,
      reverseTransitionDuration: LiquidGlass.motionStandard,
      pageBuilder: (_, __, ___) => child,
      transitionsBuilder: (context, a, __, c) {
        if (MediaQuery.of(context).disableAnimations) return c;
        return SlideTransition(
          position: Tween(begin: const Offset(-0.08, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: LiquidGlass.motionCurve)),
          child: FadeTransition(
              opacity: CurvedAnimation(parent: a, curve: LiquidGlass.motionCurve),
              child: c),
        );
      },
    );
