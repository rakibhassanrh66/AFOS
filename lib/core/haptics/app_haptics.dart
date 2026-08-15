import 'dart:async';

import 'package:flutter/foundation.dart'
    show ValueNotifier, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Every haptic in the app goes through here.
///
/// WHY A WRAPPER. The audit found **3** `HapticFeedback` calls across 62
/// screens. Three. So the app is effectively silent to the hand, and the few
/// calls that exist answer to nothing — there is no way to turn them off, and
/// no shared rule about when they fire.
///
/// THE RULE THIS ENCODES — haptics fire on COMMIT, never on press.
///
/// A press already has a visual answer (the 0.97 scale). Buzzing on touch-down
/// as well means the phone reacts to being touched, which feels twitchy and,
/// worse, fires even when the user slides off to cancel — the device confirmed
/// something that never happened. Firing on release, only when the action
/// actually commits, is what makes a control feel like it has a mechanism
/// inside it.
///
/// The vocabulary is deliberately small. A haptic language with six textures is
/// noise; three that always mean the same thing is information:
///
///  * [selection] — a discrete choice landed (tab, chip, toggle, picker row).
///  * [success]   — something irreversible completed (submitted, approved).
///  * [warning]   — a destructive confirm, or an action that was refused.
///
/// PLATFORM. Web has no haptics API, so everything here is a no-op under
/// `kIsWeb` rather than an exception or a silent platform-channel failure.
class AppHaptics {
  AppHaptics._();

  /// User preference. A ValueNotifier so a settings screen can bind to it
  /// directly, mirroring `AppConfigService.instance.sosEnabled`.
  ///
  /// Defaults to on, and **persists** — see [load] and [setEnabled].
  ///
  /// Stored in SharedPreferences, deliberately NOT in `user_settings`. Whether
  /// this phone should buzz is a property of the phone, not of the account:
  /// the same user on a tablet with no vibration motor, or on web, wants a
  /// different answer. Keeping it local also means the preference costs no
  /// schema change and no network round trip on a code path that runs inside a
  /// gesture.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static const _prefsKey = 'haptics_enabled';

  /// Restore the stored preference. Call once during bootstrap; safe to call
  /// again. Failure to read is not an error worth surfacing — the default is
  /// on, which is the same thing a fresh install gets.
  static Future<void> load() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_prefsKey);
      if (stored != null) enabled.value = stored;
    } catch (_) {
      // Keep the default.
    }
  }

  /// Change the preference and persist it.
  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (_) {
      // The in-memory value still changed, so the app obeys immediately even
      // if the write failed; it simply will not survive a restart.
    }
  }

  static bool get _live => enabled.value && !kIsWeb;

  // ---------------------------------------------------------------- coalescing
  //
  // WHY THIS EXISTS. A single tap can legitimately reach this class twice: the
  // button primitive fires `selection` because a control was committed, and the
  // handler it invoked fires `success` because the thing actually succeeded.
  // Both are correct in isolation. Together they are a double buzz, which reads
  // as a stutter or a fault rather than as two pieces of information — the hand
  // cannot resolve two textures 10ms apart, it just feels wrong.
  //
  // So calls inside one window collapse to the STRONGEST. That lets the
  // primitives always speak, without every one of the ~90 call sites having to
  // know whether something upstream already did. Strength is meaning, not
  // amplitude: a refusal outranks a success, which outranks a selection,
  // because that is the order in which a user needs to be told.

  static const _coalesceWindow = Duration(milliseconds: 60);
  static Timer? _pending;
  static int _pendingRank = -1;

  /// selection/threshold = 0, success = 1, warning = 2.
  static void _fire(int rank, void Function() effect) {
    if (!_live) return;
    if (rank <= _pendingRank) return; // A stronger (or equal) one already won.
    _pendingRank = rank;
    _pending?.cancel();
    // Fire on a short trailing edge rather than immediately, so a stronger
    // haptic arriving a moment later in the same gesture can still replace it.
    _pending = Timer(_coalesceWindow, () {
      _pending = null;
      _pendingRank = -1;
      if (_live) effect();
    });
  }

  /// Cancel anything queued. For tests, and for a screen being torn down
  /// mid-gesture.
  @visibleForTesting
  static void reset() {
    _pending?.cancel();
    _pending = null;
    _pendingRank = -1;
  }

  /// A discrete choice landed. The workhorse — use this unless the action was
  /// destructive or genuinely final.
  static void selection() => _fire(0, HapticFeedback.selectionClick);

  /// An irreversible action completed successfully.
  ///
  /// Medium, not heavy: heavy impact for an ordinary save reads as an error,
  /// because weight is how the hand distinguishes "done" from "wrong".
  static void success() => _fire(1, HapticFeedback.mediumImpact);

  /// A destructive confirmation, or an action the app refused.
  static void warning() => _fire(2, HapticFeedback.heavyImpact);

  /// A drag crossed a threshold and the surface will snap if released now.
  /// Distinct from [selection] only in intent; kept separate so the sheet and
  /// slider code reads clearly and can be retuned independently.
  static void threshold() => _fire(0, HapticFeedback.selectionClick);
}
