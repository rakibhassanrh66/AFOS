import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/config/theme/app_colors.dart';
import 'package:afos_v7/features/about/presentation/widgets/about_ink.dart';

/// Contrast on the About screen, in BOTH themes.
///
/// WHY THIS IS A SEPARATE SUITE. The layout sweep proves nothing overflows and
/// nothing is starved of width. It says nothing at all about whether the text
/// can be READ, and this screen leans harder on accent-as-foreground than any
/// other — credential chips, the turn-it-over label, the support button, the
/// numbered contributions. Every one of those measured under 2.1:1 in light
/// mode against a required 4.5:1, and every one of them looked perfect on the
/// dark emulator where they were built.
///
/// These assert the WCAG AA floor directly, against the colour that is
/// genuinely behind the glyphs — not against the theme surface, because a chip
/// paints a tint of its own accent first and that tint is what the text sits
/// on.
void main() {
  // The two accents this screen uses, and the surfaces they land on.
  const accents = <String, Color>{
    'green (Eva)': AppColors.green,
    'blueLight (Rakib)': AppColors.blueLight,
  };

  // Dark: AppColors.surface. Light: AppColors.lightCard.
  const surfaces = <String, Color>{
    'dark': AppColors.surface,
    'light': AppColors.lightCard,
  };

  group('readableOn clears WCAG AA wherever an accent is used as text', () {
    for (final s in surfaces.entries) {
      for (final a in accents.entries) {
        // The card fill: the surface tinted 5% toward the accent.
        final card = Color.alphaBlend(a.value.withValues(alpha: 0.05), s.value);
        // The chip fill: a 10% tint, which is the worst case on the screen.
        final chip = Color.alphaBlend(a.value.withValues(alpha: 0.10), s.value);
        // The support button: a 10% tint of green over the plain surface.
        final button =
            Color.alphaBlend(AppColors.green.withValues(alpha: 0.10), s.value);

        test('${a.key} on the card (${s.key})', () {
          expect(contrastRatio(readableOn(a.value, card), card),
              greaterThanOrEqualTo(4.5));
        });

        test('${a.key} on a credential chip (${s.key})', () {
          expect(contrastRatio(readableOn(a.value, chip), chip),
              greaterThanOrEqualTo(4.5));
        });

        test('the support button label (${s.key})', () {
          expect(contrastRatio(readableOn(AppColors.green, button), button),
              greaterThanOrEqualTo(4.5));
        });
      }
    }

    test('the raw accents are the thing that fails, so this is not a no-op', () {
      // If someone "simplifies" readableOn back to returning its input, the
      // assertions above would still pass in dark mode and quietly stop
      // protecting light mode. This pins the fault that motivated the helper.
      final lightCard = Color.alphaBlend(
          AppColors.green.withValues(alpha: 0.05), AppColors.lightCard);
      expect(contrastRatio(AppColors.green, lightCard), lessThan(4.5),
          reason: 'the raw accent unexpectedly passes — if the palette '
              'changed, re-derive readableOn rather than deleting it');
    });

    test('a colour that already passes is returned untouched', () {
      // Dark mode must not be darkened: the accents are already 8:1 there, and
      // dimming them would be a regression dressed as a fix.
      final darkCard = Color.alphaBlend(
          AppColors.green.withValues(alpha: 0.05), AppColors.surface);
      expect(readableOn(AppColors.green, darkCard), AppColors.green);
    });
  });

  group('muted body copy stays readable', () {
    for (final entry in <String, ThemeData>{
      'dark': ThemeData(brightness: Brightness.dark),
      'light': ThemeData(brightness: Brightness.light),
    }.entries) {
      testWidgets('aboutMuted clears AA (${entry.key})', (tester) async {
        late Color muted;
        await tester.pumpWidget(MaterialApp(
          theme: entry.value,
          home: Builder(builder: (context) {
            muted = aboutMuted(context);
            return const SizedBox();
          }),
        ));

        final surface = entry.key == 'dark'
            ? AppColors.surface
            : AppColors.lightCard;
        final card = Color.alphaBlend(
            AppColors.green.withValues(alpha: 0.05), surface);
        expect(contrastRatio(muted, card), greaterThanOrEqualTo(4.5),
            reason: 'muted copy on the About card is unreadable in '
                '${entry.key} mode');
      });
    }

    test('AppColors.textMutedOf in light mode is what this works around', () {
      // The token this screen deliberately does not use, and why. If it is ever
      // corrected upstream, aboutMuted can be deleted — this test is the note
      // that says so.
      final lightMuted =
          Color.alphaBlend(AppColors.lightMuted.withValues(alpha: 0.7),
              AppColors.lightCard);
      final card = Color.alphaBlend(
          AppColors.green.withValues(alpha: 0.05), AppColors.lightCard);
      expect(contrastRatio(lightMuted, card), lessThan(4.5));
    });
  });
}
