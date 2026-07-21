import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/config/theme/app_colors.dart';
import 'package:afos_v7/shared/widgets/afos_button.dart';
import 'package:afos_v7/shared/widgets/empty_state.dart';
import 'package:afos_v7/shared/widgets/error_view.dart';
import 'package:afos_v7/shared/widgets/feature_header.dart';
import 'package:afos_v7/shared/widgets/glass_chip.dart';
import 'package:afos_v7/shared/widgets/glass_tab_bar.dart';
import 'package:afos_v7/shared/widgets/info_card.dart';
import 'package:afos_v7/shared/widgets/label_value_row.dart';
import 'package:afos_v7/shared/widgets/logout_tile.dart';
import 'package:afos_v7/shared/widgets/pill_badge.dart';
import 'package:afos_v7/shared/widgets/sheet_header.dart';
import 'package:afos_v7/shared/widgets/stat_tile.dart';

/// Layout guard: every shared building block must survive the real range of
/// devices AND accessibility text sizes without a RenderFlex overflow.
///
/// Overflow is what "icons in weird positions / things not visible" actually is
/// at the framework level: a Row or Column asked for more space than it was
/// given, so children get clipped or shoved off-screen.
///
/// Two things this harness does deliberately:
///  * It uses LONG, realistic labels. Overflow almost never reproduces with
///    "Test" — it reproduces with 'Cancel Requested (12)' at 1.6x text scale on
///    a 320dp phone. Short placeholder strings are why layout tests pass while
///    the real app breaks.
///  * It taps FlutterError.onError rather than relying on takeException() alone.
///    This project already learned that lesson: takeException() surfaces only
///    the first error and misattributes which widget caused it.
void main() {
  // Real devices, smallest first. 320 is the narrowest Android still in use
  // and is where fixed-width children start colliding.
  const sizes = <String, Size>{
    '320x568 (small Android)': Size(320, 568),
    '360x780 (common Android)': Size(360, 780),
    '390x844 (iPhone)': Size(390, 844),
    '412x915 (large Android)': Size(412, 915),
    '600x1024 (tablet)': Size(600, 1024),
    '1024x1366 (tablet landscape)': Size(1024, 1366),
  };

  // 1.0 default, 1.3 the usual Android "large", 1.6 a realistic accessibility
  // setting. Anything that survives 1.6 will survive the sliders users actually
  // touch.
  const scales = <double>[1.0, 1.3, 1.6];

  Future<List<String>> overflowsFor(
      WidgetTester tester, Widget child, Size size, double scale) async {
    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('overflowed')) errors.add(text.split('\n').first);
    };

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Align(alignment: Alignment.topCenter, child: child),
        ),
      ),
    ));
    // Not pumpAndSettle: several of these run indefinite shimmer/pulse
    // animations and would never settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    FlutterError.onError = previous;
    return errors;
  }

  /// Long-but-real content. These strings are taken from what the app actually
  /// renders (admin filter chips, hall statuses, transport route names).
  final cases = <String, Widget Function()>{
    'AfosButton (long label)': () => const AfosButton(
        label: 'Confirm Approval and Notify Student', icon: Icons.check),
    'EmptyState': () => const EmptyState(
        icon: Icons.how_to_reg_outlined,
        title: 'No pending approvals',
        subtitle:
            'New signups awaiting super-admin review will appear here as soon as they register.',
        actionLabel: 'Refresh'),
    'ErrorView': () => const ErrorView(
        message:
            'Could not reach the server. Check your connection and try again.'),
    'FeatureHeader (title+subtitle+trailing)': () => const FeatureHeader(
        title: 'Conference Room Requests',
        subtitle: 'Review, assign a room, or decline pending bookings',
        icon: Icons.meeting_room_rounded,
        trailing: PillBadge(label: 'SUPER ADMIN', color: AppColors.holoviolet)),
    'GlassChip (long, selected)': () =>
        const GlassChip(label: 'Cancel Requested (12)', selected: true, icon: Icons.filter_alt),
    'GlassTabBar (2 tabs)': () => GlassTabBar(
        tabs: const [GlassTab('Applications'), GlassTab('Complaints')],
        currentIndex: 0,
        onChanged: (_) {}),
    'GlassTabBar (3 tabs, counts)': () => GlassTabBar(
        tabs: const [
          GlassTab('All Users', icon: Icons.people_alt_rounded),
          GlassTab('Pending (12)', icon: Icons.how_to_reg_rounded),
          GlassTab('CR Requests (7)', icon: Icons.badge_rounded),
        ],
        currentIndex: 1,
        onChanged: (_) {}),
    'GlassTabBar (5 tabs)': () => GlassTabBar(
        tabs: const [
          GlassTab('Pending'), GlassTab('Reviewing'), GlassTab('Approved'),
          GlassTab('Rejected'), GlassTab('Cancelled'),
        ],
        currentIndex: 0,
        onChanged: (_) {}),
    'InfoCard (title+subtitle+trailing)': () => const InfoCard(
        icon: Icons.directions_bus_rounded,
        title: 'Route 4 — ECB Chattor › Daffodil Smart City',
        subtitle: 'Departs 7:00 AM and 10:00 AM from the first stop',
        trailing: PillBadge(label: 'REGULAR', color: AppColors.green)),
    'LabelValueRow (long value)': () => const LabelValueRow(
        label: 'Emergency contact',
        value: '+880 1712-345678 (guardian, available after 6pm)',
        icon: Icons.phone_rounded),
    'LogoutTile': () => LogoutTile(onTap: () {}),
    'SheetHeader (with trailing)': () => const SheetHeader(
        title: 'Change role for this account',
        subtitle: 'Super admin only — this takes effect immediately',
        trailing: PillBadge(label: 'DANGER', color: AppColors.red)),
    'StatTile (long label)': () => const StatTile(
        value: '1632', label: 'Exam room allocations', icon: Icons.event_seat_rounded),
    'Row of 3 StatTiles (admin summary bar)': () => const Row(children: [
          Expanded(child: StatTile(value: '12', label: 'Pending')),
          Expanded(child: StatTile(value: '148', label: 'Approved')),
          Expanded(child: StatTile(value: '3', label: 'Cancel Requested')),
        ]),
    // Deliberately a horizontally-scrolling ListView, NOT a Row -- that is how
    // manage_hall_screen actually lays its status filters out. An earlier
    // version of this case used a bare Row and "failed" by 310px, which was the
    // TEST being wrong about the app, not a bug. Kept as a guard so nobody
    // later converts this strip to a Row without noticing.
    'Filter chip strip (hall statuses, horizontal scroll)': () => SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: const [
              Padding(padding: EdgeInsets.only(right: 8), child: Center(child: GlassChip(label: 'Pending'))),
              Padding(padding: EdgeInsets.only(right: 8), child: Center(child: GlassChip(label: 'Reviewing'))),
              Padding(padding: EdgeInsets.only(right: 8), child: Center(child: GlassChip(label: 'Cancel Requested'))),
              Padding(padding: EdgeInsets.only(right: 8), child: Center(child: GlassChip(label: 'Approved'))),
            ],
          ),
        ),
  };

  for (final entry in cases.entries) {
    testWidgets('no overflow: ${entry.key}', (tester) async {
      final failures = <String>[];
      for (final size in sizes.entries) {
        for (final scale in scales) {
          final errors =
              await overflowsFor(tester, entry.value(), size.value, scale);
          for (final e in errors) {
            failures.add('${size.key} @ ${scale}x -> $e');
          }
        }
      }
      expect(failures, isEmpty,
          reason: '${entry.key} overflowed:\n${failures.join('\n')}');
    });
  }
}
