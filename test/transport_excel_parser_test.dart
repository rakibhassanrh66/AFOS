import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/features/transport/data/transport_excel_parser.dart';
import 'package:afos_v7/features/transport/data/models/transport_schedule.dart';

/// Regression guard for BUG 2: the real DIU "Summer-2026" transport sheet is a
/// Google-Sheets export that makes the `excel` package throw
/// "Null check operator used on a null value" in its own cell parser. The
/// parser must fall back to spreadsheet_decoder and read it end-to-end.
void main() {
  test('parses the real DIU Summer-2026 xlsx via the spreadsheet_decoder fallback', () {
    final bytes = File('test/fixtures/transport_summer2026.xlsx').readAsBytesSync();
    final parsed = TransportExcelParser.parse(bytes);

    expect(parsed.semester, 'Summer-2026');
    // 10 Regular + 6 Shuttle + 4 Friday = 21 routes in this sheet.
    expect(parsed.routes.length, 21);

    // All three sections were detected.
    final types = parsed.routes.map((r) => r.scheduleType).toSet();
    expect(types, containsAll([ScheduleType.regular, ScheduleType.shuttle, ScheduleType.friday]));

    // R1 is fully populated: stops (places) + times both directions, and its
    // day-fraction time cells decoded to real times.
    final r1 = parsed.routes.firstWhere((r) => r.routeNo == 'R1');
    expect(r1.stops, isNotEmpty);
    expect(r1.stops.last, 'Daffodil Smart City');
    expect(r1.toDscTrips.where((t) => !t.isEmpty).map((t) => t.time), contains('7:00 AM'));
    expect(r1.fromDscTrips.where((t) => !t.isEmpty).map((t) => t.time), contains('4:20 PM'));
  });
}
