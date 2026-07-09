/// Non-web fallback -- never actually called (bootstrap.dart only reaches
/// into this bridge behind a kIsWeb check), but keeps the conditional
/// export resolvable for Android/iOS/desktop compilation.
class OneSignalWebBridge {
  static Future<void> login(String externalId) async {}
  static Future<void> logout() async {}
  static Future<void> requestPermission() async {}
}
