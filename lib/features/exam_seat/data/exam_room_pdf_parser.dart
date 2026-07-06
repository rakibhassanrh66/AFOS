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
  final String batch, section, roomNo;
  final int seats;

  ExamRoomAllocationRow({
    this.examTitle, required this.examDate, this.slotLabel, this.slotStart, this.slotEnd,
    this.courseCode, this.courseTitle, this.teacherInitial,
    required this.batch, required this.section, required this.roomNo, required this.seats,
  });

  Map<String, dynamic> toRow() => {
    'exam_title': examTitle, 'exam_date': examDate.toIso8601String().split('T').first,
    'slot_label': slotLabel, 'slot_start': slotStart, 'slot_end': slotEnd,
    'course_code': courseCode, 'course_title': courseTitle, 'teacher_initial': teacherInitial,
    'batch': batch, 'section': section, 'room_no': roomNo, 'seats': seats,
  };
}

class _Word { final String text; final double left, top; _Word(this.text, this.left, this.top); }

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
      for (var page = 0; page < doc.pages.count; page++) {
        final lines = PdfTextExtractor(doc).extractTextLines(startPageIndex: page, endPageIndex: page);
        final words = <_Word>[];
        for (final line in lines) {
          for (final w in line.wordCollection) {
            words.add(_Word(w.text, w.bounds.left, w.bounds.top));
          }
        }
        if (words.isEmpty) continue;
        rows.addAll(_parsePage(words));
      }
      return rows;
    } finally {
      doc.dispose();
    }
  }

  static List<ExamRoomAllocationRow> _parsePage(List<_Word> words) {
    // Group words into visual rows by rounded top-coordinate, sort each
    // row left-to-right — this reconstructs reading order regardless of
    // the underlying PDF content stream's internal ordering.
    final rowsByTop = <int, List<_Word>>{};
    for (final w in words) {
      rowsByTop.putIfAbsent(w.top.round(), () => []).add(w);
    }
    final tops = rowsByTop.keys.toList()..sort((a, b) => b.compareTo(a)); // top-to-bottom on page
    final textRows = <List<_Word>>[
      for (final t in tops) (rowsByTop[t]!..sort((a, b) => a.left.compareTo(b.left)))
    ];

    String? examTitle, slotLabel, slotStart, slotEnd;
    DateTime? examDate;
    final out = <ExamRoomAllocationRow>[];

    // Current "section context" carried across continuation rows.
    String? curCourseCode, curCourseTitle, curTeacherInitial, curBatch, curSection;

    for (final row in textRows) {
      final texts = row.map((w) => w.text).toList();
      final joined = texts.join(' ');
      if (examTitle == null && joined.contains('Examination')) { examTitle = joined; continue; }
      if (slotLabel == null && joined.startsWith('Date:')) {
        final dateIdx = texts.indexOf('Date:');
        final slotIdx = texts.indexOf('Slot:');
        if (dateIdx >= 0 && dateIdx + 1 < texts.length) {
          examDate = _parseDate(texts[dateIdx + 1]);
        }
        if (slotIdx >= 0 && slotIdx + 1 < texts.length) {
          slotLabel = texts[slotIdx + 1];
          final rest = texts.sublist(slotIdx + 2).join(' ');
          final m = RegExp(r'\(?([\d:]+\s*[AP]M)\s*-\s*([\d:]+\s*[AP]M)\)?').firstMatch(rest);
          if (m != null) { slotStart = m.group(1); slotEnd = m.group(2); }
        }
        continue;
      }
      if (texts.contains('Faculty') && texts.contains('Room')) continue; // header row
      if (joined.startsWith('Total') && joined.contains('Seat')) continue; // "Total Seat(s): N" summary line
      if (row.isEmpty) continue;

      final leftmost = row.first.left;
      if (leftmost < _newCourseMaxLeft) {
        // Tier 1: Faculty | CourseCode | Title(words) | TeacherInitial | Section | Room | Seats | Total
        final sectionIdx = texts.indexWhere((t) => _sectionToken.hasMatch(t));
        if (sectionIdx < 2) continue; // can't find a parseable "68_A"-style section token
        final batchSection = texts[sectionIdx].split('_');
        if (batchSection.length != 2) continue;
        curBatch = batchSection[0];
        curSection = batchSection[1];
        curTeacherInitial = texts[sectionIdx - 1];
        curCourseCode = texts[1];
        curCourseTitle = texts.sublist(2, sectionIdx - 1).join(' ');
        _addRoomRow(out, texts.sublist(sectionIdx + 1), examTitle, examDate, slotLabel, slotStart, slotEnd,
            curCourseCode, curCourseTitle, curTeacherInitial, curBatch, curSection);
      } else if (leftmost < _roomColMin) {
        // Tier 2: new section within the same course — TeacherInitial | Section | Room | Seats | Total
        final sectionIdx = texts.indexWhere((t) => _sectionToken.hasMatch(t));
        if (sectionIdx < 1) continue;
        final batchSection = texts[sectionIdx].split('_');
        if (batchSection.length != 2) continue;
        curBatch = batchSection[0];
        curSection = batchSection[1];
        curTeacherInitial = texts[sectionIdx - 1];
        _addRoomRow(out, texts.sublist(sectionIdx + 1), examTitle, examDate, slotLabel, slotStart, slotEnd,
            curCourseCode, curCourseTitle, curTeacherInitial, curBatch, curSection);
      } else if (curBatch != null && curSection != null) {
        // Tier 3: continuation — just another Room+Seats pair for the current section.
        _addRoomRow(out, texts, examTitle, examDate, slotLabel, slotStart, slotEnd,
            curCourseCode, curCourseTitle, curTeacherInitial, curBatch, curSection);
      }
    }
    return out;
  }

  /// roomTokens is [Room, Seats] optionally followed by a trailing Total —
  /// only the first two matter here, the total is just a checksum in the
  /// source document.
  static void _addRoomRow(List<ExamRoomAllocationRow> out, List<String> roomTokens,
      String? examTitle, DateTime? examDate, String? slotLabel, String? slotStart, String? slotEnd,
      String? courseCode, String? courseTitle, String? teacherInitial, String? batch, String? section) {
    if (roomTokens.length < 2 || examDate == null || batch == null || section == null) return;
    final seats = int.tryParse(roomTokens[1]);
    if (seats == null) return;
    out.add(ExamRoomAllocationRow(
      examTitle: examTitle, examDate: examDate, slotLabel: slotLabel,
      slotStart: slotStart, slotEnd: slotEnd,
      courseCode: courseCode, courseTitle: courseTitle, teacherInitial: teacherInitial,
      batch: batch, section: section, roomNo: roomTokens[0], seats: seats,
    ));
  }

  static DateTime? _parseDate(String s) {
    final m = RegExp(r'^(\d{1,2})-(\d{1,2})-(\d{4})$').firstMatch(s);
    if (m == null) return null;
    return DateTime(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
  }
}
