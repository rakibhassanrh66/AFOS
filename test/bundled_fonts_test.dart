import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every font weight the app asks for must be bundled in the APK.
///
/// WHY THIS TEST EXISTS, AND WHY IT MATTERS MORE THAN IT LOOKS.
///
/// `bootstrap()` sets `GoogleFonts.config.allowRuntimeFetching = false`, so the
/// app no longer downloads DM Sans from fonts.gstatic.com on first launch. The
/// six faces ship in `assets/fonts/` instead.
///
/// The failure mode of getting that wrong is SILENT. `google_fonts` does throw
/// when a face is neither bundled nor fetchable — and then catches its own
/// exception and `print`s it (`google_fonts_base.dart`, the `catch (e)` around
/// `loadFontIfNecessary`). The app does not crash. It quietly renders in the
/// platform fallback face, on every screen, and the only trace is a line in
/// logcat that nobody is reading. Adding `FontWeight.w300` to one text style
/// would be enough to do it.
///
/// So this test reproduces the package's OWN resolution rule — scan the asset
/// list for a file whose name ends in `Family-Variant`
/// (`_findFamilyWithVariantAssetPath` + `_fontWeightToFilenameWeightParts`) —
/// and asserts it against the weights the theme actually uses. It reads both
/// sides from source, so it cannot agree with a stale copy of either.
void main() {
  /// `_fontWeightToFilenameWeightParts`, transcribed from google_fonts 6.3.3.
  const weightToFilenamePart = <String, String>{
    'w100': 'Thin',
    'w200': 'ExtraLight',
    'w300': 'Light',
    'w400': 'Regular',
    'w500': 'Medium',
    'w600': 'SemiBold',
    'w700': 'Bold',
    'w800': 'ExtraBold',
    'w900': 'Black',
  };

  /// The `fontFamily` google_fonts uses internally, per family helper.
  const helperToFamily = <String, String>{
    'dmSans': 'DMSans',
    'jetBrainsMono': 'JetBrainsMono',
  };

  final pubspec = File('pubspec.yaml').readAsStringSync();

  /// Every `GoogleFonts.<helper>(...)` call in the theme, with the weight it
  /// asks for. A call with no `fontWeight` resolves to w400.
  Set<({String family, String weight})> requestedFaces() {
    final found = <({String family, String weight})>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      final text = file.readAsStringSync();
      for (final helper in helperToFamily.keys) {
        for (final m in RegExp('GoogleFonts\\.$helper\\(').allMatches(text)) {
          // Walk to the matching close paren so nested calls do not confuse us.
          var depth = 1;
          var i = m.end;
          while (i < text.length && depth > 0) {
            if (text[i] == '(') depth++;
            if (text[i] == ')') depth--;
            i++;
          }
          final args = text.substring(m.end, i);
          final w = RegExp(r'fontWeight:\s*FontWeight\.(w\d00)').firstMatch(args);
          found.add((family: helperToFamily[helper]!, weight: w?.group(1) ?? 'w400'));
        }
      }
    }
    return found;
  }

  test('the theme asks for at least the faces we think it does', () {
    final faces = requestedFaces();
    expect(faces, isNotEmpty,
        reason: 'Found no GoogleFonts calls at all — the scan is broken, not '
            'the fonts.');
    // Sanity: the two families must both still be in use, or this test is
    // silently guarding nothing.
    expect(faces.map((f) => f.family).toSet(), {'DMSans', 'JetBrainsMono'});
  });

  test('every requested face is bundled and declared in pubspec', () {
    final missing = <String>[];
    final undeclared = <String>[];
    for (final face in requestedFaces()) {
      final part = weightToFilenamePart[face.weight];
      expect(part, isNotNull, reason: 'Unknown weight ${face.weight}');
      final asset = 'assets/fonts/${face.family}-$part.ttf';
      if (!File(asset).existsSync()) missing.add('${face.weight} -> $asset');
      if (!pubspec.contains(asset)) undeclared.add(asset);
    }
    expect(
      missing,
      isEmpty,
      reason: 'These faces are used but not bundled. With '
          'allowRuntimeFetching = false, google_fonts catches its own '
          'exception and prints it, so the app will render in the PLATFORM '
          'FALLBACK font with no crash and no visible error. Download the face '
          'into assets/fonts/ using the name above.',
    );
    expect(undeclared, isEmpty,
        reason: 'Present on disk but not listed under `assets:` in '
            'pubspec.yaml, so it will not be in the bundle.');
  });

  test('the bundled files are real TrueType, not an HTML error page', () {
    // curl -f would have caught a 404, but a captive portal or a proxy can hand
    // back a 200 with HTML. A font that is not a font fails exactly like a
    // missing one: silently.
    for (final f in Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf'))) {
      final head = f.readAsBytesSync().take(4).toList();
      expect(
        head,
        // equals() around each: `anyOf` treats a bare leading List as its own
        // list of matchers, which throws rather than comparing bytes.
        anyOf([
          equals([0x00, 0x01, 0x00, 0x00]), // TrueType outlines
          equals([0x74, 0x72, 0x75, 0x65]), // 'true'
          equals([0x4F, 0x54, 0x54, 0x4F]), // 'OTTO', CFF outlines
        ]),
        reason: '${f.path} does not start with a TrueType/OpenType magic '
            'number, so it is not a font file.',
      );
    }
  });

  test('the OFL licences ship, because bundling makes us a redistributor', () {
    for (final family in const ['DMSans', 'JetBrainsMono']) {
      final licence = 'assets/fonts/$family-OFL.txt';
      expect(File(licence).existsSync(), isTrue, reason: '$licence is missing');
      expect(pubspec.contains(licence), isTrue,
          reason: '$licence is not declared, so bootstrap cannot load it into '
              'LicenseRegistry and the licence never reaches the user.');
      expect(File(licence).readAsStringSync(), contains('SIL OPEN FONT LICENSE'));
    }
  });
}
