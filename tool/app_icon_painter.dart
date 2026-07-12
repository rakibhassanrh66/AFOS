import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Sci-fi AFOS launcher icon: a navy hex-badge with a glowing circuit
/// frame around a faceted "A" monogram, referencing the VR-ID smart
/// identity concept. Rendered offscreen by test/app_icon_export_test.dart
/// and exported to assets/images/app_icon_source.png.
class AfosIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final center = Offset(w / 2, h / 2);
    final r = w / 2;

    // Background: deep navy radial glow.
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF0D1E3A), Color(0xFF060D1F)],
        radius: 0.9,
      ).createShader(Rect.fromCircle(center: center, radius: r));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    // Outer hexagon frame (electric blue, glowing).
    final hexPath = _hexPath(center, r * 0.92);
    final glow = Paint()
      ..color = const Color(0xFF1E6FFF).withOpacity(0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.028
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    canvas.drawPath(hexPath, glow);
    final hexStroke = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF5294FF), Color(0xFF1E6FFF)],
      ).createShader(Rect.fromCircle(center: center, radius: r))
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.014;
    canvas.drawPath(hexPath, hexStroke);

    // Inner hexagon (thin, faint) for a circuit-board layered look.
    final innerHex = _hexPath(center, r * 0.78);
    final innerStroke = Paint()
      ..color = const Color(0xFF5294FF).withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.006;
    canvas.drawPath(innerHex, innerStroke);

    // Circuit corner nodes + traces at each hex vertex.
    final verts = _hexVertices(center, r * 0.92);
    final nodePaint = Paint()..color = const Color(0xFFFFD700);
    final tracePaint = Paint()
      ..color = const Color(0xFFFFD700).withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.01;
    for (final v in verts) {
      final dir = (v - center);
      final outer = center + dir * 1.0;
      final tip = center + dir * 1.12;
      canvas.drawLine(outer, tip, tracePaint);
      canvas.drawCircle(tip, w * 0.016, nodePaint);
    }

    // Faceted "A" monogram, gold-gradient fill.
    final aPath = _monogramA(center, r * 0.62);
    final aPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Color(0xFFFFE873), Color(0xFFFFD700), Color(0xFFFF9D00)],
      ).createShader(Rect.fromCircle(center: center, radius: r * 0.62));
    canvas.drawPath(aPath, aPaint);
    final aStroke = Paint()
      ..color = const Color(0xFF060D1F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.008;
    canvas.drawPath(aPath, aStroke);

    // Scan-line accent through the A crossbar (VR-ID motif).
    final scanPaint = Paint()
      ..color = const Color(0xFF00D084)
      ..strokeWidth = w * 0.012
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(center.dx - r * 0.32, center.dy + r * 0.06),
      Offset(center.dx + r * 0.32, center.dy + r * 0.06),
      scanPaint,
    );
  }

  Path _hexPath(Offset center, double radius) {
    final path = Path();
    final verts = _hexVertices(center, radius);
    path.moveTo(verts[0].dx, verts[0].dy);
    for (final v in verts.skip(1)) {
      path.lineTo(v.dx, v.dy);
    }
    path.close();
    return path;
  }

  List<Offset> _hexVertices(Offset center, double radius) {
    return List.generate(6, (i) {
      final angle = (math.pi / 180) * (60 * i - 90);
      return Offset(center.dx + radius * math.cos(angle),
          center.dy + radius * math.sin(angle));
    });
  }

  /// A bold, faceted "A" silhouette — a cut-gem peak over a wide base.
  /// Kept as a single solid triangle (no internal aperture) so it stays
  /// legible at small launcher sizes; the crossbar reads via the
  /// separate gold scan-line drawn across it in paint().
  Path _monogramA(Offset center, double size) {
    final bevelL = Offset(center.dx - size * 0.16, center.dy - size * 0.78);
    final bevelR = Offset(center.dx + size * 0.16, center.dy - size * 0.78);
    final footOuterL = Offset(center.dx - size * 0.82, center.dy + size);
    final footInnerL = Offset(center.dx - size * 0.58, center.dy + size);
    final footOuterR = Offset(center.dx + size * 0.82, center.dy + size);
    final footInnerR = Offset(center.dx + size * 0.58, center.dy + size);
    final waistL = Offset(center.dx - size * 0.10, center.dy + size * 0.12);
    final waistR = Offset(center.dx + size * 0.10, center.dy + size * 0.12);

    return Path()
      ..moveTo(bevelL.dx, bevelL.dy)
      ..lineTo(bevelR.dx, bevelR.dy)
      ..lineTo(footOuterR.dx, footOuterR.dy)
      ..lineTo(footInnerR.dx, footInnerR.dy)
      ..lineTo(waistR.dx, waistR.dy)
      ..lineTo(waistL.dx, waistL.dy)
      ..lineTo(footInnerL.dx, footInnerL.dy)
      ..lineTo(footOuterL.dx, footOuterL.dy)
      ..close();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
