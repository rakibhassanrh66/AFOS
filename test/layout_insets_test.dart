import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/config/theme/dark_theme.dart';
import 'package:afos_v7/core/layout/nav_insets.dart';
import 'package:afos_v7/shared/widgets/glass_bottom_nav.dart';
import 'package:afos_v7/shared/widgets/glass_sheet.dart';

/// Guards the two inset/sheet bugs that produced the "UI is broken everywhere"
/// report, both of which are invisible to `flutter analyze` and to a static
/// read of the widget tree.
void main() {
  group('GlassSheet survives the keyboard', () {
    testWidgets('does not rebuild its subtree from scratch when the keyboard opens',
        (tester) async {
      // THE REGRESSION. GlassSheet used to pick between `Padding(child: body)`
      // and a bare `body` depending on whether the keyboard was open. Those are
      // different widget TYPES in the same slot, so Widget.canUpdate returned
      // false and Flutter threw away the entire sheet subtree and inflated a
      // new one — disposing every FocusNode and TextEditingController inside
      // it. In the app that meant tapping the course-code search field opened
      // the keyboard, the rebuild killed the focused node, and the keyboard
      // immediately closed again ("the keyboard doesn't rise"), taking any
      // typed text with it.
      //
      // Asserting on State identity rather than on rendering, because the
      // symptom IS the loss of State.
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      Widget app(double keyboardInset) => MaterialApp(
            theme: buildDarkTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                  viewInsets: EdgeInsets.only(bottom: keyboardInset)),
              child: Material(
                child: GlassSheet(
                  child: TextField(controller: controller),
                ),
              ),
            ),
          );

      await tester.pumpWidget(app(0));
      await tester.enterText(find.byType(TextField), 'CSE431');
      final stateBefore = tester.state(find.byType(TextField));

      // Keyboard opens.
      await tester.pumpWidget(app(300));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.state(find.byType(TextField)), same(stateBefore),
          reason: 'the sheet subtree was re-inflated, so every FocusNode and '
              'TextEditingController inside it was disposed');
      expect(controller.text, 'CSE431',
          reason: 'typed text must survive the keyboard opening');

      // ...and closing again, which used to be a second teardown.
      await tester.pumpWidget(app(0));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.state(find.byType(TextField)), same(stateBefore));
      expect(controller.text, 'CSE431');
    });

    testWidgets('still lifts its content clear of the keyboard', (tester) async {
      // The fix must not silently drop the lift it was there to provide.
      Widget app(double keyboardInset) => MaterialApp(
            theme: buildDarkTheme(),
            home: MediaQuery(
              data: MediaQueryData(
                  viewInsets: EdgeInsets.only(bottom: keyboardInset)),
              child: const Material(child: GlassSheet(child: Text('body'))),
            ),
          );

      await tester.pumpWidget(app(0));
      final restingBottom = tester.getBottomLeft(find.text('body')).dy;

      await tester.pumpWidget(app(300));
      await tester.pumpAndSettle();
      final liftedBottom = tester.getBottomLeft(find.text('body')).dy;

      expect(liftedBottom, lessThan(restingBottom),
          reason: 'content should move up by roughly the keyboard height');
    });
  });

  group('NavInsets', () {
    testWidgets('reads the clearance AppShell injected, and nothing else',
        (tester) async {
      // The whole point of the refactor: one source of truth. A screen asks
      // NavInsets, NavInsets asks MediaQuery, and AppShell is the only thing
      // that ever writes it. There is deliberately no compile-time constant to
      // hard-code any more.
      late EdgeInsets plain;
      late EdgeInsets withFab;
      late double raw;

      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(padding: EdgeInsets.only(bottom: 131)),
          child: Builder(builder: (context) {
            raw = NavInsets.of(context);
            plain = NavInsets.content(context);
            withFab = NavInsets.content(context, fab: true);
            return const SizedBox();
          }),
        ),
      ));

      expect(raw, 131);
      // bottom gap (16) + the injected inset — counted exactly once.
      expect(plain.bottom, 16 + 131);
      expect(plain.left, 16);
      expect(plain.top, 16);
      expect(withFab.bottom, 16 + 131 + NavInsets.fabClearance);
    });

    testWidgets('is zero outside the shell (auth routes, desktop rail)',
        (tester) async {
      late double inset;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(),
          child: Builder(builder: (context) {
            inset = NavInsets.of(context);
            return const SizedBox();
          }),
        ),
      ));
      expect(inset, 0);
    });
  });

  test('content clearance covers the bar surface but not the floating planet', () {
    // Reserving the planet's lift across the full screen width is what left a
    // dead band with nothing behind the frost, making the BackdropFilter paint
    // as an opaque slab. Content clears the surface; the planet overlaps it.
    expect(GlassBottomNav.contentClearance,
        GlassBottomNav.barHeight + GlassBottomNav.bottomMargin + 8);
    expect(GlassBottomNav.contentClearance,
        lessThan(GlassBottomNav.barHeight +
            GlassBottomNav.bottomMargin +
            GlassBottomNav.planetLift));
  });
}
