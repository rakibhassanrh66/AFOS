import 'package:intl/intl.dart';
class AppFormatters {
  AppFormatters._();

  /// EVERY displayed time goes through this first.
  ///
  /// Postgres `timestamptz` comes back over PostgREST as ISO-8601 with a zone
  /// (`...Z` / `+00:00`), and `DateTime.parse` faithfully returns a **UTC**
  /// DateTime for it. `DateFormat.format` then prints that UTC wall clock —
  /// so a message sent at 12:59 AM in Dhaka displayed as 6:59 PM, six hours
  /// out, which is exactly UTC+6. It was reported on chat, but every screen
  /// in the app that shows a server timestamp had it: notices, activity log,
  /// feedback, submissions, approvals.
  ///
  /// It also produced a WORSE symptom than being uniformly wrong. Chat draws
  /// an optimistic local echo of your own message the instant you send it,
  /// stamped `DateTime.now().toIso8601String()` — a naive local string with no
  /// zone, which parses back as LOCAL. So your message showed the right time
  /// until the server copy replaced it, then jumped six hours. Two rows in one
  /// conversation disagreed about what "now" meant.
  ///
  /// Fixing it in the formatters rather than at ~20 parse sites means a call
  /// site cannot forget. `toLocal()` on an already-local DateTime is a no-op,
  /// so the optimistic echo is unaffected and the two agree again.
  static DateTime _local(DateTime d) => d.isUtc ? d.toLocal() : d;

  static String date(DateTime d) => DateFormat('dd MMM yyyy').format(_local(d));
  static String dateTime(DateTime d) => DateFormat('dd MMM yyyy, hh:mm a').format(_local(d));
  static String time(DateTime d) => DateFormat('hh:mm a').format(_local(d));
  /// Formats a raw 24-hour "HH:MM" or "HH:MM:SS" string (as stored in a
  /// Postgres `time` column) as 12-hour "h:mm a", e.g. "13:00:00" -> "1:00 PM".
  static String time12(String hhmmss) {
    final parts = hhmmss.split(':');
    if (parts.length < 2) return hhmmss;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return hhmmss;
    return DateFormat('h:mm a').format(DateTime(2000, 1, 1, h, m));
  }
  /// A class time range, e.g. "8:00\u20138:35 AM". When both ends fall in the same
  /// half of the day \u2014 nearly every single class \u2014 the first meridiem is
  /// dropped, which keeps the range one character off the old raw 24-hour
  /// "08:00\u201308:35" it replaced. That matters: this string goes in a chip that
  /// already overflowed a 320dp card, so buying clarity with ~7 extra
  /// characters would have pushed the room number back behind an ellipsis.
  static String timeRange12(String startHhmm, String endHhmm) {
    final s = time12(startHhmm);
    final e = time12(endHhmm);
    if (s.length > 3 && e.length > 3 && s.contains(' ') && e.contains(' ')) {
      final sMeridiem = s.substring(s.length - 2);
      final eMeridiem = e.substring(e.length - 2);
      if (sMeridiem == eMeridiem) return '${s.substring(0, s.length - 3)}\u2013$e';
    }
    return '$s\u2013$e';
  }

  static String currency(double amount,{String symbol='\u09F3'}) =>
    '$symbol${amount.toStringAsFixed(2)}';
  static String greeting() {
    final h = DateTime.now().hour;
    if(h<12) return 'Good morning';
    if(h<17) return 'Good afternoon';
    return 'Good evening';
  }
  static String greetingEmoji() {
    final h = DateTime.now().hour;
    if(h<12) return '\u2600\uFE0F';
    if(h<17) return '\u26C5';
    return '\uD83C\uDF19';
  }
  static String dayName(DateTime d) => DateFormat('EEEE').format(_local(d));
  static String fullDate(DateTime d) => DateFormat('EEEE, dd MMMM yyyy').format(_local(d));
  static String relativeTime(DateTime d) {
    // `difference` compares absolute instants and was already correct across
    // zones — this is the one function here that never showed the bug. It
    // still normalises, because its `date(d)` fallback below is a wall clock
    // and would otherwise disagree with the "6h ago" that preceded it.
    final diff = DateTime.now().difference(d);
    if(diff.inMinutes<1) return 'Just now';
    if(diff.inMinutes<60) return '${diff.inMinutes}m ago';
    if(diff.inHours<24) return '${diff.inHours}h ago';
    if(diff.inDays<7) return '${diff.inDays}d ago';
    return date(d);
  }
}
