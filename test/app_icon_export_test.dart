import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/app_icon_painter.dart';

/// Not a real test — a generator. Renders [AfosIconPainter] offscreen and
/// writes assets/images/app_icon_source.png, the source image flutter_launcher_
/// icons rasterises the launcher icon from.
///
/// SKIPPED by default, for two reasons: it writes into the working tree, which
/// no ordinary `flutter test` run should do; and it needs the real async zone
/// (see below), which makes it far slower than every other test here.
///
/// Regenerate the icon with:
///   flutter test --run-skipped test/app_icon_export_test.dart
void main() {
  testWidgets('export app icon PNG', (tester) async {
    const size = 1024.0;

    // The default 800x600 test surface would give the SizedBox below tight
    // constraints and silently clamp it, exporting a 800x600 icon instead of a
    // square 1024. Size the surface to the icon and reset it afterwards.
    tester.view.physicalSize = const Size(size, size);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

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

    // runAsync is REQUIRED here. testWidgets runs its body in a fake-async zone
    // where timers and microtasks are driven by pump(), but RenderRepaintBoundary
    // .toImage() completes off the engine's real raster thread — a callback the
    // fake zone never delivers. Awaiting it directly simply hangs until the test
    // times out, which is exactly what this file did for ten minutes on every
    // full-suite run while leaving app_icon_source.png empty (0 bytes, as
    // committed). runAsync hands the body back to the real event loop so the
    // raster completion can actually arrive.
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      try {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('assets/images/app_icon_source.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }, skip: true);
}
