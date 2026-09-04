import '../../core/utils/validators.dart';

/// EVERY MEMBER OF THIS EXTENSION WAS BROKEN, ALL IN THE SAME WAY.
///
/// Someone escaped every `$` in this file at once — the signature of a bulk
/// find-and-replace, and the same accident the `AppValidators.required`
/// comment records ("Escaped '\$f' printed the literal text"). Dart read the
/// result two different ways, and neither was the intended one:
///
///  * In a NORMAL string, `\$` is an escaped dollar, so `capitalize` and
///    `initials` returned the literal characters
///    `${this[0].toUpperCase()}${substring(1)}` instead of interpolating.
///  * In a RAW string, `\$` is a backslash followed by a dollar, which the
///    regex engine reads as *a literal `$` character to match*. So both
///    `isValidEmail` and `isValidStudentId` demanded that the text end in a
///    dollar sign, and could never return true for any real input.
///
/// Nothing calls these today, which is the only reason it never surfaced —
/// `user.initials` elsewhere in the app is `UserModel.initials`, a different
/// member. Left in place and corrected rather than deleted, so the next person
/// who reaches for `'name'.capitalize` gets a working one.
extension StringExt on String {
  String get capitalize =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';

  /// First letters of the first two words, upper-cased; one letter if that is
  /// all there is; '?' for nothing usable.
  ///
  /// Filters empty parts before indexing. `'  Rakib   Hassan'.split(' ')`
  /// yields empty strings between the runs of spaces, and the original went
  /// straight to `p[0][0]` and `p[1][0]` — a RangeError on any name typed with
  /// a leading or double space.
  String get initials {
    final p = trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (p.isEmpty) return '?';
    if (p.length == 1) return p[0][0].toUpperCase();
    return '${p[0][0]}${p[1][0]}'.toUpperCase();
  }

  /// Both delegate to [AppValidators] rather than restating its rules. The
  /// student-ID rule in particular must exist in exactly one place: the copy
  /// that used to live here hard-coded a four-digit roll number, which is the
  /// assumption that stopped whole departments from registering.
  bool get isValidEmail => AppValidators.loginEmail(this) == null;
  bool get isValidStudentId => AppValidators.studentId(this) == null;
}
