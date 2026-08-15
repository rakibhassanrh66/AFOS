import 'package:flutter/material.dart';

import '../../config/theme/motion.dart';
import '../../core/haptics/app_haptics.dart';

/// Law 4, as a widget: **every gesture answers within 100ms.**
///
/// WHY THIS EXISTS. The audit counted 60 raw `GestureDetector`s and 181
/// `onTap:` sites against **two** shared widgets that implement a press state
/// at all (`afos_button`, `glass_card`). Everything else answers a touch with
/// nothing at all until the navigation or the network call completes — which,
/// on a slow connection, is the difference between "premium" and "did it even
/// register?". The fix is not to hand-roll `onTapDown`/`AnimatedScale` into
/// sixty files, because sixty hand-rolled copies drift; it is one wrapper.
///
/// WHAT IT GUARANTEES
///  * The visual answer starts in the **same frame** as touch-down. `setState`
///    on `onTapDown` schedules for the next frame, and `AnimatedScale` then
///    drives 1.0 → 0.97 over [AppMotion.instant] (90ms) — inside the 100ms
///    budget, and inside one frame at 120Hz on this project's target device.
///  * The release is **overshoot-free**. [AppMotion.standard] is `easeOutCubic`
///    and does not spring past 1.0. A control that bounces bigger than its
///    resting size under the finger reads as unstable, which is exactly why
///    [AppMotion.emphasis] is documented as *not* for press feedback.
///  * The haptic fires on **commit**, never on press — see [AppHaptics]. It is
///    on by default here, and safe to leave on even when the handler fires its
///    own: `AppHaptics` coalesces within one gesture and keeps the strongest,
///    so a `Pressable` wrapping a save button that reports `success` produces
///    one medium impact, not a click followed by a thud.
///  * Reduced motion collapses the scale animation but **keeps the press
///    state**. "Reduce motion" means do not animate; it does not mean stop
///    telling me the button was pressed.
///
/// WHAT IT DELIBERATELY DOES NOT DO. No ripple. Material's ink splash belongs
/// to Material surfaces, and this app's surfaces are glass — a circular ink
/// spread under a translucent card reads as a rendering artifact. Where
/// Material semantics genuinely apply, use `InkWell` instead of this.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Scale at full press. The default is the constitution's 0.97. Override only
  /// for a surface large enough that 3% reads as a jolt (a full-width hero),
  /// never to make a small control livelier.
  final double pressedScale;

  /// Fire [AppHaptics.selection] on commit. Turn off only where the surface is
  /// not really a control — a card that merely expands in place, say.
  final bool haptic;

  /// Pointer cursor on web/desktop. No effect on touch.
  final bool cursor;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = AppMotion.pressScale,
    this.haptic = true,
    this.cursor = true,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _set(bool v) {
    if (!_enabled || _pressed == v) return;
    setState(() => _pressed = v);
  }

  void _commit() {
    if (widget.onTap == null) return;
    if (widget.haptic) AppHaptics.selection();
    widget.onTap!();
  }

  void _commitLong() {
    if (widget.onLongPress == null) return;
    // A long-press is a deliberate, heavier act than a tap, and it usually
    // opens something destructive or modal. It gets the stronger texture.
    if (widget.haptic) AppHaptics.warning();
    widget.onLongPress!();
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? widget.pressedScale : 1.0;
    return MouseRegion(
      cursor: widget.cursor && _enabled
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: _enabled ? _commit : null,
        onLongPress: widget.onLongPress == null ? null : _commitLong,
        child: AnimatedScale(
          scale: scale,
          // Zero under reduced motion: the state still changes, it just
          // arrives instantly instead of easing.
          duration: AppMotion.durationOf(context, AppMotion.instant),
          curve: AppMotion.standard,
          child: widget.child,
        ),
      ),
    );
  }
}
