import 'package:excel/excel.dart';
import 'models/transport_schedule.dart';
import 'transport_grid_parser.dart';
import 'transport_time_parser.dart';

/// Primary transport importer: reads a DIU transport-schedule .xlsx (whether
/// exported from Google Sheets or the master file) into a string grid, then
/// hands off to [TransportGridParser]. Handles typed time cells, merged-cell
/// route blocks (continuation rows leave Route No blank), and passes cell fill
/// colours through for section detection.
class TransportExcelParser {
  TransportExcelParser._();

  static ParsedTransportSchedule parse(List<int> bytes) {
    final book = Excel.decodeBytes(bytes);
    final sheet = _firstNonEmptySheet(book);
    if (sheet == null) return const ParsedTransportSchedule(semester: 'Unknown', routes: []);

    final grid = <List<String>>[];
    for (final row in sheet.rows) {
      grid.add(row.map(_cellText).toList());
    }

    return TransportGridParser.parse(grid, fillHexForRow: (i) => _rowFillHex(sheet, i));
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
