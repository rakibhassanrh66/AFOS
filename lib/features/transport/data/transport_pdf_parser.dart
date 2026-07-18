import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'models/transport_schedule.dart';
import 'transport_grid_parser.dart';

/// Fallback transport importer: reconstructs the schedule table from a PDF by
/// word x/y positions (the same positional approach as
/// exam_room_pdf_parser.dart), builds a string grid, and hands off to the
/// shared [TransportGridParser] so the PDF and Excel paths produce the exact
/// same normalized shape. Fill colours aren't available in a PDF, so section
/// detection here is header-text only (which the source always labels).
class TransportPdfParser {
  TransportPdfParser._();

  static ParsedTransportSchedule parse(List<int> bytes) {
    final doc = PdfDocument(inputBytes: bytes);
    try {
      final words = <_Word>[];
      for (var page = 0; page < doc.pages.count; page++) {
        final lines = PdfTextExtractor(doc)
            .extractTextLines(startPageIndex: page, endPageIndex: page);
        for (final line in lines) {
          for (final w in line.wordCollection) {
            if (w.text.trim().isEmpty) continue; // Syncfusion emits blank words
            words.add(_Word(w.text.trim(), w.bounds.left, w.bounds.top, page));
          }
        }
      }
      if (words.isEmpty) return const ParsedTransportSchedule(semester: 'Unknown', routes: []);
      final grid = _buildGrid(words);
      return TransportGridParser.parse(grid);
    } finally {
      doc.dispose();
    }
  }

  static List<List<String>> _buildGrid(List<_Word> words) {
    // Group into visual rows per (page, rounded-top); order top→bottom.
    final rowsByKey = <String, List<_Word>>{};
    for (final w in words) {
      rowsByKey.putIfAbsent('${w.page}:${w.top.round()}', () => []).add(w);
    }
    final rowKeys = rowsByKey.keys.toList()
      ..sort((a, b) {
        final pa = int.parse(a.split(':')[0]), pb = int.parse(b.split(':')[0]);
        if (pa != pb) return pa.compareTo(pb);
        return int.parse(a.split(':')[1]).compareTo(int.parse(b.split(':')[1]));
      });
    final visualRows = rowKeys.map((k) => rowsByKey[k]!..sort((x, y) => x.left.compareTo(y.left))).toList();

    // Column x-starts come from the header row's keyword positions.
    final colStarts = _columnStarts(visualRows);
    if (colStarts.isEmpty) {
      // No recognizable header — fall back to a flat single-column grid so the
      // grid parser at least reads the title block.
      return visualRows.map((r) => [r.map((w) => w.text).join(' ')]).toList();
    }

    final grid = <List<String>>[];
    for (final row in visualRows) {
      final cells = List<String>.filled(colStarts.length, '');
      for (final w in row) {
        final col = _columnFor(w.left, colStarts);
        cells[col] = cells[col].isEmpty ? w.text : '${cells[col]} ${w.text}';
      }
      grid.add(cells);
    }
    return grid;
  }

  /// Ordered x-start of each of the 5 columns, derived from the header row.
  static List<double> _columnStarts(List<List<_Word>> visualRows) {
    for (final row in visualRows) {
      final joined = row.map((w) => w.text).join(' ').toLowerCase();
      if (!(joined.contains('route') &&
          (joined.contains('start') || joined.contains('departure')) &&
          joined.contains('time'))) {
        continue;
      }
      // Header row found. Locate keyword x-positions.
      double? routeNoX, startX, nameX, detailX, departX;
      for (final w in row) {
        final t = w.text.toLowerCase();
        if (t.startsWith('start')) {
          startX ??= w.left;
        } else if (t.startsWith('name')) {
          nameX ??= w.left;
        } else if (t.startsWith('detail')) {
          detailX ??= w.left;
        } else if (t.startsWith('departure')) {
          departX ??= w.left;
        }
      }
      routeNoX = row.first.left; // leftmost word = Route No column
      final starts = [routeNoX, startX, nameX, detailX, departX]
          .whereType<double>()
          .toList()
        ..sort();
      // Need at least Route No, a start, and a departure to be a real table.
      if (starts.length >= 3) return starts;
    }
    return const [];
  }

  static int _columnFor(double x, List<double> starts) {
    var col = 0;
    for (var i = 0; i < starts.length; i++) {
      // A word belongs to the last column whose start is at/left of it (with a
      // small tolerance so a word straddling the boundary lands correctly).
      if (x >= starts[i] - 12) col = i;
    }
    return col;
  }
}

class _Word {
  final String text;
  final double left, top;
  final int page;
  _Word(this.text, this.left, this.top, this.page);
}
