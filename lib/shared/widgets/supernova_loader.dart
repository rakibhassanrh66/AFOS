import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../config/theme/app_colors.dart';

/// The app's single branded loading animation — a glossy rotating/pulsing
/// starburst used everywhere a plain spinner used to sit (buttons, uploads,
/// dialogs, page waits). When [color] is null it renders in the brand
/// teal→blue duo so the loader is unmistakably AFOS; pass a [color] to tint it
/// (e.g. onto a colored button).
class SupernovaLoader extends StatefulWidget {
  final double size;
  final Color? color;
  const SupernovaLoader({super.key, this.size = 22, this.color});

  @override
  State<SupernovaLoader> createState() => _SupernovaLoaderState();
}

class _SupernovaLoaderState extends State<SupernovaLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size, height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) => CustomPaint(
            painter: _SupernovaPainter(t: _ctrl.value, color: widget.color),
          ),
        ),
      ),
    );
  }
}

class _SupernovaPainter extends CustomPainter {
  final double t;
  final Color? color;
  _SupernovaPainter({required this.t, this.color});

  // Brand duo — rays cycle across these when no explicit color is given.
  static const _brandA = AppColors.green;     // teal
  static const _brandB = AppColors.blueLight; // blue

  Color _rayColor(int i, int count) {
    if (color != null) return color!;
    final f = (i / count + t) % 1.0;
    return Color.lerp(_brandA, _brandB, (math.sin(f * math.pi * 2) + 1) / 2)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final pulse = 0.75 + 0.25 * math.sin(t * 2 * math.pi);
    final core = color ?? _brandA;

    // Glossy glowing core with a highlight.
    canvas.drawCircle(
      center,
      radius * 0.34 * pulse,
      Paint()
        ..color = core.withValues(alpha: 0.9)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      center.translate(-radius * 0.08, -radius * 0.08),
      radius * 0.12 * pulse,
      Paint()..color = Colors.white.withValues(alpha: 0.55),
    );

    // Rotating rays.
    const rayCount = 8;
    final rayPaint = Paint()
      ..strokeWidth = radius * 0.14
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < rayCount; i++) {
      final angle = (i / rayCount) * 2 * math.pi + t * 2 * math.pi;
      final rayLen = radius * (0.55 + 0.35 * ((i.isEven) ? pulse : (1 - pulse * 0.4)));
      final opacity = 0.35 + 0.65 * ((math.sin(angle + t * 4 * math.pi) + 1) / 2);
      rayPaint.color = _rayColor(i, rayCount).withValues(alpha: opacity.clamp(0.2, 1.0));
      final start = center + Offset(math.cos(angle), math.sin(angle)) * radius * 0.3;
      final end = center + Offset(math.cos(angle), math.sin(angle)) * rayLen;
      canvas.drawLine(start, end, rayPaint);
    }

    // Outer orbit ring.
    canvas.drawCircle(
      center,
      radius * 0.92,
      Paint()
        ..color = (color ?? _brandB).withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _SupernovaPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}

/// Larger full-screen-friendly version with a label, used on upload/parse
/// screens where the wait is longer and deserves more presence than an
/// inline button spinner.
class SupernovaBusy extends StatelessWidget {
  final String label;
  const SupernovaBusy({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SupernovaLoader(size: 64),
      const SizedBox(height: 16),
      Text(label, style: TextStyle(color: AppColors.textSecondaryOf(context), fontSize: 13, fontWeight: FontWeight.w600)),
    ]);
  }
}
