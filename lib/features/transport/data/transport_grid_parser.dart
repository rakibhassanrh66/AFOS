import 'models/transport_schedule.dart';
import 'transport_time_parser.dart';

/// Shared "grid of string cells -> normalized schedule" logic, used by both
/// the Excel importer (primary) and the PDF fallback so they produce the exact
/// same shape from the same document structure. The only source-specific bit
/// (Excel fill colours for section detection) is injected via [fillHexForRow].
class TransportGridParser {
  TransportGridParser._();

  static ParsedTransportSchedule parse(
    List<List<String>> grid, {
    String? Function(int rowIndex)? fillHexForRow,
  }) {
    final semester = _extractSemester(grid);
    final campus = _extractCampus(grid);

    final headerRow = _findHeaderRow(grid);
    if (headerRow == -1) {
      return ParsedTransportSchedule(semester: semester, campus: campus, routes: const []);
    }
    final cols = _resolveColumns(grid[headerRow]);

    final routes = <TransportRoute>[];
    var type = ScheduleType.regular;

    var r = headerRow + 1;
    while (r < grid.length) {
      final row = grid[r];
      final joined = row.join(' ').trim();

      final section = _sectionOf(joined, fillHexForRow?.call(r));
      if (section != null) {
        type = section;
        r++;
        // A Friday section repeats the column header row right beneath it.
        if (r < grid.length && _looksLikeHeader(grid[r])) r++;
        continue;
      }

      final routeNo = _norm(_at(row, cols.routeNo));
      if (!_isRouteToken(routeNo)) { r++; continue; }

      final blockRows = <List<String>>[row];
      var rr = r + 1;
      while (rr < grid.length) {
        final next = grid[rr];
        final nextNo = _norm(_at(next, cols.routeNo));
        final nextJoined = next.join(' ').trim();
        if (_isRouteToken(nextNo) || _sectionOf(nextJoined, fillHexForRow?.call(rr)) != null) break;
        if (nextJoined.isEmpty) { rr++; continue; }
        blockRows.add(next);
        rr++;
      }

      routes.add(_buildRoute(semester: semester, type: type, routeNo: routeNo, cols: cols, blockRows: blockRows));
      r = rr;
    }

    return ParsedTransportSchedule(semester: semester, campus: campus, routes: routes);
  }

  static TransportRoute _buildRoute({
    required String semester,
    required ScheduleType type,
    required String routeNo,
    required TransportColumns cols,
    required List<List<String>> blockRows,
  }) {
    final first = blockRows.first;
    final routeName = _norm(_at(first, cols.routeName));
    final details = blockRows
        .map((row) => _at(row, cols.routeDetails))
        .firstWhere((v) => v.trim().isNotEmpty, orElse: () => '');
    final toCells = blockRows.map((row) => _at(row, cols.startTime)).join('\n');
    final fromCells = blockRows.map((row) => _at(row, cols.departTime)).join('\n');

    return TransportRoute(
      semester: semester,
      scheduleType: type,
      routeNo: routeNo.replaceAll(' ', '').toUpperCase(),
      routeName: routeName,
      stops: _parseStops(details),
      toDscTrips: TransportTimeParser.parseTripColumn(toCells),
      fromDscTrips: TransportTimeParser.parseTripColumn(fromCells),
    );
  }

  static String _at(List<String> row, int col) => (col >= 0 && col < row.length) ? row[col] : '';
  static String _norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

  static bool looksLikeHeader(List<String> row) => _looksLikeHeader(row);
  static bool _looksLikeHeader(List<String> row) {
    final j = row.join(' ').toLowerCase();
    return j.contains('route') && (j.contains('start') || j.contains('departure')) && j.contains('time');
  }

  static int _findHeaderRow(List<List<String>> grid) {
    for (var i = 0; i < grid.length; i++) {
      if (_looksLikeHeader(grid[i])) return i;
    }
    return -1;
  }

  static TransportColumns _resolveColumns(List<String> header) {
    int find(bool Function(String) test) {
      for (var i = 0; i < header.length; i++) {
        if (test(header[i].toLowerCase())) return i;
      }
      return -1;
    }
    final routeNo = find((h) => h.contains('route') && (h.contains('no') || h.contains('number')));
    final startTime = find((h) => h.contains('start') && h.contains('time'));
    final routeName = find((h) => h.contains('route') && h.contains('name'));
    final routeDetails = find((h) => h.contains('route') && h.contains('detail'));
    final departTime = find((h) => h.contains('departure') && h.contains('time'));
    return TransportColumns(
      routeNo: routeNo == -1 ? 0 : routeNo,
      startTime: startTime == -1 ? 1 : startTime,
      routeName: routeName == -1 ? 2 : routeName,
      routeDetails: routeDetails == -1 ? 3 : routeDetails,
      departTime: departTime == -1 ? 4 : departTime,
    );
  }

  static ScheduleType? _sectionOf(String joined, String? fillHex) {
    final s = joined.toLowerCase();
    if (s.contains('shuttle')) return ScheduleType.shuttle;
    if (s.contains('friday')) return ScheduleType.friday;
    if (_norm(joined).isEmpty && fillHex != null) {
      if (_isOrange(fillHex)) return ScheduleType.shuttle;
      if (_isYellow(fillHex)) return ScheduleType.friday;
    }
    return null;
  }

  static (int, int, int) _rgb(String hex) {
    final h = hex.length >= 6 ? hex.substring(hex.length - 6) : hex.padLeft(6, '0');
    return (
      int.tryParse(h.substring(0, 2), radix: 16) ?? 0,
      int.tryParse(h.substring(2, 4), radix: 16) ?? 0,
      int.tryParse(h.substring(4, 6), radix: 16) ?? 0,
    );
  }

  static bool _isOrange(String hex) { final (r, g, b) = _rgb(hex); return r > 200 && g > 120 && g < 200 && b < 120; }
  static bool _isYellow(String hex) { final (r, g, b) = _rgb(hex); return r > 200 && g > 200 && b < 150; }

  static String _extractSemester(List<List<String>> grid) {
    for (final row in grid.take(8)) {
      for (final cell in row) {
        final m = RegExp(r'semester\s*:?\s*(.+)', caseSensitive: false).firstMatch(cell);
        if (m != null) { final v = _norm(m.group(1)!); if (v.isNotEmpty) return v; }
      }
    }
    return 'Unknown';
  }

  static String? _extractCampus(List<List<String>> grid) {
    for (final row in grid.take(8)) {
      for (final cell in row) {
        final m = RegExp(r'@\s*([A-Za-z ]{2,})').firstMatch(cell);
        if (m != null) return _norm(m.group(1)!);
      }
    }
    return null;
  }

  static bool _isRouteToken(String s) =>
      RegExp(r'^[RF]\s*\d{1,3}$', caseSensitive: false).hasMatch(s.replaceAll(' ', ''));

  static List<String> _parseStops(String details) {
    if (details.trim().isEmpty) return const [];
    final parts = details.split(RegExp(r'\s*<?>\s*')).map(_norm).where((p) => p.isNotEmpty).toList();
    final stops = <String>[];
    for (final p in parts) {
      final canon = _isDsc(p) ? kCanonicalDestination : p;
      if (stops.isNotEmpty && _isDsc(stops.last) && _isDsc(canon)) continue;
      stops.add(canon);
    }
    return stops;
  }

  static bool _isDsc(String s) {
    final t = s.toLowerCase().replaceAll(RegExp(r'[^a-z ]'), '').trim();
    return t == 'dsc' || t == 'daffodil smart city';
  }
}

class TransportColumns {
  final int routeNo, startTime, routeName, routeDetails, departTime;
  const TransportColumns({
    required this.routeNo,
    required this.startTime,
    required this.routeName,
    required this.routeDetails,
    required this.departTime,
  });
}
