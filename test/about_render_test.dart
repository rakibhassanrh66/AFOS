import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:afos_v7/config/theme/dark_theme.dart';
import 'package:afos_v7/config/theme/light_theme.dart';
import 'package:afos_v7/features/about/presentation/about_screen.dart';
import 'package:afos_v7/features/shell/bloc/shell_bloc.dart';

/// Renders the REAL About screen to PNGs under `build/about_preview/` so a
/// human can look at it.
///
/// WHY THIS EXISTS, and why it is worth keeping. Before this, the screen could
/// not be pumped in a test at all: `AfosAppBar` reaches for
/// `Supabase.instance`, which asserts unless a client has been initialised, and
/// nothing under `test/` had ever initialised one. That single assert is the
/// reason this project has 700+ widget tests and **not one** that builds a
/// whole screen. It turns out the client only has to EXIST — point it at a dead
/// local URL, hand it `EmptyLocalStorage` so it never reaches for
/// shared_preferences or secure storage, and the app bar is satisfied. Nothing
/// here makes a request.
///
/// TWO TRAPS, both of which produced convincing wrong pictures before they were
/// understood:
///
///  * `pump()` + `pump(900ms)` is NOT enough. The staged entrance is still
///    mid-fade and the capture comes out blank — a screen that looks
///    catastrophically broken and is perfectly fine. Use `pumpAndSettle()`.
///  * The FIRST capture in a file renders with a COLD CACHE: `Image.asset` has
///    not decoded and `google_fonts` has not resolved its bundled face, so the
///    portraits come out empty and small text comes out as solid blocks. Again:
///    looks like a serious bug, is an artifact. `warmUp` pumps and discards a
///    frame before every capture so the images can be trusted.
///
/// It asserts only that the screen builds and its content is present. The value
/// is the images, which catch what no probe can describe: crowding, a rule that
/// does not line up, a colour that passes contrast and still reads wrong.
void main() {
  // FIRST line of main(), not inside setUpAll. The theme builders below call
  // google_fonts, and the test bodies are COLLECTED before setUpAll runs -- so
  // a theme built at collection time hits "Binding has not yet been
  // initialized" and every test in the file fails to load.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:1',
      publishableKey: 'test-publishable-key',
      debug: false,
      authOptions:
          const FlutterAuthClientOptions(localStorage: EmptyLocalStorage()),
    );
  });

  final outDir = Directory('build/about_preview');

  Widget harness(GlobalKey key, ThemeData theme, Size size, double textScale) =>
      MaterialApp(
        theme: theme,
        home: MediaQuery(
          data: MediaQueryData(
              size: size, textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(
            key: key,
            child: BlocProvider(
              create: (_) => ShellBloc(),
              child: const AboutScreen(),
            ),
          ),
        ),
      );

  /// Decode the portraits and resolve the bundled font once, before anything is
  /// captured. See the note above — without this the first picture lies.
  Future<void> warmUp(WidgetTester tester) async {
    await tester.pumpWidget(
        harness(GlobalKey(), buildDarkTheme(), const Size(400, 900), 1.0));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final ctx = tester.element(find.byType(AboutScreen));
      for (final asset in const [
        'assets/profile/eva_512.jpg',
        'assets/profile/rakib_512.jpg',
      ]) {
        await precacheImage(AssetImage(asset), ctx);
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> shoot(
    WidgetTester tester,
    String name,
    ThemeData theme, {
    Size size = const Size(400, 900),
    double textScale = 1.0,
    Future<void> Function(WidgetTester)? after,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await warmUp(tester);

    final key = GlobalKey();
    await tester.pumpWidget(harness(key, theme, size, textScale));
    await tester.pumpAndSettle();

    expect(find.textContaining('protidin notun'), findsOneWidget,
        reason: 'the dedication never built');

    if (after != null) await after(tester);
    await tester.pumpAndSettle();

    final bytes = await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });

    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    File('${outDir.path}/$name.png').writeAsBytesSync(bytes!);
  }

  /// Scroll the PAGE (the outermost scrollable) by [dy] logical pixels.
  Future<void> page(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(Scrollable).first, Offset(0, -dy),
        warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  /// Every line of the developer profile, exactly as it was given.
  ///
  /// WHY THIS IS A TEST AND NOT A CODE REVIEW. This is somebody's own account
  /// of their life and career, handed over as a list with an order to it. A
  /// dropped line is not a rendering bug that anyone would notice -- the screen
  /// looks perfectly fine with ten of eleven entries -- and the person it
  /// belongs to is the last one who would be asked to proof-read it. So the
  /// list is pinned here, in the words it arrived in, and the screen is
  /// searched for each one.
  const cv = <String>[
    'CSE Major in Cyber Security',
    'Intern, Kaspersky Lab as a Security & System Engineer in Russia, 2026',
    'CISA, CompTIA, CEH L4, NSDA L4',
    'Web, Software & Game Developer',
    'Requested Candidate, Russia Nuclear University as a Quantum Computer '
        'Research Assistant, Anthology, 2025',
    'BracIT, Associate Security Engineer, 2024-2025',
    'Dcorn, Backend Developer, 2024',
    'Shared Investor, Tasty Treat, 2022-2024. Burned and faced a loss of '
        'about 20 lakhs.',
    'Foodpanda Delivery Boy, worked at night in Mohammadpur, 2020',
    'Server / Hotel Boy at several Bangla hotels',
    'Kicked out from BAFA, 83/155 Board, 2221, 2019',
  ];

  /// Load-bearing phrases from the prose. Not the whole passage -- a test that
  /// pins every word makes every edit a test failure. These are the claims that
  /// would be quietly softened or lost.
  const story = <String>[
    'CGPA lower than 2.79, failed in a course, barely managed to pass.',
    'kicked out of clubs for telling the truth',
    'And I come from down, very down.',
    'If I did not earn, I could not manage to get food, shelter',
    'I skipped the razzle.',
    'They are my strengths.',
  ];

  testWidgets('the developer profile keeps every line it was given',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
        harness(GlobalKey(), buildDarkTheme(), const Size(400, 900), 1.0));
    await tester.pumpAndSettle();

    // The reverse is not built until the card is turned, so turn it.
    await tester.tap(find.text('Rakib Hassan'));
    await tester.pump();
    await tester.pumpAndSettle();

    final missing = <String>[];
    for (final line in [...cv, ...story]) {
      if (find.textContaining(line, findRichText: true).evaluate().isEmpty) {
        missing.add(line);
      }
    }
    expect(missing, isEmpty,
        reason: 'these lines never reached the screen:\n - '
            '${missing.join('\n - ')}');
  });

  testWidgets('every emphasis marker on the screen is closed', (tester) async {
    // An odd marker renders the rest of a paragraph bold, which is the kind of
    // thing that ships because it still looks deliberate.
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
        harness(GlobalKey(), buildDarkTheme(), const Size(400, 900), 1.0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rakib Hassan'));
    await tester.pump();
    await tester.pumpAndSettle();

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final raw = text.data ?? text.textSpan?.toPlainText() ?? '';
      expect(raw.contains('**'), isFalse,
          reason: 'a literal ** survived to the screen in: $raw');
    }
  });

  // Builders, not built themes: these are invoked inside each test body, after
  // the binding exists.
  for (final theme in <String, ThemeData Function()>{
    'dark': buildDarkTheme,
    'light': buildLightTheme,
  }.entries) {
    final t = theme.key;

    testWidgets('$t — top of page', (tester) async {
      await shoot(tester, '${t}_1_top', theme.value());
    });

    testWidgets('$t — the two cards', (tester) async {
      await shoot(tester, '${t}_2_cards', theme.value(),
          after: (tester) => page(tester, 700));
    });

    testWidgets('$t — a card turned over', (tester) async {
      await shoot(tester, '${t}_3_back', theme.value(), after: (tester) async {
        await page(tester, 700);
        await tester.tap(find.text('Rakib Hassan'));
        await tester.pump();
        await tester.pumpAndSettle();
      });
    });

    testWidgets('$t — support details revealed', (tester) async {
      await shoot(tester, '${t}_4_support', theme.value(),
          after: (tester) async {
        await tester.ensureVisible(find.text('Show where it goes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Show where it goes'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('1065237910001'));
        await tester.pumpAndSettle();
      });
    });

    // The whole page in one frame. Nothing else shows the RHYTHM -- whether
    // the sections breathe, whether two blocks of prose sit next to each other
    // with nothing between them, whether the page is just a wall.
    testWidgets('$t — whole page', (tester) async {
      await shoot(tester, '${t}_6_whole', theme.value(),
          size: const Size(400, 2600));
    });

    // The reverse scrolled to its end, which is the only way to see the list
    // at the bottom of it.
    testWidgets('$t — the end of the reverse', (tester) async {
      await shoot(tester, '${t}_7_back_end', theme.value(),
          after: (tester) async {
        await page(tester, 700);
        await tester.tap(find.text('Rakib Hassan'));
        await tester.pump();
        await tester.pumpAndSettle();
        // The card's OWN scrollable is the innermost one.
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -4000),
            warnIfMissed: false);
        await tester.pumpAndSettle();
      });
    });

    testWidgets('$t — 320px at 1.6x text', (tester) async {
      await shoot(tester, '${t}_5_small', theme.value(),
          size: const Size(320, 900), textScale: 1.6);
    });
  }
}
