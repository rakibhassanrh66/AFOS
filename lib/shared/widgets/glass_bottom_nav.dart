import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../config/theme/app_colors.dart';
import '../../config/theme/liquid_glass_tokens.dart';

/// One destination in the floating bottom nav.
class BottomNavDest {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final String route;
  const BottomNavDest({required this.label, required this.icon, IconData? activeIcon, required this.route})
      : activeIcon = activeIcon ?? icon;
}

/// AFOS "planet" bottom navigation — a floating, detached bar whose top surface
/// **dents into a gravity valley** under a weighty brand-teal planet hovering
/// just above it: the planet never touches the bar, but the bar visibly gives
/// way beneath its mass. Tapping a tab makes the planet **glide across and
/// roll** onto it (the disc spins while its icon counter-rotates to stay
/// upright), settling on an `easeInOutCubic` so it reads as heavy-but-floating.
///
/// Selection is route-derived: the planet sits on whichever tab matches the
/// current screen (Settings when on Settings, Profile on Profile, …) and rests
/// on **Home** for any screen that isn't one of the tabs. Colors and icons come
/// from the app's own palette — one teal accent, never per-tab hues.
class GlassBottomNav extends StatefulWidget {
  final List<BottomNavDest> destinations;

  /// Route-derived index of the active tab, or -1 when the current screen isn't
  /// one of the tabs (the planet then rests on Home but a tap still navigates).
  final int currentIndex;
  final ValueChanged<int> onTap;
  const GlassBottomNav({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onTap,
  });

  static const double barHeight = 75;
  static const double planetSize = 50;

  /// How far the planet floats above the bar's top edge. Deliberately larger
  /// than half the planet so it clears the surface entirely — zero contact.
  static const double planetLift = 24;
  static const double bottomMargin = 24;
  static const double sideMargin = 16;

  /// Total vertical footprint the floating nav needs, so routed content can
  /// physically clear it (see `AppShell`'s `barSpace`). Carries a few px slack
  /// over the real height (`planetLift + barHeight + bottomMargin`).
  static const double reservedHeight = barHeight + planetLift + bottomMargin + 6;

  /// Bottom padding a SCROLLABLE must add to its own content so the last row
  /// can be scrolled clear of the floating bar.
  ///
  /// The shell hands clearance down as a `MediaQuery` bottom inset rather than
  /// as physical padding, so that routed content runs full-bleed and actually
  /// scrolls *under* the glass — a `BackdropFilter` with nothing painted behind
  /// it renders as an opaque slab, which is what made the bar read as "a
  /// rectangle inside a rectangle". `BoxScrollView` adopts that inset
  /// automatically, but ONLY when its `padding` is null; every scrollable in
  /// this app hard-codes its padding and therefore opts out. Those add this
  /// constant explicitly.
  ///
  /// Deliberately a compile-time `const` (not a MediaQuery read) so the call
  /// sites stay `const` and need no `BuildContext` in scope.
  static const double navContentClearance = reservedHeight;

  @override
  State<GlassBottomNav> createState() => _GlassBottomNavState();
}

class _GlassBottomNavState extends State<GlassBottomNav> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _move;
  int _prev = 0;

  // Where the planet actually rests: the matching tab, or Home (0) when the
  // current screen isn't a tab. (Kept separate from currentIndex so a tap from
  // a non-tab screen onto Home still navigates.)
  int get _display => _displayOf(widget.currentIndex, widget.destinations.length);

  int _displayOf(int index, int len) => (index >= 0 && index < len) ? index : 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    // easeInOutCubic gives the smooth, weighty glide of the reference design.
    _move = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutCubic);
    _ctrl.value = 1.0; // at rest, the planet sits on its target
    _prev = _display;
  }

  @override
  void didUpdateWidget(covariant GlassBottomNav old) {
    super.didUpdateWidget(old);
    final oldDisplay = _displayOf(old.currentIndex, old.destinations.length);
    if (oldDisplay != _display) {
      _prev = oldDisplay;
      if (MediaQuery.of(context).disableAnimations) {
        _ctrl.value = 1.0;
      } else {
        _ctrl.forward(from: 0.0); // float across + roll onto the new tab
      }
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _handleTap(int i) {
    if (i == widget.currentIndex) return; // already on this exact screen
    HapticFeedback.selectionClick();
    widget.onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.destinations.length;
    // Translucent enough that the BackdropFilter behind it genuinely reads as
    // frosted glass, opaque enough that the valley silhouette stays legible.
    final fill = Color.alphaBlend(
      AppColors.glassFill(context),
      AppColors.surfaceOf(context).withValues(alpha: 0.62),
    );
    final border = AppColors.glassBorder(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          GlassBottomNav.sideMargin, GlassBottomNav.planetLift, GlassBottomNav.sideMargin, GlassBottomNav.bottomMargin),
      child: SizedBox(
        height: GlassBottomNav.barHeight,
        child: AnimatedBuilder(
          animation: _move,
          builder: (context, _) {
            return LayoutBuilder(builder: (context, c) {
              final w = c.maxWidth;
              final seg = w / n;
              double centerOf(int i) => seg * i + seg / 2;
              final planetCenterX = _lerp(centerOf(_prev), centerOf(_display), _move.value);
              final planetLeft = planetCenterX - GlassBottomNav.planetSize / 2;
              // Roll direction + amount scale with how far it travels, so a
              // 3-tab jump spins more than a neighbour hop.
              final dir = (_display >= _prev) ? 1.0 : -1.0;
              final dist = (_display - _prev).abs().clamp(1, n).toDouble();
              final spinTurns = _move.value * dir * dist;

              return Stack(clipBehavior: Clip.none, children: [
                // LAYER 0: the bar's own soft tinted elevation. Painted OUTSIDE
                // the clip (a clipped shadow would be invisible) with a real
                // blur mask — Canvas.drawShadow ignores the passed alpha and
                // renders a muddy grey smear instead of a brand-tinted glow.
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _NavGlowPainter(
                          planetCenterX: planetCenterX,
                          glow: AppColors.holoTeal.withValues(alpha: 0.22),
                        ),
                      ),
                    ),
                  ),
                ),
                // LAYER 1: the frosted bar surface, dented into a gravity
                // valley under the planet. The SAME path drives the clip, the
                // fill and the rim, so the blur can never leak past the edge.
                Positioned.fill(
                  child: RepaintBoundary(
                    child: ClipPath(
                      clipper: _NavShapeClipper(planetCenterX),
                      clipBehavior: Clip.antiAlias,
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: LiquidGlass.blurRaised, sigmaY: LiquidGlass.blurRaised),
                        child: CustomPaint(
                          painter: _NavSurfacePainter(planetCenterX: planetCenterX, fill: fill, border: border),
                        ),
                      ),
                    ),
                  ),
                ),
                // LAYER 2: the interactive item row (icons + labels).
                Positioned.fill(
                  child: Row(children: [
                    for (var i = 0; i < n; i++)
                      Expanded(child: _NavItem(
                        dest: widget.destinations[i],
                        active: i == _display,
                        onTap: () => _handleTap(i),
                      )),
                  ]),
                ),
                // LAYER 3: the floating, rolling planet (carries the active
                // icon). IgnorePointer so taps fall through to the item below.
                Positioned(
                  left: planetLeft,
                  top: -GlassBottomNav.planetLift,
                  width: GlassBottomNav.planetSize,
                  height: GlassBottomNav.planetSize,
                  child: IgnorePointer(
                    child: Transform.rotate(
                      angle: spinTurns * 2 * math.pi,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.green, // one solid brand-teal "planet"
                          shape: BoxShape.circle,
                          boxShadow: [
                            // Deep downward cast — the planet has weight, and
                            // the shadow lands on the bar it is hovering over.
                            BoxShadow(
                              color: AppColors.holoTeal.withValues(alpha: 0.45),
                              blurRadius: 16,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Center(
                          // Counter-rotate so the icon stays upright while the
                          // planet visibly rolls beneath it.
                          child: Transform.rotate(
                            angle: -spinTurns * 2 * math.pi,
                            // Dark ink on the light teal disc, matching the
                            // app's on-accent ink rule.
                            child: Icon(widget.destinations[_display].activeIcon,
                                size: 24, color: AppColors.background),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ]);
            });
          },
        ),
      ),
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;
}

/// One tab: icon (faded out for the active tab — the planet carries it) over a
/// single-color label that warms to brand teal when active.
class _NavItem extends StatelessWidget {
  final BottomNavDest dest;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({required this.dest, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final iconColor = AppColors.textSecondaryOf(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        const SizedBox(height: 12),
        Expanded(
          child: Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              // The active tab's icon lives in the planet above, so fade the
              // in-bar copy out as the planet arrives.
              opacity: active ? 0.0 : 0.55,
              // Shrinks rather than overflowing if a large text scale squeezes
              // the icon row (the label below is clamped, but be safe anyway).
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Icon(active ? dest.activeIcon : dest.icon, size: 22, color: iconColor),
              ),
            ),
          ),
        ),
        // Nav labels are secondary chrome in a fixed-height bar: clamp their
        // growth so an accessibility text scale can't overflow the column.
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Text(
            dest.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
            style: TextStyle(
              color: active ? AppColors.green : AppColors.textSecondaryOf(context),
              fontSize: 11,
              height: 1.0,
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 12),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// The bar silhouette
// ---------------------------------------------------------------------------

const double _kCorner = 35; // pill-like rounding on all four corners
const double _kValleyHalf = 55; // half-width of the gravity dip
const double _kValleyDepth = 42; // how far the surface caves in under the planet
const double _kValleyOuterCtrl = 35; // outer cubic control, reference-exact
const double _kValleyInnerCtrl = 32; // inner cubic control, reference-exact

/// Builds the bar silhouette: a generously rounded slab whose TOP edge dips
/// into a smooth valley centred under the planet.
///
/// The control points are derived as a **fraction of the actual
/// shoulder-to-centre span**, not as a fixed offset from the centre. That
/// matters: on the first and last tab the shoulder gets clamped inward to the
/// corner arc, and fixed offsets would place a control point *left of* the
/// shoulder it follows — a non-monotonic x that bulges the dip into the rounded
/// corner. The fractions (0.64 / 0.58) reproduce the reference proportions
/// exactly whenever the shoulder isn't clamped.
///
/// Exposed (rather than private to the painter) so the clipper, the fill
/// painter, the glow painter and the geometry test all trace the identical
/// path.
@visibleForTesting
Path buildNavBarPath(Size size, double planetCenterX) {
  // The rounded slab, and a half-plane whose top edge carries the valley. The
  // valley is drawn UNCLAMPED (always a symmetric +/-_kValleyHalf around the
  // planet, exactly like the reference), running off past both ends; the
  // intersection with the slab then decides where the bar really stops.
  //
  // Clamping the valley's shoulders into the corner arc -- the previous
  // approach -- is what made the first and last tab look broken: at 360dp the
  // left span collapsed to 6px against a 55px right span, so the dip folded
  // into the corner instead of cradling the planet ("spins half and sticks").
  // Intersecting instead of clamping keeps the curve's shape identical on
  // every tab and simply lets the rounded corner crop it.
  final slab = Path()
    ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size, const Radius.circular(_kCorner)));
  return Path.combine(PathOperation.intersect, slab, _valleyHalfPlane(size, planetCenterX));
}

/// Everything at or below the valley-carrying top edge, extended well past both
/// ends so `buildNavBarPath`'s intersection is what trims it.
Path _valleyHalfPlane(Size size, double planetCenterX) {
  final w = size.width, h = size.height;
  final cx = planetCenterX;
  // Generous overshoot: must exceed the widest possible valley overhang so the
  // top edge is unbroken beyond the slab on both sides.
  final over = _kValleyHalf + _kCorner + w;
  return Path()
    ..moveTo(-over, 0)
    ..lineTo(cx - _kValleyHalf, 0)
    ..cubicTo(cx - _kValleyOuterCtrl, 0, cx - _kValleyInnerCtrl, _kValleyDepth, cx, _kValleyDepth)
    ..cubicTo(cx + _kValleyInnerCtrl, _kValleyDepth, cx + _kValleyOuterCtrl, 0, cx + _kValleyHalf, 0)
    ..lineTo(w + over, 0)
    ..lineTo(w + over, h + over)
    ..lineTo(-over, h + over)
    ..close();
}

/// The seven x-coordinates the valley traces, in path order:
/// `[leftShoulder, c1, c2, centre, c3, c4, rightShoulder]`.
///
/// Every offset is FIXED relative to the planet centre, so the dip is the same
/// symmetric shape on every tab — including the first and last, where it simply
/// overhangs the slab and gets cropped by `buildNavBarPath`'s intersection
/// rather than being squashed into the corner arc.
///
/// Monotonicity is therefore true by construction
/// (`-55 < -35 < -32 < 0 < 32 < 35 < 55`) instead of being something the
/// clamping had to be careful not to violate. Still asserted in
/// `glass_bottom_nav_test.dart` so the invariant can't regress.
///
/// [width] no longer affects the result and is kept only so existing callers
/// and tests keep compiling; the valley is never width-clamped.
@visibleForTesting
List<double> navValleyXs(double width, double planetCenterX) {
  final cx = planetCenterX;
  return [
    cx - _kValleyHalf,
    cx - _kValleyOuterCtrl,
    cx - _kValleyInnerCtrl,
    cx,
    cx + _kValleyInnerCtrl,
    cx + _kValleyOuterCtrl,
    cx + _kValleyHalf,
  ];
}

/// Clips the frosted layer to the bar silhouette so the blur stops at the edge.
class _NavShapeClipper extends CustomClipper<Path> {
  final double planetCenterX;
  const _NavShapeClipper(this.planetCenterX);

  @override
  Path getClip(Size size) => buildNavBarPath(size, planetCenterX);

  @override
  bool shouldReclip(covariant _NavShapeClipper old) => old.planetCenterX != planetCenterX;
}

/// Fills the (already clipped) bar and strokes its rim.
class _NavSurfacePainter extends CustomPainter {
  final double planetCenterX;
  final Color fill;
  final Color border;
  const _NavSurfacePainter({required this.planetCenterX, required this.fill, required this.border});

  @override
  void paint(Canvas canvas, Size size) {
    final path = buildNavBarPath(size, planetCenterX);
    canvas.drawPath(path, Paint()..color = fill..style = PaintingStyle.fill);
    canvas.drawPath(path, Paint()
      ..color = border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _NavSurfacePainter old) =>
      old.planetCenterX != planetCenterX || old.fill != fill || old.border != border;
}

/// Paints the bar's ambient tinted glow beneath it (outside the clip).
class _NavGlowPainter extends CustomPainter {
  final double planetCenterX;
  final Color glow;
  const _NavGlowPainter({required this.planetCenterX, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    final path = buildNavBarPath(size, planetCenterX);
    canvas.save();
    canvas.translate(0, 8);
    canvas.drawPath(path, Paint()
      ..color = glow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NavGlowPainter old) =>
      old.planetCenterX != planetCenterX || old.glow != glow;
}
