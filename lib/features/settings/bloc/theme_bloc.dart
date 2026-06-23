import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ── Events ──────────────────────────────────────────────────────────────────
abstract class ThemeEvent {}
class ToggleDark   extends ThemeEvent {}
class ToggleLight  extends ThemeEvent {}
class ToggleSystem extends ThemeEvent {}
class _ThemeLoaded extends ThemeEvent { final ThemeMode mode; _ThemeLoaded(this.mode); }

// ── State ────────────────────────────────────────────────────────────────────
class ThemeState {
  final ThemeMode mode;
  const ThemeState(this.mode);
}

// ── Bloc ─────────────────────────────────────────────────────────────────────
class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  static const _boxKey  = 'settings';
  static const _themeKey = 'theme_mode';

  ThemeBloc() : super(const ThemeState(ThemeMode.dark)) {
    on<ToggleDark>  ((e, emit) { emit(const ThemeState(ThemeMode.dark));   _save('dark'); });
    on<ToggleLight> ((e, emit) { emit(const ThemeState(ThemeMode.light));  _save('light'); });
    on<ToggleSystem>((e, emit) { emit(const ThemeState(ThemeMode.system)); _save('system'); });
    on<_ThemeLoaded>((e, emit) => emit(ThemeState(e.mode)));

    // Load saved preference via an event (avoids calling emit outside handler)
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final box   = await Hive.openBox(_boxKey);
    final saved = box.get(_themeKey, defaultValue: 'dark') as String;
    final mode  = saved == 'light'  ? ThemeMode.light
                : saved == 'system' ? ThemeMode.system
                : ThemeMode.dark;
    add(_ThemeLoaded(mode));
  }

  Future<void> _save(String v) async {
    final box = await Hive.openBox(_boxKey);
    await box.put(_themeKey, v);
  }
}
