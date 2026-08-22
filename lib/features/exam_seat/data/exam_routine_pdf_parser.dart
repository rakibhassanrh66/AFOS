import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Parses a DIU **exam routine** PDF — the timetable of which course sits when
/// — into one row per (date, slot, course, batch).
///
/// NOT THE SAME DOCUMENT as the seat plan. `exam_room_pdf_parser.dart` reads
/// "Seat Details", which says which ROOMS a section occupies. This reads
/// "Examination Routine", which says which DATE and SLOT a batch sits an
/// exam. Neither document contains the other's information, and until now only
/// the seat plan had a parser at all — which is why `exams` held 38 rows with
/// no room, no season and every `exam_type` set to the string 'mid'.
///
/// THE LAYOUT, measured from a real document (Summer 2026 finals, CSE):
///
///   x=36    x=126..200      x=315      x=382..473    x=618      x=737..785
///   date    Slot A course   batch      Slot B course batch      Slot C course
///
/// A slot cell can hold MORE THAN ONE course — 19/08 Slot A carries both
/// CSE326/Batch-65 and CSE321/Batch-66 at different heights — so a course is
/// paired with the batch nearest it vertically, not with "the" batch of the
/// column.
///
/// COLUMN BOUNDARIES ARE DERIVED, NOT HARDCODED. Every page carries a header
/// row of `Slot A:` / `Batch` / `Slot B:` / … and the boundaries are read off
/// those anchors. Hardcoding x=315 would work on exactly this file and break on
/// next semester's, which is the failure mode this project has hit before.
class ExamRoutineEntry {
  final DateTime date;
  final String slotLabel; // 'A', 'B', 'C'
  final String? slotStart; // '09:00 am'
  final String? slotEnd; // '11:00 am'
  final String courseCode; // 'CSE326'
  final String courseTitle; // 'Social and Professional Issues in Computing'
  final String batch; // '65'

  const ExamRoutineEntry({
    required this.date,
    required this.slotLabel,
    required this.courseCode,
    required this.courseTitle,
    required this.batch,
    this.slotStart,
    this.slotEnd,
  });

  /// The weekday, DERIVED from the date and never read from the page.
  ///
  /// The real document prints "Thurseday". A parser that trusted the printed
  /// name would either store the typo or refuse the row; the date is
  /// unambiguous, so the name is computed from it.
  String get dayName => const [
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday',
      ][date.weekday - 1];

  @override
  String toString() =>
      '${date.toIso8601String().split('T').first} $slotLabel $courseCode '
      'Batch-$batch';
}

/// What the routine's title line says about the whole document.
class ExamRoutineHeader {
  /// 'mid' | 'final' | 'retake' | 'improvement'
  final String? examType;

  /// 'spring' | 'summer' | 'fall'
  final String? season;
  final int? year;
  final String? department;

  const ExamRoutineHeader({
    this.examType,
    this.season,
    this.year,
    this.department,
  });

  bool get isComplete => examType != null && season != null && year != null;
}

class ExamRoutineParseResult {
  final ExamRoutineHeader header;
  final List<ExamRoutineEntry> entries;

  /// Anything the parser could see but could not confidently place. Surfaced
  /// to the uploader rather than dropped: a routine that silently loses one
  /// batch's exam is worse than one that refuses to import.
  final List<String> warnings;

  const ExamRoutineParseResult({
    required this.header,
    required this.entries,
    this.warnings = const [],
  });

  DateTime? get startsOn => entries.isEmpty
      ? null
      : entries.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);

  DateTime? get endsOn => entries.isEmpty
      ? null
      : entries.map((e) => e.date).reduce((a, b) => a.isAfter(b) ? a : b);
}

class _W {
  final String text;
  final double x, y;
  const _W(this.text, this.x, this.y);
}

/// One slot's horizontal extent on the page.
class _SlotColumn {
  final String label;
  final double courseFrom, courseTo;
  final double batchFrom, batchTo;
  String? start, end;
  _SlotColumn(this.label, this.courseFrom, this.courseTo, this.batchFrom,
      this.batchTo);
}

class ExamRoutinePdfParser {
  ExamRoutinePdfParser._();

  /// Words closer than this vertically are treated as the same visual line.
  static const _lineTolerance = 4.0;

  static final _dateRe = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$');
  static final _slotRe = RegExp(r'^Slot\s*([A-Z])\s*:?$', caseSensitive: false);
  static final _batchRe = RegExp(r'Batch\s*[-–—]\s*(\d+)', caseSensitive: false);
  static final _codeRe = RegExp(r'\b([A-Z]{2,4})\s*[-]?\s*(\d{3})\b');

  /// Times like `09:00 am – 11.00 am`. The dash is ANY dash — the source uses
  /// an en-dash that several extractors mangle — and minutes may be separated
  /// by a dot rather than a colon, which the real document does.
  static final _timeRe = RegExp(
    r'(\d{1,2})[:.](\d{2})\s*([ap]\.?m\.?)\s*[-–—~]\s*(\d{1,2})[:.](\d{2})\s*([ap]\.?m\.?)',
    caseSensitive: false,
  );

  static ExamRoutineParseResult parse(List<int> bytes) {
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final entries = <ExamRoutineEntry>[];
      final warnings = <String>[];
      // Columns survive across pages so a continuation page that omits
      // the slot header can still be read.
      final carried = <_SlotColumn>[];
      ExamRoutineHeader header = const ExamRoutineHeader();

      for (var p = 0; p < doc.pages.count; p++) {
        final words = _wordsOf(doc, p);
        if (words.isEmpty) continue;

        if (!header.isComplete) {
          final h = _readHeader(words);
          if (h != null) header = h;
        }

        entries.addAll(_parsePage(words, warnings, p + 1, carried));
      }

      if (entries.isEmpty) {
        warnings.add(
            'No exam rows were found. This may not be an examination routine, '
            'or its layout differs from the one this parser understands.');
      }
      return ExamRoutineParseResult(
          header: header, entries: entries, warnings: warnings);
    } finally {
      doc.dispose();
    }
  }

  /// Runs the page algorithm over positioned words directly.
  ///
  /// EXISTS SO THE GEOMETRY CAN BE TESTED WITHOUT THE PDF. The source document
  /// is a real university record and does not belong in a public repository,
  /// but the layout is the whole substance of this parser — every bug it had
  /// was a coordinate bug. Tests feed the exact (text, x, y) triples measured
  /// from the real file, so the column ownership, the header/times offset and
  /// the per-code splitting stay pinned.
  @visibleForTesting
  static List<ExamRoutineEntry> parsePositionedWords(
      List<(String, double, double)> words) {
    final ws = [for (final (t, x, y) in words) _W(t, x, y)];
    return _parsePage(ws, <String>[], 1, <_SlotColumn>[]);
  }

  static List<_W> _wordsOf(PdfDocument doc, int page) {
    final out = <_W>[];
    final lines = PdfTextExtractor(doc)
        .extractTextLines(startPageIndex: page, endPageIndex: page);
    for (final line in lines) {
      for (final w in line.wordCollection) {
        // Syncfusion interleaves blank "words" between real ones. Left in,
        // every index- and gap-based decision below shifts. The seat-plan
        // parser learned this the same way.
        if (w.text.trim().isEmpty) continue;
        out.add(_W(w.text.trim(), w.bounds.left, w.bounds.top));
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- header

  /// Reads "Final Examination Routine, Summer 2026" and the department line.
  ///
  /// LINE BY LINE, not over one joined blob. Joining the whole top of the page
  /// and running `Department of ([A-Za-z &]+)` against it let the capture run
  /// straight past "Engineering" into the title beneath, and the initialism
  /// came out "CSESER" instead of "CSE".
  static ExamRoutineHeader? _readHeader(List<_W> words) {
    final lines = _groupLines(words.where((w) => w.y < 140).toList());
    if (lines.isEmpty) return null;

    final all = lines.map((l) => l.map((w) => w.text).join(' ')).toList();
    final blob = all.join(' ');
    final lower = blob.toLowerCase();

    String? type;
    if (lower.contains('final')) {
      type = 'final';
    } else if (lower.contains('mid')) {
      type = 'mid';
    } else if (lower.contains('retake') || lower.contains('re-take')) {
      type = 'retake';
    } else if (lower.contains('improvement')) {
      type = 'improvement';
    }

    String? season;
    for (final sName in ['spring', 'summer', 'fall', 'autumn']) {
      if (lower.contains(sName)) {
        season = sName == 'autumn' ? 'fall' : sName;
        break;
      }
    }

    final yearM = RegExp(r'\b(20\d{2})\b').firstMatch(blob);
    final year = yearM == null ? null : int.tryParse(yearM.group(1)!);

    String? dept;
    for (final line in all) {
      final m = RegExp(r'Department of (.+)$', caseSensitive: false)
          .firstMatch(line.trim());
      if (m == null) continue;
      // Bounded to THIS line, so it cannot swallow the title below it.
      dept = m
          .group(1)!
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 2 && w.toLowerCase() != 'and')
          .map((w) => w[0].toUpperCase())
          .join();
      if (dept.isEmpty) dept = null;
      break;
    }

    if (type == null && season == null && year == null) return null;
    return ExamRoutineHeader(
        examType: type, season: season, year: year, department: dept);
  }

  /// Groups words into visual lines by y, each sorted left to right.
  static List<List<_W>> _groupLines(List<_W> words) {
    final sorted = [...words]..sort((a, b) => a.y.compareTo(b.y));
    final out = <List<_W>>[];
    for (final w in sorted) {
      if (out.isEmpty || (w.y - out.last.first.y).abs() > _lineTolerance) {
        out.add(<_W>[w]);
      } else {
        out.last.add(w);
      }
    }
    for (final l in out) {
      l.sort((a, b) => a.x.compareTo(b.x));
    }
    return out;
  }

  // ------------------------------------------------------------------ page

  /// Blocks are delimited by the SLOT HEADER ROW, not by the date.
  ///
  /// The header (`Slot A: | Batch | Slot B: | ...`) repeats above every date,
  /// and the date label sits *inside* the block it heads, roughly 70pt below
  /// it. Slicing on the date instead put each date's own courses in the
  /// previous date's block.
  static List<ExamRoutineEntry> _parsePage(
      List<_W> words, List<String> warnings, int pageNo, List<_SlotColumn> carried) {
    final lines = _groupLines(words);

    final headerIdx = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].any((w) => _isSlotHead(lines[i], w) != null)) headerIdx.add(i);
    }

    // A CONTINUATION PAGE HAS NO HEADER, AND STILL HAS EXAMS ON IT.
    //
    // Page 3 of the real document carries 27/08 with two batches and no slot
    // header at all — the table simply runs on. Refusing the page lost a whole
    // exam day. When the header is absent the columns from the previous page
    // are reused (the table cannot change shape mid-run) and the DATE rows
    // become the block boundaries instead.
    if (headerIdx.isEmpty) {
      if (carried.isEmpty) {
        warnings.add('Page $pageNo: no "Slot A/B/C" header row was found and '
            'no earlier page established the columns, so nothing could be '
            'placed in a time slot.');
        return const [];
      }
      return _parseHeaderlessPage(lines, carried);
    }

    final slots = _slotColumns(lines, headerIdx);
    if (slots.isEmpty) {
      warnings.add('Page $pageNo: the slot header row had no readable columns.');
      return const [];
    }
    // Hand the derived columns back for any continuation page that follows.
    carried
      ..clear()
      ..addAll(slots);

    final out = <ExamRoutineEntry>[];

    // A PAGE CAN OPEN MID-BLOCK, AND THAT BLOCK IS STILL AN EXAM DAY.
    //
    // Page 2 of the real document begins with 23/08 whose slot header sat at
    // the foot of page 1. Building blocks only from header rows downwards
    // dropped it silently — a whole exam day, five courses, gone, with no
    // warning. Anything above the first header row is parsed here first, using
    // the columns the previous page established.
    if (headerIdx.first > 0) {
      final lead = lines.sublist(0, headerIdx.first);
      if (lead.any((l) => l.any((w) => _dateOf(w.text) != null))) {
        out.addAll(_parseHeaderlessPage(lead, carried.isEmpty ? slots : carried));
      }
    }

    for (var b = 0; b < headerIdx.length; b++) {
      final from = headerIdx[b];
      final to = b + 1 < headerIdx.length ? headerIdx[b + 1] : lines.length;
      // THE HEADER ROW IS EXCLUDED FROM THE BLOCK'S CONTENT.
      //
      // 'Slot', 'A:', '09:00', 'am' all sit inside slot A's OWN course column,
      // and the times line is only ~12pt above the first course line — well
      // inside _cellGap. Left in, they merged into the first course cell,
      // which is why one title came out as
      // "Slot B: 12:00 pm – 02:00 pm : Object Oriented Programming
      //  CSE226: Numerical Methods" — a slot label, a time range and TWO
      // courses in a single row.
      final headTop = lines[from].first.y;
      final blockWords = <_W>[
        for (final l in lines.sublist(from, to))
          if ((l.first.y - headTop) > 24) ...l
      ];

      DateTime? date;
      for (final w in blockWords) {
        final d = _dateOf(w.text);
        if (d != null) {
          date = d;
          break;
        }
      }
      if (date == null) continue; // a trailing header with no block under it

      final owned = _batchesBySlot(slots, blockWords);
      for (final slot in slots) {
        out.addAll(_entriesForSlot(
            date, slot, blockWords, owned[slot.label] ?? const [], warnings, pageNo));
      }
    }
    return out;
  }

  /// A page whose table runs on from the previous one, with no header.
  ///
  /// Blocks are delimited by the DATE rows instead, and the column geometry is
  /// the one the last headed page established.
  static List<ExamRoutineEntry> _parseHeaderlessPage(
      List<List<_W>> lines, List<_SlotColumn> slots) {
    final dateIdx = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].any((w) => _dateOf(w.text) != null)) dateIdx.add(i);
    }
    if (dateIdx.isEmpty) return const [];

    final out = <ExamRoutineEntry>[];
    final sink = <String>[];
    for (var b = 0; b < dateIdx.length; b++) {
      final from = dateIdx[b];
      final to = b + 1 < dateIdx.length ? dateIdx[b + 1] : lines.length;
      final blockWords = <_W>[for (final l in lines.sublist(from, to)) ...l];

      DateTime? date;
      for (final w in blockWords) {
        final d = _dateOf(w.text);
        if (d != null) {
          date = d;
          break;
        }
      }
      if (date == null) continue;
      final owned = _batchesBySlot(slots, blockWords);
      for (final slot in slots) {
        out.addAll(_entriesForSlot(
            date, slot, blockWords, owned[slot.label] ?? const [], sink, 0));
      }
    }
    return out;
  }

  /// The slot letter if [w] begins a `Slot X:` label on [line].
  ///
  /// Syncfusion tokenises `Slot A:` as TWO words — 'Slot' then 'A:' — so
  /// matching a single word against /^Slot ([A-Z]):?$/ found nothing at all and
  /// the parser reported "no slot header" on every page. Both shapes are
  /// accepted now, because a differently-produced PDF may well emit one word.
  static String? _isSlotHead(List<_W> line, _W w) {
    final single = _slotRe.firstMatch(w.text);
    if (single != null) return single.group(1)!.toUpperCase();
    if (w.text.toLowerCase() != 'slot') return null;
    final i = line.indexOf(w);
    if (i < 0 || i + 1 >= line.length) return null;
    final m = RegExp(r'^([A-Za-z])\s*:?$').firstMatch(line[i + 1].text);
    return m?.group(1)?.toUpperCase();
  }

  static DateTime? _dateOf(String s) {
    final m = _dateRe.firstMatch(s);
    if (m == null) return null;
    final d = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final y = int.parse(m.group(3)!);
    // dd/mm/yyyy — the source is Bangladeshi and day-first.
    if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    return DateTime(y, mo, d);
  }

  /// Derives each slot's course and batch x-ranges from the header anchors.
  ///
  /// Measured on the real document (Syncfusion coordinates):
  ///   Slot A x=141  Batch x=241 | Slot B x=348  Batch x=469 | Slot C x=581  Batch x=706
  /// The boundaries below are computed from those anchors rather than written
  /// down, so a routine with different margins — or two slots instead of three
  /// — still resolves.
  static List<_SlotColumn> _slotColumns(
      List<List<_W>> lines, List<int> headerIdx) {
    final slotX = <String, double>{};
    final batchXs = <double>[];

    for (final i in headerIdx) {
      final line = lines[i];
      for (final w in line) {
        final label = _isSlotHead(line, w);
        if (label != null) {
          final cur = slotX[label];
          slotX[label] = cur == null || w.x < cur ? w.x : cur;
        }
        if (w.text.toLowerCase() == 'batch') batchXs.add(w.x);
      }
    }
    if (slotX.isEmpty) return const [];

    batchXs.sort();
    final batchCols = <double>[];
    for (final x in batchXs) {
      if (batchCols.isEmpty || (x - batchCols.last).abs() > 40) {
        batchCols.add(x);
      }
    }

    final labels = slotX.keys.toList()
      ..sort((a, b) => slotX[a]!.compareTo(slotX[b]!));

    // The batch column belonging to each slot is the first one to its right.
    final batchFor = <String, double>{};
    for (final l in labels) {
      batchFor[l] = batchCols.firstWhere((b) => b > slotX[l]!,
          orElse: () => slotX[l]! + 120);
    }

    final cols = <_SlotColumn>[];
    for (var i = 0; i < labels.length; i++) {
      final l = labels[i];
      // A slot's territory runs from a little left of its own label to a
      // little left of the next slot's. The `Batch` header is NOT used: its x
      // drifts between header rows, and deriving the course boundary from it
      // put slot A's boundary one point to the right of slot A's own batch
      // token. Slot labels are stable, so the whole geometry hangs off them.
      final from = slotX[l]! - 70;
      final to = i + 1 < labels.length ? slotX[labels[i + 1]]! - 70 : double.infinity;
      cols.add(_SlotColumn(l, from, to, from, to));
    }

    // Slot times live on the line under the label, split across five words
    // ('09:00','am','–','11.00','am'), so the column's words are rejoined
    // before the pattern is applied.
    for (final c in cols) {
      for (final i in headerIdx) {
        // THREE LINES DOWN, not one. The `Batch` header sits at y=125 against
        // the `Slot` row's y=119 — six points apart, which is more than
        // _lineTolerance, so _groupLines correctly makes it its own line and
        // the times end up two rows below the label rather than one. Looking
        // only at i+1 found the Batch row every time and no slot ever got a
        // start or end time.
        for (final li in [
          for (var k = 0; k < 4 && i + k < lines.length; k++) i + k
        ]) {
          final joined = lines[li]
              .where((w) => w.x >= c.courseFrom && w.x < c.batchTo)
              .map((w) => w.text)
              .join(' ');
          final m = _timeRe.firstMatch(joined);
          if (m != null) {
            c.start =
                '${m.group(1)}:${m.group(2)} ${m.group(3)!.toLowerCase()}';
            c.end = '${m.group(4)}:${m.group(5)} ${m.group(6)!.toLowerCase()}';
            break;
          }
        }
        if (c.start != null) break;
      }
    }
    return cols;
  }

  /// Every course sitting in one slot column of one date block.
  static List<ExamRoutineEntry> _entriesForSlot(
    DateTime date,
    _SlotColumn slot,
    List<_W> block,
    List<(String, double)> batches,
    List<String> warnings,
    int pageNo,
  ) {
    final courseWords = block
        .where((w) => w.x >= slot.courseFrom && w.x < slot.courseTo)
        .where((w) => _slotRe.firstMatch(w.text) == null)
        .where((w) => !_timeRe.hasMatch(w.text))
        // Batch labels sit INSIDE the course column, so without this the
        // title read 'Social and Professional Issues Batch-65 in Computing'.
        .where((w) => _batchRe.firstMatch(w.text) == null)
        .toList()
      ..sort((a, b) => a.y.compareTo(b.y));

    if (courseWords.isEmpty) return const [];

    // ONE ENTRY PER COURSE CODE, not per visual cell.
    //
    // Grouping by vertical gap merged neighbours: 20/08 slot B came out as a
    // single row titled "Object Oriented Programming CSE226: Numerical
    // Methods" carrying one batch for two different exams. A course code is an
    // unambiguous start-of-record marker, so the column is split on those
    // instead, and each code takes the batch nearest its OWN line.
    final codeIdx = <int>[];
    for (var i = 0; i < courseWords.length; i++) {
      final m = _codeRe.firstMatch(courseWords[i].text.toUpperCase());
      if (m != null && m.start == 0) codeIdx.add(i);
    }
    if (codeIdx.isEmpty) return const [];

    final out = <ExamRoutineEntry>[];
    for (var c = 0; c < codeIdx.length; c++) {
      final at = codeIdx[c];
      final upTo = c + 1 < codeIdx.length ? codeIdx[c + 1] : courseWords.length;
      final head = courseWords[at];
      final m = _codeRe.firstMatch(head.text.toUpperCase())!;
      final code = m.group(1)! + m.group(2)!;

      // "CSE321:Computer" carries the first title word in the same token.
      final tail = head.text.substring(m.end);
      // A TITLE STOPS A FEW LINES BELOW ITS CODE.
      //
      // The last page's footer — "Instructions for Students", the committee
      // member list — sits inside the course columns, and with no vertical
      // bound the final course of the document absorbed the lot: PHY101's
      // title ran to three hundred characters of examination-hall rules. A
      // course cell is at most three or four lines tall.
      final rest = courseWords
          .sublist(at + 1, upTo)
          .where((w) => w.y - head.y <= 46)
          .map((w) => w.text)
          .join(' ');

      var title = ('$tail $rest')
          .replaceAll(RegExp(r'\[[^\]]*\]'), '')
          .replaceAll(RegExp(r'^[\s:\-]+'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (title.isEmpty) title = code;

      final batch = _batchFor(head.y, head.y, batches);
      if (batch == null) {
        warnings.add(
            'Page $pageNo: ${date.day}/${date.month} slot ${slot.label} '
            '"$code" has no batch beside it and was skipped. '
            '[code at y ${head.y.toStringAsFixed(0)}, '
            'candidates: ${batches.isEmpty ? "none" : batches.map((b) => "${b.$1}@${b.$2.toStringAsFixed(0)}").join(" ")}]');
        continue;
      }

      out.add(ExamRoutineEntry(
        date: date,
        slotLabel: slot.label,
        slotStart: slot.start,
        slotEnd: slot.end,
        courseCode: code,
        courseTitle: title,
        batch: batch,
      ));
    }
    return out;
  }

  /// Assigns every `Batch-NN` token in a block to the slot it belongs to.
  ///
  /// OWNERSHIP BY NEAREST COLUMN TO THE LEFT. A batch label always belongs to
  /// the course column immediately to its left, which is a fact about the
  /// table rather than a measurement — unlike an x-window read off the `Batch`
  /// header, which missed slot A's own batch token by ONE POINT and silently
  /// dropped every slot A exam in the document.
  static Map<String, List<(String, double)>> _batchesBySlot(
      List<_SlotColumn> slots, List<_W> block) {
    final out = <String, List<(String, double)>>{
      for (final s in slots) s.label: <(String, double)>[]
    };
    for (final w in block) {
      final m = _batchRe.firstMatch(w.text);
      if (m == null) continue;
      _SlotColumn? owner;
      for (final s in slots) {
        if (s.courseFrom <= w.x &&
            (owner == null || s.courseFrom > owner.courseFrom)) {
          owner = s;
        }
      }
      if (owner != null) out[owner.label]!.add((m.group(1)!, w.y));
    }
    return out;
  }

  /// The batch whose label sits nearest this course code vertically.
  ///
  /// Nearest rather than "the one inside a y range": the batch label is
  /// vertically centred against a multi-line course cell, so it frequently
  /// sits between the code line and the title line, and sometimes just below
  /// the last one.
  static String? _batchFor(
      double top, double bottom, List<(String, double)> batches) {
    if (batches.isEmpty) return null;
    final mid = (top + bottom) / 2;
    (String, double)? best;
    var bestD = double.infinity;
    for (final b in batches) {
      final d = (b.$2 - mid).abs();
      if (d < bestD) {
        bestD = d;
        best = b;
      }
    }
    // A batch more than a cell-height away belongs to a different course.
    if (bestD > 60) return null;
    return best?.$1;
  }
}
