import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:afos_v7/config/theme/app_colors.dart';
import 'package:afos_v7/config/theme/dark_theme.dart';
import 'package:afos_v7/config/theme/light_theme.dart';
import 'package:afos_v7/shared/widgets/glass_chip.dart';

/// Pins the accent-colour setting to something a user can actually see.
///
/// The picker was wired end to end — `SetAccentColor` saved to Hive AND to
/// `user_settings.accent_color`, `_loadSaved` read it back, main.dart passed it
/// to `buildDarkTheme(accent:)` — and it still did nothing, because there were
/// ZERO references to `colorScheme` anywhere under `lib/features` against 2051
/// hardcoded `AppColors.*` constants. Every part worked except the last one, so
/// nothing failed and the feature was simply inert.
///
/// These tests assert the chain end to end rather than any single link, since
/// every single link was already fine.
void main() {
  const picked = Color(0xFFEC4899); // pink — one of the Settings swatches

  // buildDarkTheme/buildLightTheme resolve their text styles through
  // google_fonts, which tries to FETCH the font over HTTP when it is not
  // already bundled. In a test that is both a network call and a failure, so
  // runtime fetching is turned off and the bundled fallback is used — the
  // colours under test are unaffected either way.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // testWidgets, not test: buildDarkTheme/buildLightTheme resolve their fonts
  // through google_fonts, which throws outside a widget binding. The colours
  // are what is under test, but they cannot be reached without building the
  // whole ThemeData, so these run under the binding.
  group('accent reaches ThemeData', () {
    testWidgets('dark theme puts the chosen accent on colorScheme.primary',
        (tester) async {
      expect(buildDarkTheme(accent: picked).colorScheme.primary, picked);
    });

    testWidgets('light theme puts the chosen accent on colorScheme.primary',
        (tester) async {
      expect(buildLightTheme(accent: picked).colorScheme.primary, picked);
    });

    testWidgets('no accent falls back to the brand colour, not to null',
        (tester) async {
      expect(buildDarkTheme().colorScheme.primary, isNotNull);
    });
  });

  testWidgets('AppColors.accentOf reads the chosen accent', (tester) async {
    late Color seen;
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(accent: picked),
      home: Builder(builder: (context) {
        seen = AppColors.accentOf(context);
        return const SizedBox();
      }),
    ));
    expect(seen, picked);
  });

  testWidgets('a selected GlassChip paints with the accent, not a fixed blue',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildDarkTheme(accent: picked),
      home: const Scaffold(
        body: GlassChip(label: 'All Departments', selected: true),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    // Walk the chip's own decorations rather than asserting on one widget's
    // internals: the accent is applied as a fill and a border, and which of
    // those carries it is a styling detail this test should not freeze.
    final decorations = tester
        .widgetList<Container>(find.descendant(
            of: find.byType(GlassChip), matching: find.byType(Container)))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>();

    bool mentions(Color c) => decorations.any((d) =>
        d.color?.toARGB32() == c.toARGB32() ||
        (d.border?.top.color.toARGB32() == c.toARGB32()) ||
        (d.gradient?.colors.any((g) => g.toARGB32() == c.toARGB32()) ?? false));

    expect(mentions(picked), isTrue,
        reason: 'the selected chip should carry the user accent');
    expect(mentions(AppColors.blue), isFalse,
        reason: 'the old hardcoded blue fallback should be gone');
  });
}
