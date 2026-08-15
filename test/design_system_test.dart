import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:afos_v7/config/theme/app_text_styles.dart';
import 'package:afos_v7/config/theme/depth.dart';
import 'package:afos_v7/config/theme/liquid_glass_tokens.dart';
import 'package:afos_v7/config/theme/motion.dart';
import 'package:afos_v7/config/theme/spacing.dart';

/// The design constitution, as executable rules.
///
/// A design system written only in a markdown file decays: the next person adds
/// a 300ms duration or a 13px gap and nothing objects. These tests are the part
/// that objects. Each one pins a rule from CLAUDE.md that the Phase 0 audit
/// found violated.
void main() {
  setUpAll(() {
    // google_fonts otherwise tries to FETCH DM Sans over the network the first
    // time a TextStyle is built, which throws in a test environment (and would
    // make these tests depend on connectivity). Turning runtime fetching off
    // makes it fall back to the bundled/asset font and resolve synchronously —
    // the TextStyle, including its fontFeatures, is identical either way, and
    // fontFeatures is what these tests assert on.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('motion ladder', () {
    test('is strictly ordered by the mass of what it moves', () {
      final ladder = [
        AppMotion.instant,
        AppMotion.tight,
        AppMotion.base,
        AppMotion.slow,
        AppMotion.hero,
      ];
      for (var i = 1; i < ladder.length; i++) {
        expect(ladder[i] > ladder[i - 1], isTrue,
            reason: 'rung $i (${ladder[i]}) must be slower than ${ladder[i - 1]}');
      }
    });

    test('nothing exceeds 620ms', () {
      // The constitution's hard ceiling. Anything longer is a process needing a
      // progress indicator, not a transition.
      expect(AppMotion.hero.inMilliseconds, 620);
      for (final d in [AppMotion.instant, AppMotion.tight, AppMotion.base, AppMotion.slow]) {
        expect(d.inMilliseconds, lessThanOrEqualTo(620));
      }
    });

    test('press feedback is fast enough to land inside one frame budget', () {
      // Law 4: a gesture answers within 100ms.
      expect(AppMotion.pressDuration.inMilliseconds, lessThanOrEqualTo(100));
    });

    test('LiquidGlass motion constants alias the ladder — one system, not two', () {
      // The whole point of the Phase 1 re-basing. If someone re-hardcodes a
      // value here, the app quietly has two motion systems again.
      expect(LiquidGlass.motionStandard, AppMotion.base);
      expect(LiquidGlass.motionFast, AppMotion.tight);
      expect(LiquidGlass.pressDuration, AppMotion.instant);
      expect(LiquidGlass.motionCurve, AppMotion.standard);
      expect(LiquidGlass.pressScale, AppMotion.pressScale);
    });

    test('stagger is capped so a long list does not trickle in', () {
      expect(AppMotion.staggerMaxItems, lessThanOrEqualTo(6));
      // Worst case total stagger stays under a single `slow` transition.
      final worst = AppMotion.stagger * (AppMotion.staggerMaxItems - 1);
      expect(worst.inMilliseconds, lessThan(AppMotion.hero.inMilliseconds));
    });
  });

  group('reduced motion', () {
    testWidgets('collapses every duration to zero', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));

      expect(AppMotion.isReduced(ctx), isTrue);
      for (final d in [AppMotion.instant, AppMotion.base, AppMotion.hero]) {
        expect(AppMotion.durationOf(ctx, d), Duration.zero);
      }
      expect(AppMotion.staggerFor(ctx, 3), Duration.zero);
    });

    testWidgets('leaves durations intact when not requested', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(disableAnimations: false),
        child: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));

      expect(AppMotion.isReduced(ctx), isFalse);
      expect(AppMotion.durationOf(ctx, AppMotion.base), AppMotion.base);
      expect(AppMotion.staggerFor(ctx, 2), AppMotion.stagger * 2);
      // Past the cap, no delay even with motion enabled.
      expect(AppMotion.staggerFor(ctx, 99), Duration.zero);
    });

    testWidgets('is safe without a MediaQuery ancestor', (tester) async {
      // Called from constructors deep in shared code; must not throw.
      late BuildContext ctx;
      await tester.pumpWidget(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      }));
      expect(AppMotion.isReduced(ctx), isFalse);
    });
  });

  group('spacing scale', () {
    test('is geometric, not linear', () {
      // Perceived difference is ratio-based: 4->8 reads, 44->48 does not.
      expect(AppSpace.all, [4.0, 8.0, 12.0, 16.0, 24.0, 32.0, 48.0]);
    });

    test('isOnScale accepts the ladder and zero, rejects near-misses', () {
      for (final v in AppSpace.all) {
        expect(AppSpace.isOnScale(v), isTrue);
      }
      expect(AppSpace.isOnScale(0), isTrue);
      for (final v in [10.0, 11.0, 13.0, 14.0, 18.0, 20.0]) {
        expect(AppSpace.isOnScale(v), isFalse,
            reason: '$v is the kind of value that makes spacing look accidental');
      }
    });

    test('minimum touch target meets the accessibility floor', () {
      expect(AppSpace.minTouchTarget, greaterThanOrEqualTo(48));
    });
  });

  group('depth — one light source, top-left', () {
    test('level 0 casts nothing at all', () {
      // Not a transparent shadow: Flutter still composites those.
      expect(AppDepth.shadow(0, isDark: true), isEmpty);
      expect(AppDepth.shadow(0, isDark: false), isEmpty);
    });

    test('every shadow falls DOWN AND TO THE RIGHT', () {
      // This is the whole rule. A purely vertical offset is what makes UI read
      // as flat, and it is what every hand-written BoxShadow in the audit did.
      for (var level = 1; level <= 4; level++) {
        for (final dark in [true, false]) {
          for (final s in AppDepth.shadow(level, isDark: dark)) {
            expect(s.offset.dx, greaterThan(0),
                reason: 'level $level has no horizontal light direction');
            expect(s.offset.dy, greaterThan(0),
                reason: 'level $level does not fall downward');
          }
        }
      }
    });

    test('higher surfaces cast longer, softer shadows', () {
      double primaryBlur(int l) => AppDepth.shadow(l, isDark: true).first.blurRadius;
      double primaryDy(int l) => AppDepth.shadow(l, isDark: true).first.offset.dy;
      for (var l = 2; l <= 4; l++) {
        expect(primaryBlur(l), greaterThan(primaryBlur(l - 1)));
        expect(primaryDy(l), greaterThan(primaryDy(l - 1)));
      }
    });

    test('higher surfaces cast FAINTER shadows, not darker ones', () {
      // Increasing opacity with height is what produces muddy UI.
      double alpha(int l) => AppDepth.shadow(l, isDark: true).first.color.a;
      for (var l = 2; l <= 4; l++) {
        expect(alpha(l), lessThan(alpha(l - 1)));
      }
    });

    test('the brand ambient bloom stays off list-level surfaces', () {
      // Level 1 is a row; it must not glow.
      expect(AppDepth.shadow(1, isDark: true).length, 1);
      expect(AppDepth.shadow(3, isDark: true).length, greaterThan(1));
    });

    test('radius encodes elevation class and keeps the AFOS corner cut', () {
      final r0 = AppDepth.radius(0);
      final r2 = AppDepth.radius(2);
      expect(r2.topLeft.x, greaterThan(r0.topLeft.x));
      // The signature: three corners large, top-right cut tight.
      expect(r2.topRight.x, LiquidGlass.radiusCut);
      expect(r2.topLeft.x, LiquidGlass.radiusCard);
    });
  });

  group('typography — the tabular numeric role', () {
    // NOTE ON SCOPE. These assert the shared feature LIST, not a constructed
    // TextStyle. DM Sans is fetched by google_fonts at runtime rather than
    // bundled as an asset, so touching AppTextStyles.numericLarge in a test
    // kicks off an HTTP request and fails offline — including for the prose
    // styles. The feature list is what carries the rule and what all three
    // numeric styles reference, so it is the honest thing to pin here.

    test('tabular figures are declared so digits stop jittering', () {
      // The audit found ZERO uses of this feature in 188 files. Every number
      // that updates in place — the transport countdown, CGPA, live class
      // timers — was resizing its own text box on each tick.
      final features = AppTextStyles.tabularFeatures.map((f) => f.feature);
      expect(features, contains('tnum'),
          reason: 'tabular figures missing — digits will shift width');
    });

    test('a slashed zero is declared so 0 and O are distinguishable', () {
      // Matters on student IDs and seat numbers, which are read aloud and
      // typed back in.
      expect(AppTextStyles.tabularFeatures.map((f) => f.feature),
          contains('zero'));
    });

    test('the feature constants are what we think they are', () {
      expect(const FontFeature.tabularFigures().feature, 'tnum');
      expect(const FontFeature.slashedZero().feature, 'zero');
    });
  });

  group('one radius idiom per elevation tier', () {
    // A SOURCE scan, not a widget test, because the thing being prevented is a
    // second way of writing the same intent — and a widget test can only see
    // the way that was actually used.
    //
    // THE HISTORY, so this test is not mistaken for pedantry. Two idioms
    // co-existed for the whole redesign: `BorderRadius.circular(
    // LiquidGlass.radiusCard)`, symmetric on all four corners, and
    // `AppDepth.radius(2)`, which routes through `signatureRadius` and cuts the
    // top-right to 8 — the AFOS silhouette. Both are "tokens", so neither
    // showed up in any slop count, and they render visibly differently. The
    // card tier was split 21-to-N across the academic module for four phases.
    //
    // Cards are now all signature. Control-tier (14) and pill-tier surfaces
    // deliberately stay symmetric: a cut corner on a chip, a button or a text
    // field reads as a rendering fault rather than a brand mark, and a chat
    // bubble's asymmetry already carries meaning (which corner is tight says
    // who spoke).
    final libDart = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    test('no card-tier radius is written the symmetric way', () {
      final offenders = <String>[];
      for (final file in libDart) {
        final src = file.readAsStringSync();
        for (final tier in const ['radiusCard', 'radiusSheet']) {
          if (src.contains('BorderRadius.circular(LiquidGlass.$tier)')) {
            offenders.add('${file.path} uses BorderRadius.circular('
                'LiquidGlass.$tier) — use AppDepth.radius() instead');
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'A card or sheet drawn with a symmetric radius loses the '
              'top-right cut, so it no longer matches the cards beside '
              'it:\n${offenders.join('\n')}');
    });

    test('AppDepth.radius cuts the top-right corner for card and sheet tiers',
        () {
      // The other half of the rule: the helper the test above redirects people
      // to must actually produce the silhouette. If signatureRadius were ever
      // flattened, the test above would keep passing while every card went
      // square.
      for (final level in const [2, 3]) {
        final r = AppDepth.radius(level);
        expect(r.topRight, const Radius.circular(LiquidGlass.radiusCut),
            reason: 'level $level lost its cut corner');
        expect(r.topLeft, isNot(r.topRight),
            reason: 'level $level is symmetric — the silhouette is gone');
      }
    });
  });
}
