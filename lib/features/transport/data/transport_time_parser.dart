import 'models/transport_schedule.dart';

/// The core of the transport-schedule fix: a tolerant time parser that turns
/// the messy real-world cells of the DIU transport sheet into normalized
/// [Trip]s. Pure + static so it can be unit-tested against every documented
/// variant.
///
/// Handles, from one cell:
///  * real Excel time values (fraction-of-day doubles) and typed time cells
///    (pass the h/m via [fromHourMinute]);
///  * "7:00 AM", "1:30 PM";
///  * "hh:mm:ss AM/PM" e.g. "11:15:00 AM";
///  * dot forms with a redundant seconds field, e.g. "4.20.00 PM" == 4:20 PM,
///    and "10.50 AM";
///  * a trailing parenthetical note on the same line or after a newline with
///    irregular spacing, e.g. "1:30 PM                    ( Students bus)" and
///    "10:00 AM ( Strat from Polashbari U Turn )" (note kept verbatim, typos
///    and all);
///  * a literal "Coming Soon" (any spacing/case) -> status comingSoon, no time;
///  * stray whitespace / non-breaking spaces / odd separators.
class TransportTimeParser {
  TransportTimeParser._();

  // A time token: 1-2 digit hour, ':' or '.' sep, 2 digit minute, optional
  // ':'/'.' + 2 digit seconds, optional AM/PM (spacing-tolerant, incl. NBSP).
  static final RegExp _timeRe = RegExp(
    r'(\d{1,2})\s*[:.]\s*(\d{2})(?:\s*[:.]\s*\d{2})?\s*([AaPp][.\s]*[Mm])?',
  );

  /// Split a raw cell into (timePart, note). The note is the last parenthetical
  /// group's inner text, trimmed; unmatched/rogue parens are tolerated.
  static (String, String?) _splitNote(String raw) {
    final open = raw.lastIndexOf('(');
    if (open == -1) return (raw, null);
    final close = raw.indexOf(')', open);
    final inner = (close == -1 ? raw.substring(open + 1) : raw.substring(open + 1, close)).trim();
    final without = (raw.substring(0, open) + (close == -1 ? '' : raw.substring(close + 1)));
    return (without, inner.isEmpty ? null : inner);
  }

  static String _clean(String s) => s
      .replaceAll(' ', ' ') // non-breaking space
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static bool _looksComingSoon(String s) {
    final t = s.toLowerCase();
    return t.contains('coming') && t.contains('soon');
  }

  /// Build a note from any free descriptive text ([residual]) plus an optional
  /// parenthetical ([paren]). A bare parenthetical keeps just its inner text
  /// (e.g. "(Students bus)" -> "Students bus"); descriptive text that precedes
  /// a parenthetical keeps BOTH so multi-part notes like
  /// "Will go upto Mirpur-1,10&Pallabi (Only 1 Bus Assigned For ECB)" aren't
  /// reduced to just the parenthetical.
  static String? _combineNote(String residual, String? paren) {
    final r = _clean(residual);
    if (r.isEmpty) return paren;
    if (paren == null || paren.isEmpty) return r;
    return '$r ($paren)';
  }

  /// Canonical display for an hour/minute (+ optional explicit meridiem).
  static String _display(int hour24Or12, int minute, {String? meridiem}) {
    int h = hour24Or12;
    String mer;
    if (meridiem != null) {
      mer = meridiem;
      if (h == 0) h = 12;
      if (h > 12) h -= 12; // e.g. a stray "13:00 PM"
    } else if (h >= 13 && h <= 23) {
      // 24h value with no meridiem -> derive.
      mer = 'PM';
      h -= 12;
    } else if (h == 12) {
      mer = 'PM';
    } else if (h == 0) {
      h = 12;
      mer = 'AM';
    } else {
      // 1..11 with no meridiem: default to AM (campus mornings), the least
      // surprising choice — most cells carry an explicit AM/PM anyway.
      mer = 'AM';
    }
    final mm = minute.toString().padLeft(2, '0');
    return '$h:$mm $mer';
  }

  /// Parse one raw cell string into a [Trip]. Returns an empty trip
  /// (`Trip.isEmpty`) for a blank cell so callers can skip it.
  static Trip parseTrip(String? raw) {
    if (raw == null) return const Trip();
    var s = _clean(raw);
    if (s.isEmpty) return const Trip();

    final (timePart0, paren) = _splitNote(s);
    final timePart = _clean(timePart0);

    if (_looksComingSoon(s)) {
      return Trip(time: null, note: paren, status: TripStatus.comingSoon);
    }

    final m = _timeRe.firstMatch(timePart);
    if (m == null) {
      // No time and not coming-soon. Keep the WHOLE descriptive text (outside
      // any parenthetical) plus the parenthetical, not just the parenthetical —
      // so a continuation line like "Will go upto ... (Only 1 Bus ...)" survives
      // intact for the column parser to merge into the trip above it.
      return Trip(time: null, note: _combineNote(timePart, paren));
    }
    final hour = int.parse(m.group(1)!);
    final minute = int.parse(m.group(2)!);
    final merRaw = m.group(3);
    String? meridiem;
    if (merRaw != null) {
      meridiem = merRaw.toLowerCase().contains('p') ? 'PM' : 'AM';
    }
    if (minute > 59 || hour > 23) {
      // Unparseable-as-time; treat as note-only so the QA step can flag it.
      return Trip(time: null, note: paren ?? raw.trim());
    }
    // Any descriptive text sitting beside the time (outside the parenthetical)
    // is part of the note too, e.g. "6:10 PM Will go upto ... (Only 1 Bus ...)".
    final residual = timePart.substring(0, m.start) + timePart.substring(m.end);
    return Trip(time: _display(hour, minute, meridiem: meridiem), note: _combineNote(residual, paren));
  }

  /// For a typed Excel time cell (hour/minute already known). Optionally pass
  /// a same-cell [note].
  static Trip fromHourMinute(int hour24, int minute, {String? note}) {
    if (hour24 < 0 || hour24 > 23 || minute < 0 || minute > 59) return const Trip();
    return Trip(time: _display(hour24, minute), note: note);
  }

  /// For a raw Excel serial time (fraction of a day in [0,1)).
  static Trip fromDayFraction(double frac, {String? note}) {
    if (frac.isNaN || frac < 0 || frac >= 1) return const Trip();
    final totalMin = (frac * 24 * 60).round();
    return fromHourMinute((totalMin ~/ 60) % 24, totalMin % 60, note: note);
  }

  /// Parse a whole Start/Departure cell that may stack several trips across
  /// sub-rows (separated by newlines) into a list of trips, dropping blanks.
  static List<Trip> parseTripColumn(String? raw) {
    if (raw == null) return const [];
    // Keep note-carrying newlines together with their time, but split distinct
    // stacked trips. A blank line or a run of times separates them; splitting
    // on newlines first is the reliable signal from the sheet's sub-rows.
    final lines = raw.split(RegExp(r'[\r\n]+'));
    final trips = <Trip>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      // A line with several time tokens (and no single attached note) is
      // several stacked trips flattened onto one line — split them. A line
      // with one time keeps its note via parseTrip.
      final matches = _timeRe.allMatches(_clean(line)).toList();
      if (matches.length > 1) {
        for (final m in matches) {
          final t = parseTrip(m.group(0));
          if (!t.isEmpty) trips.add(t);
        }
      } else {
        final t = parseTrip(line);
        if (t.isEmpty) continue;
        // A note-only line (no time, not coming-soon) is a continuation of the
        // trip above it — the sheet sometimes splits a time and its note onto
        // separate sub-rows (e.g. "6:10 PM" then "Will go upto ... (Only 1 Bus
        // ...)"). Merge it into the previous trip instead of leaving an orphan
        // time-less entry.
        if (t.time == null && t.status == TripStatus.scheduled && t.note != null && trips.isNotEmpty) {
          final prev = trips.removeLast();
          final merged = (prev.note == null || prev.note!.isEmpty) ? t.note : '${prev.note} ${t.note}';
          trips.add(Trip(time: prev.time, note: merged, status: prev.status));
          continue;
        }
        trips.add(t);
      }
    }
    return trips;
  }
}
