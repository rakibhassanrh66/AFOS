import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Parses a real DIU exam seat-plan PDF into per-room allocation rows.
///
/// Confirmed against an actual sample document (word-position JSON export):
/// each page is one exam date+slot, with a table laid out as fixed text
/// columns (not simple whitespace-separated text) — Faculty | Course Code |
/// Course Title | Teacher Initial | Section (e.g. "68_A" = batch 68,
/// section A) | Room No | Seats | Total. A section spans several rooms
/// (each on its own row, sharing the same left-hand columns only on the
/// first row of that section's block), and a room can be split between
/// two adjacent sections. There is no per-student seat number anywhere in
/// the source — this is a room-capacity allocation, not a seating chart.
///
/// Row classification is based on the leftmost word's x-position per row:
/// a "new section" row starts around the Faculty/Course-code columns
/// (~28-160pt), a "continuation" row (more rooms for the same section)
/// only has Room+Seats words, starting around ~390pt+ — there's a wide
/// empty gap between those two ranges in the source template.
class ExamRoomAllocationRow {
  final String? examTitle;
  final DateTime examDate;
  final String? slotLabel;
  final String? slotStart, slotEnd;
  final String? courseCode, courseTitle, teacherInitial;
  /// The row's leading "Faculty"/"Dept." column, verbatim. Was sitting
  /// unread at the start of every Tier-1 row (see the header comment) — the
  /// source table prints it, this just stops discarding it. Kept raw rather
  /// than normalized into a department CODE (the way the exam-routine
  /// header text is abbreviated to e.g. "CSE") because that abbreviation was
  /// tuned against a "Department of X" sentence, a different shape of text
  /// from whatever this column prints; guessing at that mapping without a
  /// real sample to check it against risks a confidently wrong code, which
  /// is worse than an unabbreviated but honest string.
  final String? department;
  final String batch, section, roomNo;
  final int seats;

  ExamRoomAllocationRow({
    this.examTitle, required this.examDate, this.slotLabel, this.slotStart, this.slotEnd,
    this.courseCode, this.courseTitle, this.teacherInitial, this.department,
    required this.batch, required this.section, required this.roomNo, required this.seats,
  });

  Map<String, dynamic> toRow() => {
    'exam_title': examTitle, 'exam_date': examDate.toIso8601String().split('T').first,
    'slot_label': slotLabel, 'slot_start': slotStart, 'slot_end': slotEnd,
    'course_code': courseCode, 'course_title': courseTitle, 'teacher_initial': teacherInitial,
    'department': department,
    'batch': batch, 'section': section, 'room_no': roomNo, 'seats': seats,
  };
}

class _Word { final String text; final double left, top; _Word(this.text, this.left, this.top); }

/// The "which course/section are we inside" context, carried ACROSS pages.
///
/// It used to be local to one page, so a table continuing over a page break —
/// which every one of these documents does, batch 70 alone spans sections
/// A..M — restarted with no course. Those rows were stored with
/// `course_code = null`, and a null course code joins to no exam, so 57% of
/// the seat plan was invisible to the very screen it exists for.
///
/// Reset deliberately when a page turns out to belong to a different
/// date+slot, so one exam's course can never bleed into the next one's table.
class _BlockContext {
  String? courseCode, courseTitle, teacherInitial, batch, section, department;
  String? slotKey;

  void clear() {
    courseCode = courseTitle = teacherInitial = batch = section = department = null;
  }

  /// Returns after clearing if [key] names a different exam block.
  void enter(String key) {
    if (slotKey != null && slotKey != key) clear();
    slotKey = key;
  }
}

class ExamRoomPdfParser {
  /// Column boundaries (x-position, pt) observed in the real sample —
  /// generous ranges since exact PDF margins can vary slightly. Three row
  /// shapes exist per table, distinguished by the leftmost word's position:
  ///  - < _newCourseMaxLeft: a full new-course row (Faculty CourseCode
  ///    Title... TeacherInitial Section Room Seats Total)
  ///  - < _roomColMin: a new section within the *same* course (only
  ///    TeacherInitial Section Room Seats Total — course cells are blank
  ///    because the PDF merges them visually with the row above)
  ///  - >= _roomColMin: a continuation row, just another Room+Seats pair
  ///    for the current section (a section can span several rooms, and a
  ///    room can be split between two adjacent sections)
  static const _newCourseMaxLeft = 200.0;
  static const _roomColMin = 390.0;
  static final _sectionToken = RegExp(r'^\d+_[A-Za-z0-9]+$');

  static List<ExamRoomAllocationRow> parse(List<int> bytes) {
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final rows = <ExamRoomAllocationRow>[];
      final ctx = _BlockContext();
      for (var page = 0; page < doc.pages.count; page++) {
        final lines = PdfTextExtractor(doc).extractTextLines(startPageIndex: page, endPageIndex: page);
        final words = <_Word>[];
        for (final line in lines) {
          for (final w in line.wordCollection) {
            // Confirmed against a real PDF (not just the pre-converted
            // JSON sample, which had apparently already filtered these
            // out): Syncfusion's wordCollection includes literal blank/
            // whitespace-only "words" interspersed between real ones —
            // e.g. "Machine" and "Learning" in a course title have a
            // blank word between them. Left in, these shift every
            // index-based lookup below and silently drop every row.
            if (w.text.trim().isEmpty) continue;
            words.add(_Word(w.text, w.bounds.left, w.bounds.top));
          }
        }
        if (words.isEmpty) continue;
        rows.addAll(_parsePage(words, ctx));
      }
      return rows;
    } finally {
      doc.dispose();
    }
  }

  /// Runs the page algorithm over positioned words, page by page.
  ///
  /// EXISTS SO THE GEOMETRY CAN BE TESTED WITHOUT THE PDF — the same reason
  /// the routine parser has one. These documents are real university records
  /// and do not belong in a public repository, but the layout IS the parser:
  /// every bug it has had was a coordinate bug. Takes a LIST of pages because
  /// the defect worth pinning hardest only appears across a page break.
  @visibleForTesting
  static List<ExamRoomAllocationRow> parsePositionedPages(
      List<List<(String, double, double)>> pages) {
    final ctx = _BlockContext();
    final out = <ExamRoomAllocationRow>[];
    for (final page in pages) {
      out.addAll(_parsePage(
          [for (final (t, x, y) in page) _Word(t, x, y)], ctx));
    }
    return out;
  }

  static List<ExamRoomAllocationRow> _parsePage(List<_Word> words, _BlockContext ctx) {
    // Group words into visual rows by rounded top-coordinate, sort each
    // row left-to-right — this reconstructs reading order regardless of
    // the underlying PDF content stream's internal ordering.
    final rowsByTop = <int, List<_Word>>{};
    for (final w in words) {
      rowsByTop.putIfAbsent(w.top.round(), () => []).add(w);
    }
    final tops = rowsByTop.keys.toList();

    // Which direction is "top of page" isn't consistent — confirmed
    // against two real sample documents where one increases top going
    // down the page and the other decreases. Rather than assume either,
    // calibrate per page: the "Examination" title row always visually
    // precedes the "Date:" row, so whichever sort direction puts the
    // Examination row's top before the Date row's top is the correct
    // reading order for this specific page.
    int? examTop, dateTop;
    for (final t in tops) {
      final joined = rowsByTop[t]!.map((w) => w.text).join(' ');
      if (examTop == null && joined.contains('Examination')) examTop = t;
      if (dateTop == null && joined.startsWith('Date:')) dateTop = t;
    }
    final descending = examTop == null || dateTop == null || examTop > dateTop;
    tops.sort((a, b) => descending ? b.compareTo(a) : a.compareTo(b));
    final textRows = <List<_Word>>[
      for (final t in tops) (rowsByTop[t]!..sort((a, b) => a.left.compareTo(b.left)))
    ];

    // These stay page-local on purpose: every page of these documents
    // repeats its own "Date: … Slot: …" header, and the guards below take
    // only the FIRST one on a page. Carrying them forward would make a
    // second page's header unreadable and file a slot-B exam under slot A.
    String? examTitle, slotLabel, slotStart, slotEnd;
    DateTime? examDate;
    final out = <ExamRoomAllocationRow>[];

    for (final row in textRows) {
      final texts = row.map((w) => w.text).toList();
      final joined = texts.join(' ');
      if (examTitle == null && joined.contains('Examination')) { examTitle = joined; continue; }
      if (slotLabel == null && joined.startsWith('Date:')) {
        final dateIdx = texts.indexOf('Date:');
        final slotIdx = texts.indexOf('Slot:');
        if (dateIdx >= 0 && dateIdx + 1 < texts.length) {
          // "19-08-2026" is ONE word in some of these documents and FIVE in
          // others ("19", "-", "08", "-", "2026"), because the hyphens are
          // drawn as their own text runs. Matching the first token alone
          // returned null, and a null date drops every row on the page
          // silently — the 19 Aug file parsed to zero rows for exactly this.
          // Rejoin the column before matching.
          final end = slotIdx > dateIdx ? slotIdx : texts.length;
          examDate = _parseDate(texts.sublist(dateIdx + 1, end).join());
        }
        if (slotIdx >= 0 && slotIdx + 1 < texts.length) {
          slotLabel = texts[slotIdx + 1];
          final rest = texts.sublist(slotIdx + 2).join(' ');
          final m = RegExp(r'\(?([\d:]+\s*[AP]M)\s*-\s*([\d:]+\s*[AP]M)\)?').firstMatch(rest);
          if (m != null) { slotStart = m.group(1); slotEnd = m.group(2); }
        }
        // A page that continues the previous page's table keeps its course;
        // a page that starts a different exam drops it.
        ctx.enter('${examDate?.toIso8601String()}|$slotLabel');
        continue;
      }
      // Header row. Two templates in circulation: one heads the first column
      // "Faculty", the other "Dept.".
      if ((texts.contains('Faculty') || texts.contains('Dept.')) &&
          texts.contains('Room')) {
        continue;
      }
      if (joined.startsWith('Total') && joined.contains('Seat')) continue; // "Total Seat(s): N" summary line
      if (row.isEmpty) continue;

      final leftmost = row.first.left;
      if (leftmost < _newCourseMaxLeft) {
        // Tier 1: Faculty | CourseCode | Title(words) | TeacherInitial | Section | Room | Seats | Total
        final sectionIdx = texts.indexWhere((t) => _sectionToken.hasMatch(t));
        if (sectionIdx < 2) continue; // can't find a parseable "68_A"-style section token
        final batchSection = texts[sectionIdx].split('_');
        if (batchSection.length != 2) continue;
        ctx.batch = batchSection[0];
        ctx.section = batchSection[1];
        ctx.teacherInitial = texts[sectionIdx - 1];
        ctx.department = texts[0];
        ctx.courseCode = texts[1];
        ctx.courseTitle = texts.sublist(2, sectionIdx - 1).join(' ');
        _addRoomRow(out, texts.sublist(sectionIdx + 1), examTitle, examDate, slotLabel, slotStart, slotEnd,
            ctx.courseCode, ctx.courseTitle, ctx.teacherInitial, ctx.department, ctx.batch, ctx.section);
      } else if (leftmost < _roomColMin) {
        // Tier 2: new section within the same course — TeacherInitial | Section | Room | Seats | Total
        final sectionIdx = texts.indexWhere((t) => _sectionToken.hasMatch(t));
        if (sectionIdx < 1) continue;
        final batchSection = texts[sectionIdx].split('_');
        if (batchSection.length != 2) continue;
        ctx.batch = batchSection[0];
        ctx.section = batchSection[1];
        ctx.teacherInitial = texts[sectionIdx - 1];
        _addRoomRow(out, texts.sublist(sectionIdx + 1), examTitle, examDate, slotLabel, slotStart, slotEnd,
            ctx.courseCode, ctx.courseTitle, ctx.teacherInitial, ctx.department, ctx.batch, ctx.section);
      } else if (ctx.batch != null && ctx.section != null) {
        // Tier 3: continuation — just another Room+Seats pair for the current section.
        _addRoomRow(out, texts, examTitle, examDate, slotLabel, slotStart, slotEnd,
            ctx.courseCode, ctx.courseTitle, ctx.teacherInitial, ctx.department, ctx.batch, ctx.section);
      }
    }
    return out;
  }

  /// roomTokens is [Room, Seats] optionally followed by a trailing Total —
  /// only the first two matter here, the total is just a checksum in the
  /// source document.
  static void _addRoomRow(List<ExamRoomAllocationRow> out, List<String> roomTokens,
      String? examTitle, DateTime? examDate, String? slotLabel, String? slotStart, String? slotEnd,
      String? courseCode, String? courseTitle, String? teacherInitial, String? department,
      String? batch, String? section) {
    if (roomTokens.length < 2 || examDate == null || batch == null || section == null) return;

    // Same split-token hazard as the date: a room is "G1-001" in one
    // template and "G1", "-", "001" in the other, while a numeric room
    // ("218") is always a single token. Rejoin around a lone hyphen before
    // reading the seat count — otherwise int.tryParse lands on "-", returns
    // null, and the row is dropped without a word.
    var i = 0;
    final room = StringBuffer(roomTokens[i]);
    while (i + 2 < roomTokens.length && roomTokens[i + 1] == '-') {
      room..write('-')..write(roomTokens[i + 2]);
      i += 2;
    }
    if (i + 1 >= roomTokens.length) return;
    final seats = int.tryParse(roomTokens[i + 1]);
    if (seats == null) return;
    out.add(ExamRoomAllocationRow(
      examTitle: examTitle, examDate: examDate, slotLabel: slotLabel,
      slotStart: slotStart, slotEnd: slotEnd,
      courseCode: courseCode, courseTitle: courseTitle, teacherInitial: teacherInitial,
      department: department,
      batch: batch, section: section, roomNo: room.toString(), seats: seats,
    ));
  }

  static DateTime? _parseDate(String s) {
    final m = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})$').firstMatch(s);
    if (m == null) return null;
    return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  }
}
