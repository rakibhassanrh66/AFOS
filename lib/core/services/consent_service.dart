import 'package:shared_preferences/shared_preferences.dart';

/// Device-local record of the one-time data-notice acceptance shown before
/// first launch. Versioned so a future material change to what's disclosed
/// can re-prompt everyone by bumping the suffix, without needing a migration.
///
/// This is a disclosure notice, not a server-tracked legal consent record —
/// nothing here reaches Supabase, matching every other on-device-only
/// preference in this app (haptics, last route, biometric prompt flag).
class ConsentService {
  ConsentService._();
  static const _key = 'data_notice_accepted_v1';

  static Future<bool> hasAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}
