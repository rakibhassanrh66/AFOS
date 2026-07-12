import 'package:intl/intl.dart';
class AppFormatters {
  AppFormatters._();
  static String date(DateTime d) => DateFormat('dd MMM yyyy').format(d);
  static String dateTime(DateTime d) => DateFormat('dd MMM yyyy, hh:mm a').format(d);
  static String time(DateTime d) => DateFormat('hh:mm a').format(d);
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
  static String dayName(DateTime d) => DateFormat('EEEE').format(d);
  static String fullDate(DateTime d) => DateFormat('EEEE, dd MMMM yyyy').format(d);
  static String relativeTime(DateTime d) {
    final diff = DateTime.now().difference(d);
    if(diff.inMinutes<1) return 'Just now';
    if(diff.inMinutes<60) return '${diff.inMinutes}m ago';
    if(diff.inHours<24) return '${diff.inHours}h ago';
    if(diff.inDays<7) return '${diff.inDays}d ago';
    return date(d);
  }
}
