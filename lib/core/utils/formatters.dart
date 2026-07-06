import 'package:intl/intl.dart';
class AppFormatters {
  AppFormatters._();
  static String date(DateTime d) => DateFormat('dd MMM yyyy').format(d);
  static String dateTime(DateTime d) => DateFormat('dd MMM yyyy, hh:mm a').format(d);
  static String time(DateTime d) => DateFormat('hh:mm a').format(d);
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
