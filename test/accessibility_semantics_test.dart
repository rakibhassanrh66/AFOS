import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/core/haptics/app_haptics.dart';
import 'package:afos_v7/shared/widgets/afos_button.dart';
import 'package:afos_v7/shared/widgets/glass_card.dart';
import 'package:afos_v7/shared/widgets/pressable.dart';
import 'package:afos_v7/shared/widgets/stat_tile.dart';

/// The app's interactive surfaces must announce themselves as CONTROLS.
///
/// WHAT THIS LOCKS DOWN. A sweep of this codebase found **three**
/// `Semantics`/`semanticLabel` declarations across 250 files and 62 screens.
/// That is not a styling gap: `AfosButton`, `GlassCard` and `Pressable` are all
/// built on a raw `GestureDetector`, which contributes a tap ACTION to the
/// semantics tree but never the button ROLE. So TalkBack read the app's most
/// common controls — the primary CTA on nearly every screen, every card that
/// navigates, every chip — as ordinary text that happened to respond to a tap.
/// Someone driving AFOS by ear could reach them and could even activate them,
/// but was never told they were there.
///
/// WHY A SEMANTICS TEST AND NOT A VISUAL ONE. None of this has any visual
/// signature at all. `flutter analyze` sees nothing, every layout probe in this
/// suite passes, and the app looks identical with and without it. The
/// semantics tree is the only place the difference exists, so it is the only
/// place it can be asserted.
///
/// These drive the REAL widgets, never copies — a copied widget cannot regress.
void main() {
  setUp(() {
    // These assert roles, not textures. Leaving haptics on would schedule
    // AppHaptics' 60ms coalescing timer on every tap and fail the tests on a
    // pending timer instead of on what they are about.
    AppHaptics.enabled.value = false;
    AppHaptics.reset();
  });
  tearDown(() => AppHaptics.enabled.value = true);

  Future<void> pump(WidgetTester t, Widget child) => t.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: child))),
      );

  group('AfosButton', () {
    testWidgets('is announced as a button, by its own label', (t) async {
      final handle = t.ensureSemantics();
      await pump(t, AfosButton(label: 'Submit result', onTap: () {}));

      // Asserted on the widget's own node, not via bySemanticsLabel: the
      // label ANNOTATES the subtree rather than creating a node of its own, so
      // the merged node is the thing a screen reader actually reaches.
      //
      // The label is asserted EXACTLY, not just for presence. The first
      // version of this widget's fix declared the label on the Semantics AND
      // left the child Text carrying it, and the two merged into
      // one merged label that says the name twice. Only an exact match
      // catches that.
      expect(
        t.getSemantics(find.byType(AfosButton)),
        isSemantics(label: 'Submit result', isButton: true, isEnabled: true),
        reason: 'a GestureDetector gives the action but not the role',
      );
      handle.dispose();
    });

    testWidgets('a loading button announces itself as unavailable', (t) async {
      final handle = t.ensureSemantics();
      // Deliberately still passing onTap: `loading` alone is what makes the
      // button inert, and a button that silently ignores activation is the
      // exact failure this flag prevents.
      //
      // The label matters MORE here than in the enabled case: a loading button
      // renders a spinner and no text, so if the widget did not supply a name
      // itself this would announce as an unnamed disabled control.
      await pump(t, AfosButton(label: 'Saving', loading: true, onTap: () {}));

      expect(
        t.getSemantics(find.byType(AfosButton)),
        isSemantics(label: 'Saving', isButton: true, isEnabled: false),
      );
      handle.dispose();
    });
  });

  group('GlassCard', () {
    testWidgets('a tappable card is a button; a plain one is not', (t) async {
      final handle = t.ensureSemantics();

      await pump(t, GlassCard(onTap: () {}, child: const Text('Transport')));
      expect(t.getSemantics(find.text('Transport')),
          isSemantics(isButton: true));

      // The other half of the rule. A card that does nothing must NOT claim to
      // be a control, or every static surface in the app becomes noise to
      // someone navigating by role.
      await pump(t, const GlassCard(child: Text('Read only')));
      expect(t.getSemantics(find.text('Read only')),
          isSemantics(isButton: false));
      handle.dispose();
    });
  });

  group('Pressable', () {
    testWidgets('carries the role to everything built on it', (t) async {
      final handle = t.ensureSemantics();
      await pump(t, Pressable(onTap: () {}, child: const Text('Filter')));

      expect(t.getSemantics(find.text('Filter')),
          isSemantics(isButton: true));
      handle.dispose();
    });

    testWidgets('an inert Pressable is not announced as enabled', (t) async {
      final handle = t.ensureSemantics();
      await pump(t, const Pressable(child: Text('Just a surface')));

      expect(t.getSemantics(find.text('Just a surface')),
          isSemantics(isEnabled: false));
      handle.dispose();
    });
  });

  group('StatTile', () {
    testWidgets('the tappable variant clears the 48dp touch floor', (t) async {
      await pump(
        t,
        SizedBox(
          width: 120,
          child: StatTile(value: 1284, label: 'Total users', onTap: () {}),
        ),
      );

      // The constitution's floor. These tiles are centred content in an
      // Expanded and come out ~20dp tall on their own, which is well under it
      // and sits in a row of three — the shape most likely to be mis-tapped.
      expect(t.getSize(find.byType(InkWell)).height,
          greaterThanOrEqualTo(48.0));
    });

    testWidgets('a readout tile offers no control at all', (t) async {
      await pump(t, const StatTile(value: 12, label: 'Pending'));
      expect(find.byType(InkWell), findsNothing,
          reason: 'a number with no destination is not a button');
    });
  });
}
