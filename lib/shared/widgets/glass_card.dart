import 'dart:ui';
import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';

/// Premium holographic glass surface: frosted blur + animated gradient edge
/// + soft glow bloom. This is the app's signature surface — reused
/// everywhere instead of plain Containers/Cards.
class GlassCard extends StatefulWidget {
  final Widget child;
  final double borderRadius;
  final Color? glowColor;
  final bool animated;
  final EdgeInsetsGeometry? padding;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.glowColor,
    this.animated = true,
    this.padding,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.animated) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 6),
      )..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final glow = widget.glowColor ?? AppColors.holoBlue;
    final radius = BorderRadius.circular(widget.borderRadius);

    Widget buildGlass(double t) {
      final gradient = SweepGradient(
        transform: GradientRotation(t * 6.283185307),
        colors: [
          glow.withOpacity(0.55),
          AppColors.holoviolet.withOpacity(0.35),
          AppColors.holoTeal.withOpacity(0.35),
          glow.withOpacity(0.55),
        ],
      );

      return Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: glow.withOpacity(0.16),
              blurRadius: 24,
              spreadRadius: -4,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.all(1.2),
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: gradient,
              ),
              child: Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: AppColors.glassFill(context),
                  borderRadius: BorderRadius.circular(widget.borderRadius - 1),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      );
    }

    if (_controller == null) return buildGlass(0);

    return AnimatedBuilder(
      animation: _controller!,
      builder: (context, _) => buildGlass(_controller!.value),
    );
  }
}
