/// Pulls a 6-digit confirmation code out of whatever the user actually copied.
///
/// WHY THIS IS NOT JUST `RegExp(r'\d{6}')`. People do not select the code
/// cleanly. They copy the whole line out of the email, they copy the subject,
/// and — the case that matters most — when the code is displayed as six
/// separate boxes, a long-press selection comes back as `1 2 3 4 5 6` with the
/// separators between the cells baked in.
///
/// That last one decided the email design. A naive matcher forces the mail to
/// render the code as one unbroken string, because per-digit chips would
/// produce a paste that silently fails. Tolerating separators here removes the
/// constraint, so the message can look the way it should AND the paste works.
/// The parser is the right place for the tolerance: it is testable, and there
/// is exactly one of it.
///
/// WHAT IT DELIBERATELY WILL NOT DO is take six digits out of a longer number.
/// A student number or a phone number is not a confirmation code, and quietly
/// slicing one into the field produces a rejection the person cannot explain.
/// Hence the digit boundaries on both ends.
String? extractOtpCode(String? raw, {int length = 6}) {
  final text = raw ?? '';
  if (text.isEmpty) return null;

  // Separators tolerated BETWEEN digits: ordinary and non-breaking spaces,
  // tabs, newlines, and the hyphen/dash family — which covers "123-456" and
  // every per-digit layout a mail client can produce when its cells are
  // selected. Anything else ends the run.
  final pattern = RegExp(
    r'(?<![0-9])([0-9](?:[\s  -​\-‐-―]*[0-9]){'
    '${length - 1}'
    r'})(?![0-9])',
  );

  final match = pattern.firstMatch(text);
  if (match == null) return null;

  final digits = match.group(1)!.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length == length ? digits : null;
}
