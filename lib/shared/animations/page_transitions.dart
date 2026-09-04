import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/theme/motion.dart';

/// One transition system, three characters. Every page shares the same
/// duration, curve and entrance scale; only the translate/fade differs, so
/// navigation reads as one thing rather than three.
///
/// TWO FAULTS LIVED HERE, AND BOTH SURFACED AS "THE APP FEELS SLOW".
///
///  1. REDUCED MOTION WAS IGNORED ON EVERY ROUTED SCREEN. Only
///     [appPageRoute] — used by a handful of imperatively pushed screens —
///     checked `disableAnimations`. The three go_router builders below, which
///     are how essentially all 62 screens are actually reached, animated
///     regardless of what the user had asked the system for. motion.dart's
///     own audit note says that setting "currently does almost nothing"; this
///     file was the largest single reason why.
///
///  2. GOING BACK COST AS MUCH AS GOING FORWARD. Both directions ran at
///     [AppMotion.base]. A push introduces something new and can justify the
///     time; a pop returns to a screen the user has already seen and is
///     already holding in their head, so spending the same 240ms on it is
///     what makes back navigation feel heavy. Reverse now runs at
///     [AppMotion.tight].

/// The per-style part: given an already-curved animation, wrap the child.
typedef _Character = Widget Function(Animation<double> curved, Widget child);

CustomTransitionPage<T> _page<T>(
  Widget child,
  GoRouterState state,
  _Character character,
) =>
    CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: AppMotion.base,
      reverseTransitionDuration: AppMotion.tight,
      transitionsBuilder: (context, animation, _, c) {
        // Returning the child unwrapped is the correct answer, not a
        // zero-duration tween: it builds no transition widgets at all.
        if (AppMotion.isReduced(context)) return c;
        return character(
          CurvedAnimation(parent: animation, curve: AppMotion.standard),
          c,
        );
      },
    );

CustomTransitionPage<T> fadeScalePage<T>(Widget child, GoRouterState state) =>
    _page<T>(
      child,
      state,
      (a, c) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween(begin: AppMotion.entranceScaleFrom, end: 1.0).animate(a),
          child: c,
        ),
      ),
    );

CustomTransitionPage<T> slideRightPage<T>(Widget child, GoRouterState state) =>
    _page<T>(
      child,
      state,
      (a, c) => SlideTransition(
        position:
            Tween(begin: const Offset(-0.08, 0), end: Offset.zero).animate(a),
        child: FadeTransition(opacity: a, child: c),
      ),
    );

CustomTransitionPage<T> slideUpPage<T>(Widget child, GoRouterState state) =>
    _page<T>(
      child,
      state,
      (a, c) => SlideTransition(
        position:
            Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(a),
        child: FadeTransition(opacity: a, child: c),
      ),
    );

/// Shared route for imperative `Navigator.push` of nested screens that live
/// outside the go_router table (chat rooms, the payment webview) — so they get
/// the exact same slide+fade as [slideRightPage] instead of the default
/// platform MaterialPageRoute transition.
Route<T> appPageRoute<T>(Widget child) => PageRouteBuilder<T>(
      transitionDuration: AppMotion.base,
      reverseTransitionDuration: AppMotion.tight,
      pageBuilder: (_, __, ___) => child,
      transitionsBuilder: (context, a, __, c) {
        if (AppMotion.isReduced(context)) return c;
        final curved = CurvedAnimation(parent: a, curve: AppMotion.standard);
        return SlideTransition(
          position: Tween(begin: const Offset(-0.08, 0), end: Offset.zero)
              .animate(curved),
          child: FadeTransition(opacity: curved, child: c),
        );
      },
    );
