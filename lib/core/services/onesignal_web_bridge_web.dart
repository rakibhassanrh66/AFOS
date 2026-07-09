import 'dart:js_interop';

@JS('afosOneSignalLogin')
external void _login(JSString externalId);

@JS('afosOneSignalLogout')
external void _logout();

@JS('afosOneSignalRequestPermission')
external void _requestPermission();

/// Calls the afosOneSignal* glue functions defined in web/index.html, which
/// queue onto OneSignal's own OneSignalDeferred Web SDK -- the
/// onesignal_flutter plugin has no web implementation to route through.
class OneSignalWebBridge {
  static Future<void> login(String externalId) async {
    _login(externalId.toJS);
  }

  static Future<void> logout() async {
    _logout();
  }

  static Future<void> requestPermission() async {
    _requestPermission();
  }
}
