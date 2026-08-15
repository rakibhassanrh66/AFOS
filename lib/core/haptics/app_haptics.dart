import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:flutter/services.dart';

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
  /// Defaults to on. Persisting this is deliberately NOT done here — writing
  /// to the settings store would mean touching a repository, which is outside
  /// the Phase 1 token-layer scope. A later phase binds this notifier to
  /// `user_settings`; until then it is per-session, which is honest and
  /// harmless.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);

  static bool get _live => enabled.value && !kIsWeb;

  /// A discrete choice landed. The workhorse — use this unless the action was
  /// destructive or genuinely final.
  static void selection() {
    if (_live) HapticFeedback.selectionClick();
  }

  /// An irreversible action completed successfully.
  ///
  /// Medium, not heavy: heavy impact for an ordinary save reads as an error,
  /// because weight is how the hand distinguishes "done" from "wrong".
  static void success() {
    if (_live) HapticFeedback.mediumImpact();
  }

  /// A destructive confirmation, or an action the app refused.
  static void warning() {
    if (_live) HapticFeedback.heavyImpact();
  }

  /// A drag crossed a threshold and the surface will snap if released now.
  /// Distinct from [selection] only in intent; kept separate so the sheet and
  /// slider code reads clearly and can be retuned independently.
  static void threshold() {
    if (_live) HapticFeedback.selectionClick();
  }
}
