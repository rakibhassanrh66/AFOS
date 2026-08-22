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

  /// The two bugs that cost the Summer 2026 final routine eight of its
  /// thirty-eight exams — found on 2026-08-22 by parsing the real file and
  /// comparing it against the seat-plan documents, which list the same exams
  /// independently. Neither produced a warning: a course that is never
  /// detected cannot be reported missing.
  group('a slot cell holding several courses', () {
    /// Page 2 of the real document, 23/08, slot A. Four electives share one
    /// cell, run together with slashes, and the credit markers ([520], [160])
    /// are glued to the codes exactly as Syncfusion emits them.
    List<(String, double, double)> crowdedCell() => [
          ('Slot', 141, 119), ('A:', 161, 119),
          ('Slot', 348, 119), ('B:', 369, 119),
          ('Batch', 241, 125), ('Batch', 469, 125),
          ('09:00', 111, 131), ('am', 139, 131), ('–', 156, 131),
          ('11.00', 164, 131), ('am', 190, 131),
          ('12:00', 317, 131), ('pm', 345, 131), ('–', 363, 131),
          ('02:00', 371, 131), ('pm', 399, 131),

          // Four codes, only the first at the start of its own token.
          ('CSE431:Machine', 100, 200), ('Learning', 179, 200),
          ('[520]', 99, 212), ('/CSE441:UI', 125, 212), ('and', 181, 212),
          ('UX', 199, 212),
          ('Design', 109, 224), ('[160]/CSE453:', 142, 224),
          ('Wireless', 93, 237), ('Sensor', 133, 237), ('Network', 165, 237),
          ('[50]', 205, 237),
          ('/CSE471:Introduction', 104, 249), ('to', 201, 249),
          ('Batch-64', 235, 230),

          ('AOL101:', 315, 224), ('Art', 358, 224), ('of', 375, 224),
          ('Living', 387, 224),
          ('Batch-68', 462, 212),

          // The date label sits BELOW its own first courses and above its
          // last — it is centred in the row, which is the second bug.
          ('23/08/2026', 26, 251),
          ('CSE121:', 98, 293), ('Electrical', 140, 293), ('Circuits', 190, 293),
          ('Batch-70', 235, 285),
          ('CSE313:', 308, 293), ('Compiler', 350, 293), ('Design', 400, 293),
          ('Batch-67', 462, 286),
        ];

    test('every course in the cell is recovered, not just the first', () {
      // Requiring the code to START its token accepted "CSE431:Machine" and
      // silently dropped "/CSE441:UI", "[160]/CSE453:" and
      // "/CSE471:Introduction".
      final rows = ExamRoutinePdfParser.parsePositionedWords(crowdedCell());
      final codes = rows.map((r) => r.courseCode).toSet();
      expect(codes, containsAll(['CSE431', 'CSE441', 'CSE453', 'CSE471']));
    });

    test('each one takes the batch of its own cell, not of its neighbour', () {
      final rows = ExamRoutinePdfParser.parsePositionedWords(crowdedCell());
      final byCode = {for (final r in rows) r.courseCode: r};
      for (final c in ['CSE431', 'CSE441', 'CSE453', 'CSE471']) {
        expect(byCode[c]!.batch, '64', reason: '$c took the wrong batch');
      }
      // The neighbouring column is untouched by the split.
      expect(byCode['AOL101']!.batch, '68');
      expect(byCode['AOL101']!.slotLabel, 'B');
    });

    test('a credit marker glued to the code is not read as the title', () {
      final rows = ExamRoutinePdfParser.parsePositionedWords(crowdedCell());
      final byCode = {for (final r in rows) r.courseCode: r};
      expect(byCode['CSE453']!.courseTitle, 'Wireless Sensor Network');
      expect(byCode['CSE441']!.courseTitle, isNot(contains('520')));
      expect(byCode['CSE441']!.courseTitle, isNot(contains('CSE453')));
    });
  });

  group('the date label is centred in its row, not at the top of it', () {
    /// Two consecutive days. Each label sits between its own courses: 23/08 at
    /// y=251 owns courses at y=200 AND y=293; 24/08 at y=392 owns y=350 and
    /// y=420. Slicing at the label would give 23/08 only the courses beneath
    /// it and hand the ones above to the previous day.
    List<(String, double, double)> twoDays() => [
          ('Slot', 141, 119), ('A:', 161, 119),
          ('Batch', 241, 125),
          ('09:00', 111, 131), ('am', 139, 131), ('–', 156, 131),
          ('11.00', 164, 131), ('am', 190, 131),

          ('CSE431:Machine', 100, 200), ('Learning', 179, 200),
          ('Batch-64', 235, 200),
          ('23/08/2026', 26, 251),
          ('CSE121:', 98, 293), ('Electrical', 140, 293),
          ('Batch-70', 235, 293),

          ('CSE411:Computer', 95, 350), ('Graphics', 180, 350),
          ('Batch-65', 235, 350),
          ('24/08/2026', 26, 392),
          ('ENG101:Basic', 98, 420), ('English', 160, 420),
          ('Batch-72', 235, 420),
        ];

    test('a day owns the courses above its label as well as below', () {
      final rows = ExamRoutinePdfParser.parsePositionedWords(twoDays());
      final on23 = rows.where((r) => r.date == DateTime(2026, 8, 23));
      expect(on23.map((r) => r.courseCode).toSet(), {'CSE431', 'CSE121'});
    });

    test('the next day does not steal them', () {
      final rows = ExamRoutinePdfParser.parsePositionedWords(twoDays());
      final on24 = rows.where((r) => r.date == DateTime(2026, 8, 24));
      expect(on24.map((r) => r.courseCode).toSet(), {'CSE411', 'ENG101'});
      // The batch travels with the course, not with the block boundary.
      final byCode = {for (final r in rows) r.courseCode: r};
      expect(byCode['CSE431']!.batch, '64');
      expect(byCode['CSE121']!.batch, '70');
      expect(byCode['CSE411']!.batch, '65');
      expect(byCode['ENG101']!.batch, '72');
    });

    test('nothing is lost or duplicated across the boundary', () {
      final rows = ExamRoutinePdfParser.parsePositionedWords(twoDays());
      expect(rows.length, 4);
    });
  });
}
