import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/features/schedule/data/repositories/schedule_repository.dart';
import 'package:afos_v7/features/schedule/presentation/widgets/semester_break_card.dart';

/// The semester-break state: what it says, and what it must never do.
///
/// The RULE itself (which term counts, and when a newer routine cancels the
/// break) lives in `ScheduleRepository.semesterBreak` and needs a live
/// database, so it is verified against the real table rather than mocked —
/// checked on 2026-09-01: CSE's published final term ends 2026-08-27, no
/// schedule_slots row is newer than that, so the break is active. What is
/// pinned here is the part that can regress silently: the labelling, and the
/// promise that the motivational line does not change on a rebuild.
void main() {
  group('SemesterBreak labelling', () {
    test('capitalises the season and keeps the year', () {
      final b = SemesterBreak(
          season: 'summer', year: 2026, endedOn: _aug27);
      expect(b.termLabel, 'Summer 2026');
    });

    test('a term with no season or year degrades to an empty label', () {
      // The card falls back to "Final exams are over" rather than printing a
      // stray year or a lone capital letter.
      final b = SemesterBreak(season: '', year: null, endedOn: _aug27);
      expect(b.termLabel, '');
    });

    test('a season with no year still reads properly', () {
      final b = SemesterBreak(season: 'spring', year: null, endedOn: _aug27);
      expect(b.termLabel, 'Spring');
    });
  });

  group('the motivational line', () {
    // The constitution forbids motion on rebuild, and the same reasoning
    // applies to copy: a message that changes on every scroll or keyboard
    // open reads as broken rather than as encouragement.
    test('is stable for a whole day', () {
      final morning = DateTime(2026, 9, 1, 8, 30);
      final evening = DateTime(2026, 9, 1, 23, 59);
      expect(SemesterBreakCard.lineFor(morning),
          SemesterBreakCard.lineFor(evening));
    });

    test('differs from one day to the next', () {
      expect(SemesterBreakCard.lineFor(DateTime(2026, 9, 1)),
          isNot(SemesterBreakCard.lineFor(DateTime(2026, 9, 2))));
    });

    test('never returns empty, for any day across a full year', () {
      for (var i = 0; i < 365; i++) {
        final d = DateTime(2026, 1, 1).add(Duration(days: i));
        expect(SemesterBreakCard.lineFor(d).trim(), isNotEmpty, reason: '$d');
      }
    });

    test('carries no emoji — the constitution bans it in UI copy', () {
      final emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]',
          unicode: true);
      for (var i = 0; i < 30; i++) {
        final line =
            SemesterBreakCard.lineFor(DateTime(2026, 1, 1).add(Duration(days: i)));
        expect(emoji.hasMatch(line), isFalse, reason: line);
      }
    });
  });

  group('daysSince', () {
    test('counts whole days from the last exam', () {
      final ended = DateTime.now().subtract(const Duration(days: 5));
      final b = SemesterBreak(season: 'summer', year: 2026, endedOn: ended);
      expect(b.daysSince, 5);
    });
  });
}

final _aug27 = DateTime(2026, 8, 27);
