import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import 'app_icon_painter.dart';

/// Standalone export — avoids flutter_test's RepaintBoundary.toImage(),
/// which hung indefinitely in this environment (timed out at 10 minutes
/// with no error, likely a headless-surface issue with the test harness).
/// Uses dart:ui directly: paint onto a PictureRecorder, rasterize, encode
/// PNG, write to disk, exit. Run with: flutter run -d windows -t tool/export_icon_main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const size = 1024.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  AfosIconPainter().paint(canvas, const Size(size, size));
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('assets/images/app_icon_source.png');
  await file.writeAsBytes(byteData!.buffer.asUint8List());
  // ignore: avoid_print
  print('WROTE_ICON_OK: ${await file.length()} bytes');
  exit(0);
}
