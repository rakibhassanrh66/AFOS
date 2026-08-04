import 'package:flutter/widgets.dart';

/// How many immersive routes are currently mounted.
///
/// An immersive route is one where the floating bottom nav is not just
/// unhelpful but actively in the way: a conversation. The message composer is
/// pinned to the bottom of the screen, which is exactly where the bar floats,
/// so the two collided — the send button and the field sat under the glass,
/// reachable only by guessing where the bar ended.
///
/// PADDING THE COMPOSER ABOVE THE BAR WAS THE WRONG FIX. It buys clearance by
/// spending the scarcest space on the screen: a chat is a bottom-anchored
/// list, so every pixel reserved for a bar nobody is going to press comes
/// straight out of the messages. And a translucent bar floating over a
/// scrolling transcript is visual noise with no function — the four quick
/// destinations are not what anyone wants mid-conversation.
///
/// So the bar is removed for the duration instead, and its clearance with it.
/// Leaving is the back arrow already in the app bar, or the system back
/// gesture — both of which were always there.
///
/// Deliberately NOT solved by painting something opaque behind the composer.
/// That would trade a collision for a solid slab across the bottom of a glass
/// interface, and `LiquidBackdrop`/`BackdropFilter` with an opaque layer over
/// it renders as a flat rectangle rather than frost (the same mistake that
/// produced "a rectangle inside a rectangle" on the sheets).
///
/// A COUNTER, not a bool, for the same reason [openGlassSheetCount] is one: a
/// push transition mounts the incoming route before the outgoing one is
/// disposed, so chat-to-chat navigation would flash the bar back on for a
/// frame if this could only ever be true or false.
final ValueNotifier<int> immersiveRouteCount = ValueNotifier<int>(0);

/// Marks everything below it as immersive: `AppShell` hides the floating nav
/// and stops reserving its clearance for as long as this is mounted.
///
/// Wrap the whole screen, not just its body — the count must be held for the
/// route's entire lifetime, however it is dismissed (pop, back gesture,
/// hardware back), which is what tying it to State lifecycle guarantees.
class ImmersiveScope extends StatefulWidget {
  final Widget child;
  const ImmersiveScope({super.key, required this.child});

  @override
  State<ImmersiveScope> createState() => _ImmersiveScopeState();
}

class _ImmersiveScopeState extends State<ImmersiveScope> {
  /// Whether this scope currently owns a unit of the count.
  ///
  /// Needed because the increment is deferred by a frame and the route can be
  /// gone before it lands (push then immediately pop). Without it, dispose
  /// could decrement a count this scope never added and un-hide the bar on some
  /// OTHER chat that is still open.
  bool _held = false;

  // BOTH SIDES ARE DEFERRED TO AFTER THE FRAME, and that is not optional.
  //
  // AppShell is an ANCESTOR of this widget and watches [immersiveRouteCount].
  // `initState` runs while the frame that mounts this route is still building,
  // and AppShell was already built earlier in that same pass — so touching the
  // notifier there marks an already-built ancestor dirty and trips Flutter's
  // "setState() or markNeedsBuild() called during build". `dispose` has the
  // same problem in the other direction: it runs while the element tree is
  // being finalised.
  //
  // This is why the pattern differs from `openGlassSheetCount`, which can
  // mutate synchronously: that one is driven from a tap handler, which is
  // never inside a build.
  //
  // Cost is one frame at each end, spent during the push/pop transition where
  // the bar is sliding out of view anyway.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _held = true;
      immersiveRouteCount.value++;
    });
  }

  @override
  void dispose() {
    if (_held) {
      _held = false;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => immersiveRouteCount.value--);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
