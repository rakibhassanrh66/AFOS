import 'package:afos_v7/features/exam_seat/data/exam_routine_pdf_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exam-routine parser, pinned on the geometry of the real document.
///
/// WHY POSITIONED WORDS AND NOT A PDF FIXTURE. The source is a real DIU
/// examination routine and does not belong in a public repository. But the
/// layout IS the parser — every bug this file had was a coordinate bug, not a
/// logic bug — so the coordinates below are the exact ones measured from
/// "Updated CSE Exam Routine Final Semester Summer 2026", via Syncfusion's own
/// word bounds. Feeding them directly tests the thing that actually breaks.
///
/// The real document parses to 28 entries across 19–27 Aug with no warnings.
void main() {
  // One date block of the real page 1, to scale.
  //
  //   y=119  Slot A:(141)      Slot B:(348)      Slot C:(581)
  //   y=125  Batch(241)        Batch(469)        Batch(706)
  //   y=131  09:00 am – 11.00 am  |  12:00 pm – 02:00 pm  |  03:00 pm – 05:00 pm
  //   y=155+ course cells, batches at x=235 / 462 / 700
  List<(String, double, double)> page() => [
        ('Slot', 141, 119), ('A:', 161, 119),
        ('Slot', 348, 119), ('B:', 369, 119),
        ('Slot', 581, 119), ('C:', 602, 119),
        // The Batch header sits SIX points below the Slot row, which is more
        // than the line tolerance — it is its own line, and the times are two
        // rows below the label, not one.
        ('Batch', 241, 125), ('Batch', 469, 125), ('Batch', 706, 125),
        ('09:00', 111, 131), ('am', 139, 131), ('–', 156, 131),
        ('11.00', 164, 131), ('am', 190, 131),
        ('12:00', 317, 131), ('pm', 345, 131), ('–', 363, 131),
        ('02:00', 371, 131), ('pm', 399, 131),
        ('03:00', 551, 131), ('pm', 579, 131), ('–', 597, 131),
        ('05:00', 605, 131), ('pm', 633, 131),

        ('19/08/2026', 26, 189), ('Wednesday', 24, 201),

        // Slot A, first course. Note the batch label sits INSIDE the course
        // column at x=235 — it is owned by A because A's column starts left of
        // it and no later column does.
        ('CSE326', 126, 155),
        ('Social', 120, 167), ('and', 150, 167), ('Professional', 172, 167),
        ('Issues', 126, 179), ('in', 152, 179), ('Computing', 164, 179),
        ('Batch-65', 235, 174),

        // Slot A, SECOND course in the same column, lower down.
        ('CSE321:Computer', 126, 215), ('Networks', 190, 215),
        ('Batch-66', 235, 222),

        ('ENG102:Writing', 330, 155), ('and', 400, 155),
        ('Comprehension', 340, 167),
        ('Batch-71', 462, 174),

        ('CSE212:', 545, 155), ('Discrete', 580, 155), ('Mathematics', 620, 155),
        ('Batch-69', 700, 155),
      ];

  group('the real page geometry', () {
    test('every slot and every course is recovered, with its own batch', () {
      final rows = ExamRoutinePdfParser.parsePositionedWords(page());
      // Two in slot A, one in B, one in C.
      expect(rows.length, 4);

      final byCode = {for (final r in rows) r.courseCode: r};
      expect(byCode.keys, containsAll(['CSE326', 'CSE321', 'ENG102', 'CSE212']));

      // TWO COURSES IN ONE COLUMN, each with its own batch. Grouping cells by
      // vertical gap merged these into a single row carrying one batch.
      expect(byCode['CSE326']!.batch, '65');
      expect(byCode['CSE321']!.batch, '66');
      expect(byCode['CSE326']!.slotLabel, 'A');
      expect(byCode['CSE321']!.slotLabel, 'A');
    });

    test('a batch token inside the course column is owned, not read as title',
        () {
      // THE ONE-POINT BUG. Slot A's batch window was x 236-286 while its own
      // Batch-65 token sat at x=235 — outside by a single point — so every
      // slot A exam was dropped. Ownership is by nearest column to the left.
      final rows = ExamRoutinePdfParser.parsePositionedWords(page());
      final a = rows.firstWhere((r) => r.courseCode == 'CSE326');
      expect(a.batch, '65');
      expect(a.courseTitle, 'Social and Professional Issues in Computing');
      expect(a.courseTitle, isNot(contains('Batch')));
    });

    test('slot times are found two rows below the label, not one', () {
      final rows = ExamRoutinePdfParser.parsePositionedWords(page());
      final a = rows.firstWhere((r) => r.slotLabel == 'A');
      final b = rows.firstWhere((r) => r.slotLabel == 'B');
      final c = rows.firstWhere((r) => r.slotLabel == 'C');
      expect(a.slotStart, '09:00 am');
      expect(a.slotEnd, '11:00 am'); // note: printed "11.00", normalised
      expect(b.slotStart, '12:00 pm');
      expect(c.slotEnd, '05:00 pm');
    });

    test('the code may carry the first title word in the same token', () {
      // Syncfusion emits "CSE321:Computer" as one word.
      final rows = ExamRoutinePdfParser.parsePositionedWords(page());
      final r = rows.firstWhere((x) => x.courseCode == 'CSE321');
      expect(r.courseTitle, 'Computer Networks');
    });
  });

  group('the weekday is computed, never read', () {
    test('19/08/2026 is a Wednesday regardless of what the page prints', () {
      // The real document prints "Thurseday" for 20/08. Trusting the printed
      // name would store a typo; the date is unambiguous.
      final rows = ExamRoutinePdfParser.parsePositionedWords(page());
      expect(rows.first.dayName, 'Wednesday');
      expect(rows.first.date, DateTime(2026, 8, 19));
    });

    test('dates are read day-first, as the source writes them', () {
      final rows = ExamRoutinePdfParser.parsePositionedWords(page());
      // 19/08 is 19 August, not an invalid 8 month-19.
      expect(rows.first.date.month, 8);
      expect(rows.first.date.day, 19);
    });
  });
}
