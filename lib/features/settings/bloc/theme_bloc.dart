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
    final savedAccent = box.get(_accentKey) as String?;
    var accent = savedAccent != null ? Color(int.parse(savedAccent, radix: 16)) : AppColors.blue;

    final uid = SupabaseConfig.uid;
    if (uid != null) {
      try {
        final row = await SupabaseConfig.client.from('user_settings').select('accent_color').eq('profile_id', uid).maybeSingle();
        final hex = row?['accent_color'] as String?;
        if (hex != null) accent = Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
      } catch (_) {}
    }

    final mode = saved == 'light'  ? ThemeMode.light
               : saved == 'system' ? ThemeMode.system
               : ThemeMode.dark;
    add(_ThemeLoaded(mode, accent));
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
