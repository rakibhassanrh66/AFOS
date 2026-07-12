import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Reads a `blob:` URL (e.g. from record_web's AudioRecorder.stop(), or an
/// XFile.path on web) back into bytes via the browser's own fetch(), which
/// can resolve same-document blob: URLs directly -- there's no dart:io on
/// web to read them with otherwise.
Future<Uint8List> fetchBlobBytes(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}
