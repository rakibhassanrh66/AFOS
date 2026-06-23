import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

CustomTransitionPage<T> fadeScalePage<T>(Widget child, GoRouterState state) =>
  CustomTransitionPage<T>(key:state.pageKey, child:child,
    transitionDuration: const Duration(milliseconds:350),
    transitionsBuilder: (_,a,__,c) => FadeTransition(
      opacity: CurvedAnimation(parent:a,curve:Curves.easeOut),
      child: ScaleTransition(
        scale: Tween(begin:0.93,end:1.0).animate(CurvedAnimation(parent:a,curve:Curves.easeOutCubic)),
        child: c)));

CustomTransitionPage<T> slideRightPage<T>(Widget child, GoRouterState state) =>
  CustomTransitionPage<T>(key:state.pageKey, child:child,
    transitionDuration: const Duration(milliseconds:300),
    transitionsBuilder: (_,a,__,c) => SlideTransition(
      position: Tween(begin:const Offset(-0.08,0),end:Offset.zero)
        .animate(CurvedAnimation(parent:a,curve:Curves.easeOutCubic)),
      child: FadeTransition(opacity:CurvedAnimation(parent:a,curve:Curves.easeOut),child:c)));

CustomTransitionPage<T> slideUpPage<T>(Widget child, GoRouterState state) =>
  CustomTransitionPage<T>(key:state.pageKey, child:child,
    transitionDuration: const Duration(milliseconds:400),
    transitionsBuilder: (_,a,__,c) => SlideTransition(
      position: Tween(begin:const Offset(0,0.06),end:Offset.zero)
        .animate(CurvedAnimation(parent:a,curve:Curves.easeOutCubic)),
      child: FadeTransition(opacity:CurvedAnimation(parent:a,curve:Curves.easeOut),child:c)));
