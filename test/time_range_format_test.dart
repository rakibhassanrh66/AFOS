import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/core/utils/formatters.dart';

/// Locks the class-time format. Several screens rendered the raw 24-hour
/// value straight out of Postgres — "08:00–08:35" on the offering card,
/// "14:00:00–15:00:00" (seconds included) on the conference-room screens —
/// while the time pickers that produced them show 12-hour. The same meeting
/// therefore read differently depending on which screen you were looking at.
///
/// The width behaviour is the load-bearing part: this string goes into a chip
/// that has already overflowed a 320dp card once, hiding the room number
/// behind an ellipsis. Collapsing a same-meridiem range keeps it within one
/// character of the 24-hour form it replaced, so the fix cannot reintroduce
/// that overflow.
void main() {
  group('time12', () {
    test('drops seconds and converts to 12-hour', () {
      expect(AppFormatters.time12('08:00:00'), '8:00 AM');
      expect(AppFormatters.time12('13:00:00'), '1:00 PM');
      expect(AppFormatters.time12('00:30'), '12:30 AM');
      expect(AppFormatters.time12('12:05'), '12:05 PM');
    });

    test('passes malformed input through untouched rather than throwing', () {
      expect(AppFormatters.time12('not-a-time'), 'not-a-time');
      expect(AppFormatters.time12(''), '');
    });
  });

  group('timeRange12', () {
    test('collapses the meridiem when both ends share it', () {
      expect(AppFormatters.timeRange12('08:00:00', '08:35:00'), '8:00–8:35 AM');
      expect(AppFormatters.timeRange12('13:00', '14:30'), '1:00–2:30 PM');
    });

    test('keeps both when the range crosses midday', () {
      expect(AppFormatters.timeRange12('11:30', '13:00'), '11:30 AM–1:00 PM');
    });

    test('stays within one character of the raw 24-hour form it replaced', () {
      // "08:00–08:35" is 11 chars; the chip on a 320dp card has no room for
      // the ~7 extra a naive "8:00 AM–8:35 AM" would cost.
      const raw = '08:00–08:35';
      final formatted = AppFormatters.timeRange12('08:00:00', '08:35:00');
      expect(formatted.length, lessThanOrEqualTo(raw.length + 1),
          reason: 'a longer range would push the room number behind an ellipsis');
    });

    test('degrades safely on malformed input', () {
      expect(AppFormatters.timeRange12('junk', 'junk'), 'junk–junk');
    });
  });
}
