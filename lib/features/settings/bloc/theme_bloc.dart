import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../../../config/supabase_config.dart';
import '../../../config/theme/app_colors.dart';

// ── Events ──────────────────────────────────────────────────────────────────
abstract class ThemeEvent {}
class ToggleDark   extends ThemeEvent {}
class ToggleLight  extends ThemeEvent {}
class ToggleSystem extends ThemeEvent {}
class SetAccentColor extends ThemeEvent { final Color color; SetAccentColor(this.color); }
class _ThemeLoaded extends ThemeEvent { final ThemeMode mode; final Color accent; _ThemeLoaded(this.mode, this.accent); }

// ── State ────────────────────────────────────────────────────────────────────
class ThemeState {
  final ThemeMode mode;
  final Color accentColor;
  const ThemeState(this.mode, [this.accentColor = AppColors.blue]);
}

// ── Bloc ─────────────────────────────────────────────────────────────────────
// Accent color syncs to user_settings (DB) so it follows the user across
// devices/reinstalls, not just Hive on this one device — Hive is only the
// offline-first cache read before the network round trip resolves.
class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  static const _boxKey  = 'settings';
  static const _themeKey = 'theme_mode';
  static const _accentKey = 'accent_color';

  ThemeBloc() : super(const ThemeState(ThemeMode.dark)) {
    on<ToggleDark>  ((e, emit) { emit(ThemeState(ThemeMode.dark, state.accentColor));   _save(mode: 'dark'); });
    on<ToggleLight> ((e, emit) { emit(ThemeState(ThemeMode.light, state.accentColor));  _save(mode: 'light'); });
    on<ToggleSystem>((e, emit) { emit(ThemeState(ThemeMode.system, state.accentColor)); _save(mode: 'system'); });
    on<SetAccentColor>((e, emit) { emit(ThemeState(state.mode, e.color)); _save(accent: e.color); });
    on<_ThemeLoaded>((e, emit) => emit(ThemeState(e.mode, e.accent)));

    // Load saved preference via an event (avoids calling emit outside handler)
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final box   = await Hive.openBox(_boxKey);
    final saved = box.get(_themeKey, defaultValue: 'dark') as String;
    // TOLERANT ON PURPOSE, because nothing catches a throw here.
    //
    // _loadSaved() is fire-and-forget from the constructor, so an exception
    // does not surface as an error anywhere -- it just means the theme never
    // loads and the app sits on the default with nothing to explain why.
    //
    // Two ways the old line could throw on a value written by an EARLIER
    // build: `as String?` is a hard cast, so an accent stored as an int threw
    // a TypeError before parsing even began; and int.parse throws on anything
    // that is not clean hex. The remote read below was already wrapped in a
    // try/catch for exactly this reason -- the local one never was.
    var accent = parseAccent(box.get(_accentKey)) ?? AppColors.blue;

    final uid = SupabaseConfig.uid;
    if (uid != null) {
      try {
        final row = await SupabaseConfig.client.from('user_settings').select('accent_color').eq('profile_id', uid).maybeSingle();
        final hex = row?['accent_color'] as String?;
        accent = parseAccent(hex) ?? accent;
      } catch (_) {}
    }

    final mode = saved == 'light'  ? ThemeMode.light
               : saved == 'system' ? ThemeMode.system
               : ThemeMode.dark;
    add(_ThemeLoaded(mode, accent));
  }

  /// Public so the tolerance itself can be tested rather than a copy of it.
  ///
  /// Accepts every shape this value has ever been stored in: '#RRGGBB' from
  /// the `user_settings` row, 'AARRGGBB' from Hive, and a bare int from an
  /// older local write. Returns null for anything else rather than throwing,
  /// so a single unreadable preference costs the accent colour and nothing
  /// else.
  static Color? parseAccent(Object? raw) {
    if (raw is int) return Color(raw);
    if (raw is! String) return null;
    var hex = raw.trim().replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final value = int.tryParse(hex, radix: 16);
    return value == null ? null : Color(value);
  }

  Future<void> _save({String? mode, Color? accent}) async {
    final box = await Hive.openBox(_boxKey);
    if (mode != null) await box.put(_themeKey, mode);
    if (accent != null) {
      final hex = accent.toARGB32().toRadixString(16).padLeft(8, '0');
      await box.put(_accentKey, hex);
      final uid = SupabaseConfig.uid;
      if (uid != null) {
        final webHex = '#${hex.substring(2)}';
        try {
          await SupabaseConfig.client.from('user_settings').upsert({
            'profile_id': uid, 'accent_color': webHex, 'updated_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}
      }
    }
  }
}
