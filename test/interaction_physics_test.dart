import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/config/theme/motion.dart';
import 'package:afos_v7/core/haptics/app_haptics.dart';
import 'package:afos_v7/shared/widgets/pressable.dart';

/// Phase 4 — the interaction rules, as executable checks.
///
/// These assert BEHAVIOUR a human would otherwise have to feel for, and which
/// no other test in this project covers: that a touch is answered before the
/// handler runs, that the answer does not overshoot, and that one gesture
/// produces one haptic rather than two.
void main() {
  /// Captures platform haptic calls. `HapticFeedback` goes out over the
  /// platform channel, so intercepting the channel is the only way to see what
  /// the hand would actually feel.
  List<String> tapHaptics(WidgetTester tester) {
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') calls.add('${call.arguments}');
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    return calls;
  }

  setUp(AppHaptics.reset);

  group('Law 4 — a gesture answers before the handler does', () {
    testWidgets('press-down scales to 0.97 and starts within one frame',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              onTap: () {},
              haptic: false,
              child: const SizedBox(width: 200, height: 60),
            ),
          ),
        ),
      ));

      double currentScale() => tester
          .widget<AnimatedScale>(find.byType(AnimatedScale))
          .scale;

      expect(currentScale(), 1.0, reason: 'resting');

      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(Pressable)));
      // ONE frame. The visual target must already be 0.97 — not queued behind
      // navigation, not waiting on the handler.
      await tester.pump();
      expect(currentScale(), AppMotion.pressScale,
          reason: 'press state must be committed within a single frame');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(currentScale(), 1.0, reason: 'released');
    });

    testWidgets('the release never overshoots its resting size',
        (tester) async {
      // A control that springs past 1.0 under the finger reads as unstable.
      // AppMotion.standard must therefore stay overshoot-free — unlike
      // AppMotion.emphasis, which exists precisely to overshoot and is
      // documented as not for press feedback.
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        expect(AppMotion.standard.transform(t), lessThanOrEqualTo(1.0),
            reason: 'standard curve overshoots at t=$t');
      }
      expect(AppMotion.emphasis.transform(0.6), greaterThan(1.0),
          reason: 'emphasis is supposed to overshoot; if it stopped, the '
              'confirmation flourish is silently gone');
    });

    testWidgets('a disabled Pressable does not fake a press', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(child: SizedBox(width: 200, height: 60)),
          ),
        ),
      ));
      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(Pressable)));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0,
          reason: 'nothing will happen on release, so nothing should respond');
      await gesture.up();
    });

    testWidgets('reduced motion keeps the press state, only drops the easing',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: Pressable(
                onTap: () {},
                haptic: false,
                child: const SizedBox(width: 200, height: 60),
              ),
            ),
          ),
        ),
      ));
      expect(
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
          Duration.zero,
          reason: '"reduce motion" means do not animate — it does not mean '
              'stop telling me the control was pressed');
    });
  });

  group('haptics fire on commit, once per gesture', () {
    testWidgets('nothing fires on press-down; one fires on release',
        (tester) async {
      final calls = tapHaptics(tester);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              onTap: () {},
              child: const SizedBox(width: 200, height: 60),
            ),
          ),
        ),
      ));

      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(Pressable)));
      await tester.pump();
      expect(calls, isEmpty,
          reason: 'a buzz on touch-down fires even when the finger slides off '
              'to cancel — the phone would confirm something that never '
              'happened');

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 120));
      expect(calls.length, 1);
    });

    testWidgets('sliding off to cancel fires nothing at all', (tester) async {
      final calls = tapHaptics(tester);
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              onTap: () => tapped = true,
              child: const SizedBox(width: 100, height: 60),
            ),
          ),
        ),
      ));

      final gesture = await tester.startGesture(
          tester.getCenter(find.byType(Pressable)));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 400)); // off the control
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 120));

      expect(tapped, isFalse);
      expect(calls, isEmpty);
    });

    testWidgets('two haptics in one gesture collapse to the stronger one',
        (tester) async {
      // The real case: a Pressable reports `selection` because a control
      // committed, and the handler it invoked reports `success` because the
      // save worked. Both are correct; together they are a stutter.
      final calls = tapHaptics(tester);
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Pressable(
              onTap: AppHaptics.success,
              child: SizedBox(width: 200, height: 60),
            ),
          ),
        ),
      ));

      await tester.tap(find.byType(Pressable));
      await tester.pump(const Duration(milliseconds: 120));

      expect(calls.length, 1, reason: 'one gesture, one haptic');
      expect(calls.single, contains('mediumImpact'),
          reason: 'success outranks selection — the stronger meaning wins');
    });

    testWidgets('a refusal outranks a success', (tester) async {
      final calls = tapHaptics(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      AppHaptics.success();
      AppHaptics.warning();
      await tester.pump(const Duration(milliseconds: 120));
      expect(calls.length, 1);
      expect(calls.single, contains('heavyImpact'));
    });

    testWidgets('the user setting silences everything', (tester) async {
      final calls = tapHaptics(tester);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      AppHaptics.enabled.value = false;
      addTearDown(() => AppHaptics.enabled.value = true);
      AppHaptics.warning();
      await tester.pump(const Duration(milliseconds: 120));
      expect(calls, isEmpty);
    });
  });
}
