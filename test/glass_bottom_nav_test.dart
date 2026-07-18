import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/shared/widgets/glass_bottom_nav.dart';

/// Regression guard for the blob/label overlap fix: the floating bottom nav
/// must lay out its 4 items at a real phone width with no RenderFlex overflow,
/// and every label must render (the label sits in its own zone below the blob).
void main() {
  const dests = [
    BottomNavDest(label: 'Home', icon: Icons.home_outlined, route: '/home'),
    BottomNavDest(label: 'Search', icon: Icons.search_rounded, route: '/search'),
    BottomNavDest(label: 'Profile', icon: Icons.person_outline_rounded, route: '/profile'),
    BottomNavDest(label: 'Settings', icon: Icons.settings_outlined, route: '/settings'),
  ];

  Future<void> pumpAt(WidgetTester tester, Size size, int index) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: GlassBottomNav(destinations: dests, currentIndex: index, onTap: (_) {}),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders 4 items with no overflow at a narrow phone width', (tester) async {
    await pumpAt(tester, const Size(360, 780), 0); // small Android width
    expect(tester.takeException(), isNull);
    for (final d in dests) {
      expect(find.text(d.label), findsOneWidget);
    }
  });

  testWidgets('no overflow at a typical phone width with a mid item active', (tester) async {
    await pumpAt(tester, const Size(414, 896), 2); // Profile active
    expect(tester.takeException(), isNull);
    expect(find.text('Profile'), findsOneWidget);
  });
}
