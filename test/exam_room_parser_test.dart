import 'package:afos_v7/features/exam_seat/data/exam_room_pdf_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seat-plan parser, pinned on the geometry of the real documents.
///
/// Coordinates are the exact ones Syncfusion reports for the Summer 2026
/// finals "Seat Details" files. Three defects are pinned here, all found on
/// 2026-08-22 by running the parser over the real PDFs rather than by
/// reasoning about them:
///
///  1. the course context did not survive a page break, so 57% of every file
///     was stored with `course_code = null` — and a null course code joins to
///     no exam, making those rooms invisible to the screen they exist for;
///  2. the date arrives as five tokens in one of the two templates
///     ("19", "-", "08", "-", "2026"), which produced a null date, and a null
///     date drops every row on the page. One whole file parsed to zero rows;
///  3. the room number arrives as three tokens ("G1", "-", "001") in that same
///     template, so the seat count landed on "-" and the row was dropped.
void main() {
  /// The title and Date rows every page of these documents repeats. The
  /// parser calibrates reading direction from their relative position, so a
  /// fixture without them is not testing the real thing.
  List<(String, double, double)> pageHead({String slot = 'A'}) => [
        ('Final', 172, 32), ('Examination,', 216, 32), ('Summer', 313, 32),
        ('-', 373, 32), ('2026', 378, 32),
        // FIVE tokens, as the real file emits them.
        ('Date:', 124, 52), ('19', 166, 52), ('-', 183, 52), ('08', 188, 52),
        ('-', 204, 52), ('2026', 209, 52),
        ('Slot:', 264, 52), (slot, 301, 52), ('(09:00', 316, 52),
        ('AM', 364, 52), ('-', 391, 52), ('11:00', 400, 52), ('AM)', 443, 52),
        ('Total', 237, 71), ('Seat(s):', 277, 71), ('1557', 336, 71),
        // The "Dept." template, not the "Faculty" one.
        ('Dept.', 35, 117), ('ID', 108, 117), ('Course', 185, 117),
        ('Title', 230, 117), ('Tech.', 286, 117), ('Int.', 321, 117),
        ('Section', 347, 117), ('Room', 399, 117), ('No', 436, 117),
        ('Seat(s)', 462, 117), ('Total', 525, 117),
      ];

  /// A full new-course row: Dept | Code | Title… | Initial | Section | Room…
  List<(String, double, double)> courseRow(double y) => [
        ('CSE', 32, y), ('CSE321', 74, y), ('Computer', 159, y),
        ('Networks', 206, y), ('FNN', 287, y), ('66_A', 343, y),
        ('G1', 400, y), ('-', 413, y), ('001', 417, y), ('14', 457, y),
        ('51', 513, y),
      ];

  group('split tokens', () {
    test('a date drawn as five tokens is still read', () {
      // The whole 19 Aug file parsed to ZERO rows because of this: the regex
      // was matched against the token after "Date:", which is "19".
      final rows = ExamRoomPdfParser.parsePositionedPages([
        [...pageHead(), ...courseRow(138)],
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.examDate, DateTime(2026, 8, 19));
    });

    test('a room drawn as three tokens is rejoined, not truncated', () {
      final rows = ExamRoomPdfParser.parsePositionedPages([
        [...pageHead(), ...courseRow(138)],
      ]);
      expect(rows.single.roomNo, 'G1-001');
      // int.tryParse used to land on "-" and drop the row entirely.
      expect(rows.single.seats, 14);
    });

    test('a room that is already one token is left alone', () {
      final rows = ExamRoomPdfParser.parsePositionedPages([
        [
          ...pageHead(),
          ('CSE', 32, 138), ('CSE321', 74, 138), ('Computer', 159, 138),
          ('FNN', 287, 138), ('66_A', 343, 138),
          ('218', 400, 138), ('24', 457, 138), ('51', 513, 138),
        ],
      ]);
      expect(rows.single.roomNo, '218');
      expect(rows.single.seats, 24);
    });

    test('the "Dept." header row is skipped like the "Faculty" one', () {
      final rows = ExamRoomPdfParser.parsePositionedPages([
        [...pageHead(), ...courseRow(138)],
      ]);
      expect(rows.map((r) => r.courseCode), everyElement('CSE321'));
    });
  });

  group('a table continuing over a page break', () {
    /// Page 2 opens straight into more sections of the SAME course. The
    /// course cells are blank because the PDF merged them with the page
    /// before, so nothing on this page names CSE321.
    List<(String, double, double)> continuationPage() => [
          ...pageHead(),
          // Tier 2: a new section, same course — initial, section, room, seats.
          ('STA', 287, 138), ('66_J', 343, 138), ('218', 400, 138),
          ('24', 457, 138), ('51', 513, 138),
          // Tier 3: another room for that same section.
          ('219', 400, 158), ('24', 457, 158),
        ];

    test('the course carries across the break instead of becoming null', () {
      final rows = ExamRoomPdfParser.parsePositionedPages([
        [...pageHead(), ...courseRow(138)],
        continuationPage(),
      ]);
      final later = rows.where((r) => r.section == 'J').toList();
      expect(later, hasLength(2));
      for (final r in later) {
        expect(r.courseCode, 'CSE321',
            reason: 'the continuation page lost its course');
        expect(r.courseTitle, isNotNull);
        expect(r.batch, '66');
      }
    });

    test('a continuation row at the very top of a page is not dropped', () {
      // Before the fix these rows were skipped outright, because the batch and
      // section context was null at the start of every page. Row counts went
      // UP when the context was carried: 1444 -> 1497 across the seven files.
      final rows = ExamRoomPdfParser.parsePositionedPages([
        [...pageHead(), ...courseRow(138)],
        [
          ...pageHead(),
          // Tier 3 only: just another room, no section named anywhere.
          ('002', 400, 138), ('14', 457, 138),
        ],
      ]);
      expect(rows, hasLength(2));
      expect(rows.last.section, 'A');
      expect(rows.last.roomNo, '002');
      expect(rows.last.courseCode, 'CSE321');
    });

    test('a page starting a DIFFERENT exam does not inherit the old course',
        () {
      // The context is carried, but only within one date+slot block. A new
      // slot must not borrow the previous exam's course for its own rows.
      final rows = ExamRoomPdfParser.parsePositionedPages([
        [...pageHead(), ...courseRow(138)],
        [
          ...pageHead(slot: 'B'),
          // Tier 3 continuation with no course named and no carried context.
          ('002', 400, 138), ('14', 457, 138),
        ],
      ]);
      // Only the first page's row survives; the slot-B fragment has no course,
      // no section and no batch to attach to, so it is dropped rather than
      // filed under slot A's exam.
      expect(rows, hasLength(1));
      expect(rows.single.slotLabel, 'A');
    });
  });
}
