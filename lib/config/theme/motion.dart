import 'package:flutter/material.dart';

/// The app's motion ladder — one source of truth for how long anything takes
/// and how it eases.
///
/// WHY THIS EXISTS. Before this file there were two duration constants
/// (`LiquidGlass.motionFast` 200ms, `motionStandard` 280ms) and **66 raw
/// `Duration(milliseconds: …)` literals scattered through `lib/`**. Two things
/// follow from that, and both are visible:
///
///  * Nothing encoded MASS. A 40px chip and a full-screen sheet used the same
///    280ms, so the small thing felt sluggish and the large thing felt abrupt.
///  * The scattered literals drifted. There is no way to retune the app's feel
///    when the numbers live in 66 places.
///
/// The ladder below is ordered by the SIZE of the thing being moved, because
/// that is what the eye reads as weight:
///
/// | token     | duration | use                                        |
/// |-----------|----------|--------------------------------------------|
/// | [instant] | 90ms     | press state, ripple, toggle                |
/// | [tight]   | 160ms    | chip, badge, icon swap                     |
/// | [base]    | 240ms    | card expand, tab switch                    |
/// | [slow]    | 380ms    | bottom sheet, dialog, page push            |
/// | [hero]    | 620ms    | splash → home, shared element              |
///
/// Nothing in this app may exceed [hero]. If something needs longer, it is not
/// a transition — it is a process, and it needs a progress indicator instead.
///
/// ACCESSIBILITY IS NOT OPTIONAL HERE. Every duration must be read through
/// [durationOf] (or [isReduced]) so that a user who has switched on "reduce
/// motion" actually gets none. Reading these constants directly is a bug: the
/// audit found only 9 references to `disableAnimations` in 188 files against
/// ~66 hardcoded durations, which is why that setting currently does almost
/// nothing.
class AppMotion {
  AppMotion._();

  // ---------------------------------------------------------------- durations

  /// Press feedback and anything the finger is still touching. Must be short
  /// enough that the visual change lands in the same frame as the touch.
  static const Duration instant = Duration(milliseconds: 90);

  /// Small elements that carry little implied mass.
  static const Duration tight = Duration(milliseconds: 160);

  /// The default for most interface movement.
  static const Duration base = Duration(milliseconds: 240);

  /// Large surfaces entering or leaving: sheets, dialogs, page routes.
  static const Duration slow = Duration(milliseconds: 380);

  /// Reserved for the one signature moment per session — the splash handoff
  /// and true shared-element transforms. Never use this for a list item.
  static const Duration hero = Duration(milliseconds: 620);

  /// Per-item delay when a list stages its entrance, and the hard cap on how
  /// many items may stage at all.
  ///
  /// The cap matters: staggering 40 rows means the last one appears 1.6s after
  /// the first, which reads as the app being slow rather than as polish. Only
  /// the first [staggerMaxItems] animate; the rest are simply present.
  static const Duration stagger = Duration(milliseconds: 40);
  static const int staggerMaxItems = 6;

  // ------------------------------------------------------------------- curves

  /// Decelerating, no overshoot. The default for anything that is not a spring.
  static const Curve standard = Curves.easeOutCubic;

  /// For something leaving the screen, where the eye does not need to track it.
  static const Curve exit = Curves.easeInCubic;

  /// Symmetric — only for a value that moves and returns to where it started.
  static const Curve inOut = Curves.easeInOutCubic;

  // ------------------------------------------------------------------ springs
  //
  // Springs, not fixed curves, for anything the user can interrupt (a sheet
  // being dragged, a card being expanded). A curve replayed from a new position
  // restarts its easing and reads as a stutter; a spring carries its velocity
  // through and reads as physical.
  //
  // Mass is 1.0 throughout so stiffness and damping alone describe the feel:
  // higher stiffness = snappier, higher damping = less bounce. Each of these is
  // just under critical damping, so they settle without visible oscillation.

  static const SpringDescription springBase =
      SpringDescription(mass: 1, stiffness: 380, damping: 30);

  static const SpringDescription springSlow =
      SpringDescription(mass: 1, stiffness: 260, damping: 26);

  static const SpringDescription springHero =
      SpringDescription(mass: 1, stiffness: 180, damping: 22);

  // ------------------------------------------------------ press interaction
  //
  // Law 4: a gesture must answer within 100ms. These are the two numbers that
  // make a surface feel like it responded rather than like it was queued.

  static const double pressScale = 0.97;
  static const Duration pressDuration = instant;

  /// How far a surface starts below its resting scale when it enters.
  static const double entranceScaleFrom = 0.97;

  // ------------------------------------------------------------ reduced motion

  /// True when the platform (or the user's accessibility settings) has asked
  /// for animation to be suppressed.
  ///
  /// Uses `maybeDisableAnimationsOf` so this is safe to call from a context
  /// with no MediaQuery ancestor — it answers `false` rather than throwing,
  /// which matters because this is called from widget constructors deep in
  /// shared code.
  static bool isReduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// The duration to actually use. **Read every duration through this.**
  ///
  /// Returns [Duration.zero] under reduced motion, which makes an
  /// AnimatedContainer/AnimatedOpacity jump straight to its end state — the
  /// correct behaviour. It does not disable the widget, only the tweening.
  static Duration durationOf(BuildContext context, Duration d) =>
      isReduced(context) ? Duration.zero : d;

  /// Staged-entry delay for item [index], already reduced-motion aware and
  /// already capped. Returns [Duration.zero] past [staggerMaxItems] so a long
  /// list does not trickle in.
  static Duration staggerFor(BuildContext context, int index) {
    if (isReduced(context) || index >= staggerMaxItems || index < 0) {
      return Duration.zero;
    }
    return stagger * index;
  }
}
