import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/shared/widgets/glass_bottom_nav.dart';

/// Guards the floating "planet" bottom nav: the bar must lay out its 4 items at
/// real phone widths with no RenderFlex overflow, must park the planet on Home
/// for screens that aren't tabs, and — the subtle one — its gravity-valley path
/// must stay geometrically well-formed at every tab position and width.
void main() {
  const dests = [
    BottomNavDest(label: 'Home', icon: Icons.home_outlined, route: '/home'),
    BottomNavDest(label: 'Search', icon: Icons.search_rounded, route: '/search'),
    BottomNavDest(label: 'Profile', icon: Icons.person_outline_rounded, route: '/profile'),
    BottomNavDest(label: 'Settings', icon: Icons.settings_outlined, route: '/settings'),
  ];

  Future<void> pumpAt(WidgetTester tester, Size size, int index, {double textScale = 1.0}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: GlassBottomNav(destinations: dests, currentIndex: index, onTap: (_) {}),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('layout', () {
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

    testWidgets('no overflow at a very small width', (tester) async {
      await pumpAt(tester, const Size(320, 640), 3); // Settings active, tiny screen
      expect(tester.takeException(), isNull);
    });

    testWidgets('no overflow at 2x accessibility text scale', (tester) async {
      // Labels are clamped inside the widget so a large system font can't push
      // the fixed-height bar into a RenderFlex overflow.
      await pumpAt(tester, const Size(360, 780), 1, textScale: 2.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('off-tab route (-1) parks the planet on Home and still renders', (tester) async {
      await pumpAt(tester, const Size(390, 844), -1); // e.g. on /schedule
      expect(tester.takeException(), isNull);
      for (final d in dests) {
        expect(find.text(d.label), findsOneWidget);
      }
    });
  });

  group('gravity-valley geometry', () {
    const widths = <double>[320, 360, 390, 414, 480, 600, 768, 1024];
    const sideMargin = GlassBottomNav.sideMargin;

    test('valley x-coordinates stay non-decreasing for every tab at every width', () {
      for (final screenW in widths) {
        final barW = screenW - sideMargin * 2;
        final seg = barW / dests.length;
        for (var i = 0; i < dests.length; i++) {
          final xs = navValleyXs(barW, seg * i + seg / 2);
          for (var k = 1; k < xs.length; k++) {
            expect(xs[k], greaterThanOrEqualTo(xs[k - 1] - 0.001),
                reason: 'width $screenW, tab $i: x[$k] ran backwards past x[${k - 1}]');
          }
        }
      }
    });

    // THE regression guard for the reported bug: "middle two spin fine, both
    // side edges only go half and stick." The old code clamped the valley's
    // shoulders into the corner arc, so on a 360dp phone tab 0 got a 6px left
    // span against a 55px right span — a lopsided sliver instead of a dip. The
    // valley is now a FIXED symmetric shape around the planet at every tab, and
    // is cropped by intersection rather than deformed.
    test('valley is perfectly symmetric on EVERY tab, including the edges', () {
      for (final screenW in widths) {
        final barW = screenW - sideMargin * 2;
        final seg = barW / dests.length;
        for (var i = 0; i < dests.length; i++) {
          final centre = seg * i + seg / 2;
          final xs = navValleyXs(barW, centre);
          final leftSpan = centre - xs[0];
          final rightSpan = xs[6] - centre;
          expect(leftSpan, closeTo(rightSpan, 0.001),
              reason: 'width $screenW, tab $i: left span $leftSpan != right span '
                  '$rightSpan — the dip is lopsided, which is what made the first '
                  'and last tab look half-formed');
          expect(leftSpan, closeTo(55, 0.001),
              reason: 'width $screenW, tab $i: dip narrowed to $leftSpan');
        }
      }
    });

    test('valley keeps the reference control-point offsets', () {
      // Reference: shoulders at +/-55, outer controls +/-35, inner +/-32.
      final xs = navValleyXs(400, 200);
      expect(xs[0], closeTo(145, 0.01));
      expect(xs[1], closeTo(165, 0.01));
      expect(xs[2], closeTo(168, 0.01));
      expect(xs[3], closeTo(200, 0.01));
      expect(xs[4], closeTo(232, 0.01));
      expect(xs[5], closeTo(235, 0.01));
      expect(xs[6], closeTo(255, 0.01));
    });

    test('painted path never escapes the bar, even when the dip overhangs', () {
      // The dip is drawn unclamped and may run past the slab; the intersection
      // in buildNavBarPath is what must keep the RESULT in bounds.
      for (final screenW in widths) {
        final barW = screenW - sideMargin * 2;
        final size = Size(barW, GlassBottomNav.barHeight);
        for (final centre in [0.0, barW * 0.12, barW / 2, barW * 0.88, barW]) {
          final b = buildNavBarPath(size, centre).getBounds();
          expect(b.left, greaterThanOrEqualTo(-0.5), reason: 'width $screenW, centre $centre');
          expect(b.right, lessThanOrEqualTo(barW + 0.5), reason: 'width $screenW, centre $centre');
          expect(b.bottom, lessThanOrEqualTo(GlassBottomNav.barHeight + 0.5));
        }
      }
    });

    test('every tab actually carves a dip of full depth', () {
      // Proves the dent forms at the EDGE tabs too: a point just above the
      // valley floor at the planet's centre must be carved away, while a point
      // below it stays solid. Under the old clamping the edge tabs failed this.
      const size = Size(328, GlassBottomNav.barHeight);
      for (final centre in [41.0, 123.0, 205.0, 287.0]) {
        final path = buildNavBarPath(size, centre);
        expect(path.contains(Offset(centre, 34)), isFalse,
            reason: 'tab at $centre: no dip carved above the valley floor');
        expect(path.contains(Offset(centre, 50)), isTrue,
            reason: 'tab at $centre: surface missing below the valley floor');
      }
    });

    test('buildNavBarPath yields a closed, non-empty shape at every tab', () {
      const size = Size(328, GlassBottomNav.barHeight);
      for (final centre in [41.0, 123.0, 205.0, 287.0]) {
        final path = buildNavBarPath(size, centre);
        final bounds = path.getBounds();
        expect(bounds.width, greaterThan(300));
        expect(bounds.height, closeTo(GlassBottomNav.barHeight, 1));
        expect(path.contains(Offset(centre, GlassBottomNav.barHeight - 8)), isTrue);
      }
    });
  });
}
