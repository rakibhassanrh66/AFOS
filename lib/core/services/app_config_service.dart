import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/supabase_config.dart';

/// App-wide config flags (currently just the SOS visibility gate), cached in a
/// [ValueNotifier] and kept live via a realtime subscription so a super-admin
/// flipping the toggle reflects on every device immediately. RLS remains the
/// authority — this only drives what the UI shows.
class AppConfigService {
  AppConfigService._();
  static final AppConfigService instance = AppConfigService._();

  /// Whether the campus-emergency SOS feature is switched ON for general users.
  /// Default false (hidden) until proven otherwise, so a load failure fails
  /// closed rather than exposing SOS to everyone.
  final ValueNotifier<bool> sosEnabled = ValueNotifier<bool>(false);

  RealtimeChannel? _channel;
  bool _started = false;

  /// Idempotent — safe to call from every shell mount; only the first call
  /// actually loads + subscribes (needs an authenticated session, so this is
  /// driven from the authenticated shell, not cold bootstrap).
  Future<void> ensureInit() async {
    if (_started) return;
    _started = true;
    await _load();
    _subscribe();
  }

  Future<void> _load() async {
    try {
      final row = await SupabaseConfig.client
          .from('app_config').select('sos_enabled').eq('id', 1).maybeSingle();
      sosEnabled.value = (row?['sos_enabled'] as bool?) ?? false;
    } catch (e) {
      debugPrint('[AppConfigService] load failed (keeping SOS hidden): $e');
    }
  }

  void _subscribe() {
    _channel?.unsubscribe();
    _channel = SupabaseConfig.client
        .channel('app_config_changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_config',
          callback: (payload) {
            final v = payload.newRecord['sos_enabled'] as bool?;
            if (v != null) sosEnabled.value = v;
          },
        )
        .subscribe();
  }

  /// Super-admin only (enforced by RLS). Optimistically updates the local
  /// notifier; the realtime echo confirms/corrects it.
  Future<void> setSosEnabled(bool value) async {
    await SupabaseConfig.client.from('app_config').update({
      'sos_enabled': value,
      'updated_at': DateTime.now().toIso8601String(),
      'updated_by': SupabaseConfig.uid,
    }).eq('id', 1);
    sosEnabled.value = value;
  }

  /// Cleared on logout so a signed-out session can't leak the last value.
  void reset() {
    _channel?.unsubscribe();
    _channel = null;
    _started = false;
    sosEnabled.value = false;
  }
}
