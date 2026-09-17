import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/config/theme/app_colors.dart';
import 'package:afos_v7/config/theme/motion.dart';
import 'package:afos_v7/features/about/presentation/widgets/about_content.dart';
import 'package:afos_v7/features/about/presentation/widgets/flip_profile_card.dart';

import 'support/layout_probe.dart';

/// The About screen's card and the pieces its reverse is built from, tested as
/// the real widgets.
///
/// WHAT IS ACTUALLY AT RISK HERE, and why these are the tests:
///
///  * The reverse carries several hundred words of someone's life at whatever
///    text size the reader has set, and three of its blocks pair a FIXED-WIDTH
///    column with an `Expanded` sibling. That is the exact shape
///    `layout_probe.dart` was written for — its own header records that the
///    fault "shipped twice" — so every one of them goes through the sweep at
///    320px and 2.0x.
///  * The turn is a 3D transform that swaps faces at the half-way point. If
///    that midpoint test is wrong by a frame the card shows mirror-written
///    text, which no analyzer catches.
///  * The reverse scrolls and the card also flips. Those two gestures share a
///    surface, so the tap target had to be narrowed to the header — and a test
///    has to hold it there, because the obvious "make the whole card tappable"
///    refactor would silently make reading interruptible again.
///  * Reduced motion has to collapse the turn WITHOUT disabling the control.
///    The project's audit found that distinction ignored across the app, so a
///    new widget gets it asserted rather than assumed.
void main() {
  // Long enough to overflow the tallest body the card will ever allow
  // (the 520px ceiling), because 'does it scroll' is the condition under
  // test. An earlier fixture was three paragraphs and quietly fit, so the
  // assertion passed on a card that was not scrolling at all. This is on
  // the order of what Rakib's reverse actually carries.
  const longBack = 'Paragraph one, long enough on its own that the body of this '
      'card runs past the height it is allowed to occupy on any phone in the '
      'probe set, which is the thing that makes it scroll at all.\n\n'
      'Paragraph two exists so there is something below the fold worth going '
      'to find, rather than a single orphaned line.\n\n'
      'Paragraph three keeps the total past the ceiling even on a tall desktop '
      'window, where the cap is 520 logical pixels rather than a fraction of a '
      'short phone.\n\n'
      'Paragraph four is here for the same reason as paragraph three, and is '
      'the point at which the fixture stops being a token and starts being '
      'the length of a real passage of somebody writing about their life.\n\n'
      'Paragraph five, and then the marker.\n\n'
      'BOTTOM MARKER';

  Widget card({Widget? back}) => FlipProfileCard(
        name: 'Israt Habiba Eva',
        role: 'Computer Science & Engineering · Forward Deployed Engineer',
        photoAsset: 'assets/profile/eva_512.jpg',
        accent: AppColors.green,
        tags: const ['Exterminators', 'CSE', 'FDE'],
        back: back ?? const AboutProse(longBack),
      );

  runLayoutSweep('AboutScreen', {
    'FlipProfileCard (front, five tags)': () => const FlipProfileCard(
          name: 'Rakib Hassan',
          role: 'Founder, Exterminators · CSE, Cyber Security · builds AFOS',
          photoAsset: 'assets/profile/rakib_512.jpg',
          accent: AppColors.blueLight,
          tags: [
            'CISA',
            'CompTIA',
            'CEH L4',
            'NSDA L4',
            'Web · Software · Games'
          ],
          back: Text('back'),
        ),
    'DevelopingPhoto': () => const DevelopingPhoto(
        asset: 'assets/profile/eva_512.jpg', size: 96, accent: AppColors.green),

    // The three fixed-column blocks, each driven with its longest REAL entry
    // rather than an invented one — a fixture longer than anything the screen
    // holds reports a starve that cannot happen.
    'AboutGlossary (longest real short form)': () =>
        const AboutGlossary('WHAT I HOLD', [
          (short: 'CISA', long: 'Certified Information Systems Auditor'),
          (
            short: 'Exterminators',
            long: 'Team member, alongside the developer'
          ),
          (
            short: 'NSDA L4',
            long: 'National Skills Development Authority, level 4'
          ),
        ]),
    // The longest real entries in the list, including the one with an
    // ampersand and the one that runs to three lines at 2.0x.
    'AboutFactList (longest real entries)': () => const AboutFactList(
          'EDUCATION, CAREER & EXPERIENCE',
          [
            '**Requested Candidate, Russia Nuclear University** as a '
                'Quantum Computer Research Assistant, Anthology, 2025',
            '**Shared Investor, Tasty Treat**, 2022-2024. Burned and faced '
                'a loss of about 20 lakhs.',
            '**Foodpanda Delivery Boy**, worked at night in Mohammadpur, '
                '2020',
          ],
          accent: AppColors.blueLight,
        ),
    'AboutPoints (longest real contribution)': () => const AboutPoints(
          'WHAT SHE ACTUALLY DID',
          [
            (
              title: 'Was the bridge to academic life',
              detail: 'For someone who came into it from outside and had '
                  'nobody else to ask. That is the contribution this app is '
                  'named for.'
            ),
          ],
          accent: AppColors.green,
        ),

    // The two blocks that were private to the screen until the sweep could not
    // reach them. AboutDedication is not here for symmetry: an unbounded-height
    // `CrossAxisAlignment.stretch` inside it threw on first paint at every size
    // in this set, and it went unnoticed precisely because nothing could build
    // it outside the live screen.
    'AboutDedication (the quote that started it)': () => const AboutDedication(
          quote: 'Iss, protidin notun notun website ar app hoy — ar notun app '
              'download, install, log-in er jhamela.',
          translation: 'Every day it is another website, another app. And '
              'every time, the same hassle: download it, install it, log in '
              'all over again.',
        ),
    'AboutSupportCard (collapsed)': () => const AboutSupportCard(),
  });

  Future<void> pump(WidgetTester tester, Widget child,
      {bool reduceMotion = false, Size size = const Size(400, 860)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(size: size, disableAnimations: reduceMotion),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  /// Turn the card and let both the rotation and the height settle.
  Future<void> flip(WidgetTester tester) async {
    await tester.tap(find.text('Israt Habiba Eva'));
    // The bare pump() is not padding -- it is what STARTS the controller.
    // tester.tap does not pump, so the ticker has not begun; without this the
    // first timed pump only registers the animation start, the second lands at
    // 240/380 of the turn, and the card is left frozen near edge-on. Every
    // geometric assertion after that is then made against a card squeezed to
    // 139px of its 334px width, and a drag aimed at its centre misses.
    await tester.pump();
    await tester.pump(AppMotion.slow);
    await tester.pump(AppMotion.base);
  }

  group('emphasis markers', () {
    const base = TextStyle(fontWeight: FontWeight.w400);
    const strong = TextStyle(fontWeight: FontWeight.w700);

    test('splits a marked run out of the surrounding prose', () {
      final spans = emphasisSpans('plain **bold** plain', base, strong);
      expect(spans.map((s) => s.text).toList(),
          ['plain ', 'bold', ' plain']);
      expect(spans.map((s) => s.style!.fontWeight).toList(),
          [FontWeight.w400, FontWeight.w700, FontWeight.w400]);
    });

    test('a leading run is still emphasised', () {
      // The lede of the developer profile opens with one, so this is the real
      // shape and not a hypothetical.
      final spans = emphasisSpans('**Lede.** Then the rest.', base, strong);
      expect(spans.first.text, 'Lede.');
      expect(spans.first.style!.fontWeight, FontWeight.w700);
    });

    test('unmarked text comes back as a single plain span', () {
      final spans = emphasisSpans('nothing marked here', base, strong);
      expect(spans, hasLength(1));
      expect(spans.single.style!.fontWeight, FontWeight.w400);
    });

    test('an unbalanced marker degrades instead of throwing', () {
      // It renders the tail emphasised, which is visible and fixable. The
      // balance of the copy this screen actually ships is asserted in
      // about_render_test.dart against the real screen.
      expect(() => emphasisSpans('**unclosed', base, strong), returnsNormally);
    });
  });

  testWidgets('front shows the summary and the invitation, not the story',
      (tester) async {
    await pump(tester, card());

    expect(find.text('Israt Habiba Eva'), findsOneWidget);
    expect(find.text('Exterminators'), findsOneWidget);
    expect(find.text('Read the long version'), findsOneWidget);
    expect(find.textContaining('Paragraph one'), findsNothing);
  });

  testWidgets('turning it over reveals the story, and turning back hides it',
      (tester) async {
    await pump(tester, card());

    await flip(tester);
    expect(find.textContaining('Paragraph one'), findsOneWidget);
    // The name stays, as the header on the reverse — that is what tells you
    // whose card you are now reading, and it is the way back.
    expect(find.text('Israt Habiba Eva'), findsOneWidget);
    expect(find.text('Read the long version'), findsNothing);

    await flip(tester);
    expect(find.textContaining('Paragraph one'), findsNothing);
    expect(find.text('Read the long version'), findsOneWidget);
  });

  testWidgets('the reverse grows to its whole content, and the PAGE scrolls it',
      (tester) async {
    // WHY THIS IS THE ASSERTION. The reverse used to be capped at a fraction of
    // the viewport with a scroll view of its own. Two scrollables sharing one
    // surface do not chain in Flutter: once the inner one hit its end, a drag
    // starting on the card was swallowed and the page never moved. Inside the
    // app shell, where a floating nav bar covers the bottom of the screen, that
    // left the last lines of somebody's profile wedged under the bar with no
    // gesture that could free them.
    //
    // So: exactly ONE scrollable, and the card taller than the viewport.
    // A real phone, not the roomy default: the point is that the card is
    // TALLER than the viewport, which is the only situation where any of this
    // matters.
    await pump(tester, card(), size: const Size(360, 640));
    await flip(tester);

    expect(find.byType(Scrollable), findsOneWidget,
        reason: 'a second scrollable is back inside the card, which is what '
            'made the bottom of it unreachable on a real device');

    final card_ = tester.getSize(find.byType(FlipProfileCard));
    expect(card_.height, greaterThan(400),
        reason: 'the reverse was capped instead of growing to its content');

    // And the end of the passage can be reached by scrolling the page.
    final page = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(page.position.maxScrollExtent, greaterThan(0));
    await tester.drag(find.byType(Scrollable), const Offset(0, -4000),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(page.position.pixels, page.position.maxScrollExtent,
        reason: 'the bottom of the card could not be scrolled to');
  });

  testWidgets('a tap on the body does not flip the card', (tester) async {
    // Only the header turns it back. With the page scrolling under the finger
    // and the card filling most of the screen, a fully-tappable card would flip
    // every time somebody tried to read it.
    await pump(tester, card());
    await flip(tester);

    await tester.tapAt(tester.getCenter(find.textContaining('Paragraph one')));
    await tester.pump(AppMotion.slow);
    await tester.pump(AppMotion.base);

    expect(find.textContaining('Paragraph one'), findsOneWidget,
        reason: 'a tap inside the body turned the card over');
    expect(find.text('Read the long version'), findsNothing);
  });

  testWidgets('under reduced motion the card still turns — just instantly',
      (tester) async {
    await pump(tester, card(), reduceMotion: true);

    await tester.tap(find.text('Israt Habiba Eva'));
    // A single zero-length frame. With the animation collapsed there is no
    // in-between state to wait for; if the control had been disabled instead of
    // the motion, this would find nothing.
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Paragraph one'), findsOneWidget);

    // Drain AppHaptics' 60ms coalescing timer. It is not motion — reduce-motion
    // does not switch haptics off — so it is still outstanding here, and a live
    // timer at the end of a test is a failure regardless of what it is for.
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('the support details stay hidden until they are asked for',
      (tester) async {
    // 320px at 2.0x — the narrowest phone in the probe set at the largest
    // accessibility scale, which is where an account number sitting beside a
    // 48dp copy button is most likely to be starved off the screen. The sweep
    // cannot reach this state because it never taps.
    const size = Size(320, 568);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final errors = <String>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) => errors.add(d.exceptionAsString());

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: const MediaQuery(
        data: MediaQueryData(
            size: size, textScaler: TextScaler.linear(2.0)),
        child: Scaffold(
          body: SingleChildScrollView(child: AboutSupportCard()),
        ),
      ),
    ));
    await tester.pump();

    // Findings are RECORDED here and asserted after the handler is restored.
    //
    // Calling expect() while FlutterError.onError is overridden is a trap: a
    // failing expect throws, the override is never undone, and the binding
    // then reports "A test overrode FlutterError.onError but either failed to
    // return it to its original state" — which says nothing about what
    // actually broke, and poisons the tests that run after it.
    final hiddenBefore = find.text('1065237910001').evaluate().isEmpty &&
        find.text('1671070005769').evaluate().isEmpty &&
        find.text('01643537724').evaluate().isEmpty;

    // At 2.0x on a 568px-tall phone the paragraph above pushes the button
    // below the fold, and a tap on an off-screen widget silently misses —
    // which would have read as "the reveal is broken" rather than "the test
    // never pressed it".
    await tester.ensureVisible(find.text('Show where it goes'));
    await tester.pump();
    await tester.tap(find.text('Show where it goes'));
    await tester.pump();
    await tester.pump(AppMotion.base);

    // All three destinations, by value. Listing them individually is the point:
    // a support block that quietly drops one account is worse than one that
    // shows none, because nobody looking at it would know.
    final shownAfter = find.text('1065237910001').evaluate().length == 1 &&
        find.text('1671070005769').evaluate().length == 1 &&
        find.text('01643537724').evaluate().length == 1;
    final warned =
        find.textContaining('will ever message you asking for money').evaluate().length == 1;

    await tester.pump(const Duration(milliseconds: 100));
    FlutterError.onError = previous;

    expect(hiddenBefore, isTrue,
        reason: 'an account number was on screen before anyone asked for it');
    expect(shownAfter, isTrue, reason: 'the details did not appear');
    // The anti-impersonation line is not optional decoration — it ships with
    // the numbers or the numbers are worse than useless.
    expect(warned, isTrue, reason: 'the impersonation warning was missing');
    expect(errors, isEmpty,
        reason: 'the revealed details broke layout at 320px / 2.0x:\n'
            '${errors.join('\n')}');
  });

  testWidgets('the card announces itself as a button, with its state',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, card());

    expect(
      tester.getSemantics(find.bySemanticsLabel(RegExp('Israt Habiba Eva'))),
      matchesSemantics(
        isButton: true,
        hasTapAction: true,
        hasEnabledState: false,
        label: 'Israt Habiba Eva. Computer Science & Engineering · '
            'Forward Deployed Engineer',
        value: 'Showing summary',
        hint: 'Turn the card over',
      ),
    );
    handle.dispose();
  });
}
