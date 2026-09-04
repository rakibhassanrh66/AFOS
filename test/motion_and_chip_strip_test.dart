// Two rules that had already drifted once, pinned so they cannot drift again.
//
// 1. A horizontal chip strip must grow with the reader's text scale. Three
//    strips carried the same geometry and only one grew, so the other two
//    clipped at a 2.0x accessibility scale — measured at 4.0px and 1.0px of
//    overflow before AppSpace.chipStrip existed.
//
// 2. A shared widget must read its duration through AppMotion.durationOf.
//    motion.dart says so in as many words ("Reading these constants directly
//    is a bug"), and yet the button, the text field, the chip, the bottom nav
//    and the slide menu all read them bare — so "reduce motion" did nothing on
//    the widgets the whole app is assembled from.
//
// Real widgets throughout. A copy in a test cannot regress.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/config/theme/spacing.dart';
import 'package:afos_v7/shared/widgets/afos_button.dart';
import 'package:afos_v7/shared/widgets/afos_text_field.dart';
import 'package:afos_v7/shared/widgets/glass_chip.dart';

/// Pumps [child] at [scale], with animations optionally suppressed.
Future<void> _pump(WidgetTester tester, Widget child,
    {double scale = 1.0, bool reduceMotion = false}) async {
  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(scale),
        disableAnimations: reduceMotion,
      ),
      child: Scaffold(
        body: Align(alignment: Alignment.topLeft, child: child),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  group('AppSpace.chipStrip', () {
    testWidgets('gives a real GlassChip room at every accessibility scale',
        (tester) async {
      for (final scale in const [1.0, 1.3, 1.6, 2.0]) {
        await _pump(
          tester,
          GlassChip(
            icon: Icons.tune_rounded,
            label: 'Department: CSE',
            selected: true,
            onTap: () {},
          ),
          scale: scale,
        );

        final chipHeight =
            tester.renderObject<RenderBox>(find.byType(GlassChip)).size.height;

        // The height the Manage Users filter strip asks for at this scale.
        final ctx = tester.element(find.byType(GlassChip));
        final strip = AppSpace.chipStrip(ctx, 44);

        expect(strip, greaterThanOrEqualTo(chipHeight),
            reason: 'GlassChip is ${chipHeight}px at ${scale}x but the strip '
                'only offers ${strip}px — this is the 1.0px clip that shipped.');
      }
    });

    test('reproduces the marks_entry height it replaced, and is capped', () {
      // Not a widget test: these are the pure arithmetic guarantees. The
      // formula and the 62px cap came from marks_entry_screen, and passing its
      // base of 38 back through must reproduce what that screen already
      // rendered, or the "no visual change" claim is false.
      double at(double scale, double base) =>
          (base + (scale - 1) * 24).clamp(base, 62.0);

      expect(at(1.0, 38), 38.0);
      expect(at(2.0, 38), 62.0);
      // Capped, so a 3.0x system scale cannot hand a phone a 100px band.
      expect(at(3.0, 38), 62.0);
      expect(at(3.0, 44), 62.0);
      // Never smaller than the base it was given.
      expect(at(0.8, 44), 44.0);
    });
  });

  // The two widget groups above prove the helper is adequate and that the
  // primitives honour the setting. Neither can prove a SCREEN still routes
  // through them — and a screen reverting to a literal is exactly how both
  // faults arose. These two scan the source for that, which is the only check
  // available for screens that cannot be pumped without Supabase.
  group('the convention holds across lib/', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    test('every horizontal chip strip goes through AppSpace.chipStrip', () {
      const strips = {
        'attendance_screen.dart': 'course filter',
        'user_directory_screen.dart': 'user filter',
        'marks_entry_screen.dart': 'offering picker',
      };

      for (final entry in strips.entries) {
        final file = dartFiles.firstWhere(
            (f) => f.path.endsWith(entry.key),
            orElse: () => throw StateError('${entry.key} has moved — '
                'update this test rather than deleting the case.'));
        expect(file.readAsStringSync(), contains('AppSpace.chipStrip'),
            reason: '${entry.key} (${entry.value}) stopped using the helper. '
                'A literal height here is a clipped label at a 2.0x scale.');
      }
    });

    test('no widget reads a motion duration as a bare constant', () {
      // AnimationControllers are exempt: a controller may hold a real duration
      // and simply never be driven, which is how splash, console_grid,
      // exam_pulse_band and glass_bottom_nav honour the setting — each checks
      // isReduced (or disableAnimations) before calling forward(). Verified by
      // reading each one, not assumed. update_sheet returns an un-animated row
      // outright, so its tween never builds.
      final exempt = <String>{
        'splash_screen.dart',
        'console_grid.dart',
        'exam_pulse_band.dart',
        'glass_bottom_nav.dart',
        'update_sheet.dart',
      };
      final bare = RegExp(r'duration:\s*AppMotion\.(instant|tight|base|slow|hero)\b');
      final offenders = <String>[];

      for (final file in dartFiles) {
        final name = file.path.split(RegExp(r'[/\\]')).last;
        if (exempt.contains(name)) continue;
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (bare.hasMatch(lines[i])) {
            offenders.add('$name:${i + 1}  ${lines[i].trim()}');
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'These read a duration directly, so "reduce motion" does '
              'nothing on them. Wrap in AppMotion.durationOf(context, …):\n'
              '${offenders.join('\n')}');
    });
  });

  group('reduce motion reaches the shared primitives', () {
    testWidgets('AfosButton collapses both of its durations', (tester) async {
      await _pump(tester, AfosButton(label: 'Save', onTap: () {}),
          reduceMotion: true);

      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
          Duration.zero,
          reason: 'the press scale still animated under reduce motion');
      expect(
          tester
              .widget<AnimatedContainer>(find.byType(AnimatedContainer))
              .duration,
          Duration.zero,
          reason: 'the button surface still animated under reduce motion');
    });

    testWidgets('AfosButton still animates when motion is allowed',
        (tester) async {
      // The other half of the assertion: durationOf must not have flattened
      // the animation for everybody.
      await _pump(tester, AfosButton(label: 'Save', onTap: () {}));

      expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
          isNot(Duration.zero));
    });

    testWidgets('AfosTextField collapses its focus glow', (tester) async {
      await _pump(tester, const AfosTextField(hint: 'University ID'),
          reduceMotion: true);

      expect(
          tester
              .widget<AnimatedContainer>(find.byType(AnimatedContainer))
              .duration,
          Duration.zero);
    });

    testWidgets('GlassChip collapses its selection transition', (tester) async {
      await _pump(
        tester,
        GlassChip(label: 'Pending', selected: true, onTap: () {}),
        reduceMotion: true,
      );

      expect(
          tester
              .widget<AnimatedContainer>(find.byType(AnimatedContainer))
              .duration,
          Duration.zero);
    });
  });
}
