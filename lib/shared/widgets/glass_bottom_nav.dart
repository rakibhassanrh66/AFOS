import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'dart:ui';
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

/// The app's floating, frosted-glass bottom navigation bar — detached from the
/// screen edges, rounded pill, with a single blob indicator that slides between
/// items using a real **spring simulation** (it visibly travels across the
/// intermediate items, overshoots, and settles — never teleports). Pairs a
/// selected-icon bounce with light haptics. Active tab is derived from the
/// caller (route-based), not internal index state.
class GlassBottomNav extends StatefulWidget {
  final List<BottomNavDest> destinations;
  final int currentIndex;
  final ValueChanged<int> onTap;
  const GlassBottomNav({
    super.key,
    required this.destinations,
    required this.currentIndex,
    required this.onTap,
  });

  static const double barHeight = 64;

  @override
  State<GlassBottomNav> createState() => _GlassBottomNavState();
}

class _GlassBottomNavState extends State<GlassBottomNav> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  // Animated indicator position, in "item index" units (allowed to overshoot
  // past the endpoints for the spring bounce).
  late double _pos;

  // Underdamped spring -> a little overshoot + settle.
  static final SpringDescription _spring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 380, ratio: 0.62);

  @override
  void initState() {
    super.initState();
    _pos = widget.currentIndex.toDouble();
    _ctrl = AnimationController.unbounded(vsync: this)..addListener(() {
      setState(() => _pos = _ctrl.value);
    });
  }

  @override
  void didUpdateWidget(covariant GlassBottomNav old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) _springTo(widget.currentIndex.toDouble());
  }

  void _springTo(double target) {
    if (MediaQuery.of(context).disableAnimations) {
      _ctrl.stop();
      setState(() => _pos = target);
      return;
    }
    _ctrl.animateWith(SpringSimulation(_spring, _pos, target, _ctrl.velocity));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _handleTap(int i) {
    if (i == widget.currentIndex) return;
    HapticFeedback.selectionClick();
    widget.onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.destinations.length;
    final radius = BorderRadius.circular(LiquidGlass.radiusPill);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 10 + MediaQuery.of(context).padding.bottom * 0.4),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: LiquidGlass.blurRaised, sigmaY: LiquidGlass.blurRaised),
            child: Container(
              height: GlassBottomNav.barHeight,
              decoration: BoxDecoration(
                color: Color.alphaBlend(AppColors.glassFill(context), AppColors.surfaceOf(context).withValues(alpha: 0.82)),
                borderRadius: radius,
                border: Border.all(color: AppColors.glassBorder(context), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.holoBlue.withValues(alpha: 0.14),
                    blurRadius: 22,
                    spreadRadius: -4,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: LayoutBuilder(builder: (context, c) {
                final segW = c.maxWidth / n;
                // Indicator blob is a bit narrower than a full segment, centred
                // on the animated position.
                const blobW = 46.0;
                final blobLeft = segW * _pos + (segW - blobW) / 2;
                return Stack(children: [
                  // The one spring-driven sliding blob.
                  Positioned(
                    left: blobLeft,
                    top: (GlassBottomNav.barHeight - 40) / 2,
                    width: blobW,
                    height: 40,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.holoGradient,
                        borderRadius: BorderRadius.circular(LiquidGlass.radiusPill),
                        boxShadow: [
                          BoxShadow(color: AppColors.holoTeal.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4)),
                        ],
                      ),
                    ),
                  ),
                  Row(children: [
                    for (var i = 0; i < n; i++)
                      Expanded(child: _NavItem(
                        dest: widget.destinations[i],
                        // Icon lights up as the blob arrives (based on the live
                        // animated position, so passing items flash briefly).
                        selectedness: (1 - (_pos - i).abs()).clamp(0.0, 1.0),
                        selected: i == widget.currentIndex,
                        onTap: () => _handleTap(i),
                      )),
                  ]),
                ]);
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final BottomNavDest dest;
  final double selectedness; // 0..1 how close the blob is
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.dest, required this.selectedness, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = Color.lerp(AppColors.textSecondaryOf(context), Colors.white, selectedness)!;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: GlassBottomNav.barHeight,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // Icon bounces up slightly as it becomes selected.
          Transform.translate(
            offset: Offset(0, -2 * selectedness),
            child: Transform.scale(
              scale: 1 + 0.14 * selectedness,
              child: Icon(selected ? dest.activeIcon : dest.icon, size: 22, color: fg),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            dest.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textHeightBehavior: const TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false),
            style: TextStyle(
              color: fg,
              fontSize: 10,
              height: 1.0,
              fontWeight: selectedness > 0.5 ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ]),
      ),
    );
  }
}
