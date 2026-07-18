import 'package:flutter/material.dart';
import '../../config/theme/liquid_glass_tokens.dart';

/// The AFOS signature silhouette as a single [OutlinedBorder] — three corners
/// rounded at [radius], the top-right corner cut tight to [LiquidGlass.radiusCut].
///
/// Consolidating the shape into one [ShapeBorder] means a surface's FILL,
/// BORDER, and CLIP all come from the exact same path, so the 1px hairline can
/// never mis-nest against the clip (the "borders cross over at the edges"
/// artifact you get when a `Border.all` is drawn inside a separately-computed
/// `ClipRRect`). Use it via `ShapeDecoration(shape: SignatureBorder(...))` for
/// fill+border and `ClipPath(clipper: ShapeBorderClipper(shape: ...))` for the
/// backdrop clip, so every glass surface renders identically.
class SignatureBorder extends OutlinedBorder {
  final double radius;
  const SignatureBorder({this.radius = LiquidGlass.radiusCard, super.side = BorderSide.none});

  BorderRadius get _br => LiquidGlass.signatureRadius(radius);

  RRect _rrect(Rect rect, {double inset = 0}) {
    final br = _br;
    return RRect.fromRectAndCorners(
      inset == 0 ? rect : rect.deflate(inset),
      topLeft: br.topLeft, topRight: br.topRight,
      bottomLeft: br.bottomLeft, bottomRight: br.bottomRight,
    );
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_rrect(rect));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_rrect(rect, inset: side.width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    // Stroke sits fully inside the shape (aligned inside), so the outer edge of
    // the hairline coincides with the clip — no half-stroke gets clipped away.
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = side.color
      ..strokeWidth = side.width;
    canvas.drawRRect(_rrect(rect, inset: side.width / 2), paint);
  }

  @override
  OutlinedBorder copyWith({BorderSide? side, double? radius}) =>
      SignatureBorder(radius: radius ?? this.radius, side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => SignatureBorder(radius: radius * t, side: side.scale(t));
}
