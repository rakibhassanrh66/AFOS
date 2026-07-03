import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/app_icon_painter.dart';

/// Not a real test — renders AfosIconPainter offscreen and writes it to
/// assets/images/app_icon_source.png as the launcher icon source.
/// Run with: flutter test test/app_icon_export_test.dart
void main() {
  testWidgets('export app icon PNG', (tester) async {
    const size = 1024.0;
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: SizedBox(
          width: size, height: size,
          child: CustomPaint(painter: AfosIconPainter(), size: const Size(size, size)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('assets/images/app_icon_source.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
  });
}
