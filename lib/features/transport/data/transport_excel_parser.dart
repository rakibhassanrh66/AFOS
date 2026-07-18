import 'package:excel/excel.dart';
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';
import 'models/transport_schedule.dart';
import 'transport_grid_parser.dart';
import 'transport_time_parser.dart';

/// Primary transport importer: reads a DIU transport-schedule .xlsx (whether
/// exported from Google Sheets or the master file) into a string grid, then
/// hands off to [TransportGridParser]. Handles typed time cells, merged-cell
/// route blocks (continuation rows leave Route No blank), and passes cell fill
/// colours through for section detection.
///
/// Two readers: the `excel` package is tried first (it also exposes cell fill
/// colours, used as a secondary section marker). But `excel` v4 throws
/// "Null check operator used on a null value" inside its own cell parser on
/// some Google-Sheets exports (confirmed against the real DIU Summer-2026
/// sheet), so any failure — or an empty parse — falls back to the more tolerant
/// `spreadsheet_decoder` (which has no fill-colour info; section detection then
/// relies on the text keywords in [TransportGridParser]).
class TransportExcelParser {
  TransportExcelParser._();

  static ParsedTransportSchedule parse(List<int> bytes) {
    try {
      final r = _parseWithExcel(bytes);
      if (r.routes.isNotEmpty) return r;
    } catch (_) {
      // excel package choked (its known cell-parser null crash) — fall through.
    }
    return _parseWithSpreadsheetDecoder(bytes);
  }

  // --- Primary reader: `excel` package (typed cells + fill colours) ---------
  static ParsedTransportSchedule _parseWithExcel(List<int> bytes) {
    final book = Excel.decodeBytes(bytes);
    final sheet = _firstNonEmptySheet(book);
    if (sheet == null) return const ParsedTransportSchedule(semester: 'Unknown', routes: []);

    final grid = <List<String>>[];
    for (final row in sheet.rows) {
      grid.add(row.map(_cellText).toList());
    }

    return TransportGridParser.parse(grid, fillHexForRow: (i) => _rowFillHex(sheet, i));
  }

  // --- Fallback reader: `spreadsheet_decoder` (tolerant; no fill colours) ----
  static ParsedTransportSchedule _parseWithSpreadsheetDecoder(List<int> bytes) {
    final dec = SpreadsheetDecoder.decodeBytes(bytes);
    SpreadsheetTable? best;
    var bestRows = 0;
    for (final name in dec.tables.keys) {
      final t = dec.tables[name];
      if (t == null) continue;
      if (t.maxRows > bestRows) { best = t; bestRows = t.maxRows; }
    }
    if (best == null) return const ParsedTransportSchedule(semester: 'Unknown', routes: []);

    final grid = <List<String>>[];
    for (final row in best.rows) {
      grid.add(row.map(_sdCellText).toList());
    }
    return TransportGridParser.parse(grid);
  }

  static Sheet? _firstNonEmptySheet(Excel book) {
    Sheet? best;
    var bestRows = 0;
    for (final name in book.tables.keys) {
      final s = book.tables[name];
      if (s == null) continue;
      if (s.maxRows > bestRows) { best = s; bestRows = s.maxRows; }
    }
    return best;
  }

  /// Cell -> display string. Typed time cells and Excel serial-time doubles are
  /// converted to canonical "h:mm AM/PM" so the grid parser sees clean text.
  static String _cellText(Data? cell) {
    final v = cell?.value;
    if (v == null) return '';
    if (v is TextCellValue) return v.value.toString().trim();
    if (v is TimeCellValue) return TransportTimeParser.fromHourMinute(v.hour, v.minute).time ?? '';
    if (v is DateTimeCellValue) return TransportTimeParser.fromHourMinute(v.hour, v.minute).time ?? '';
    if (v is DoubleCellValue) {
      final d = v.value;
      if (d > 0 && d < 1) {
        final t = TransportTimeParser.fromDayFraction(d);
        if (t.time != null) return t.time!;
      }
      return d.toString();
    }
    if (v is IntCellValue) return v.value.toString();
    return v.toString().trim();
  }

  /// spreadsheet_decoder cell -> display string. It returns time cells as raw
  /// day-fraction doubles (e.g. 0.2916… == 7:00 AM), so those must be converted
  /// here — otherwise the time regex would misread "0.29" as 0:29.
  static String _sdCellText(dynamic v) {
    if (v == null) return '';
    if (v is num) {
      final d = v.toDouble();
      if (d > 0 && d < 1) {
        final t = TransportTimeParser.fromDayFraction(d);
        if (t.time != null) return t.time!;
      }
      return v is int ? v.toString() : d.toString();
    }
    return v.toString().trim();
  }

  static String? _rowFillHex(Sheet sheet, int rowIndex) {
    try {
      if (rowIndex < 0 || rowIndex >= sheet.rows.length) return null;
      for (final cell in sheet.rows[rowIndex]) {
        final hex = cell?.cellStyle?.backgroundColor.colorHex;
        if (hex != null && hex.isNotEmpty && hex.toLowerCase() != 'none' && !hex.toUpperCase().endsWith('FFFFFF')) {
          return hex.toUpperCase();
        }
      }
    } catch (_) {}
    return null;
  }
}
