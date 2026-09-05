import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/core/utils/image_pick_policy.dart';

/// The upload caps must never fall below what the app actually decodes.
///
/// WHY THIS TEST EXISTS. `ImagePickPolicy` fixes photos being uploaded at
/// 10-30x the size any screen can use (measured: `avatars` averaged 378 KB for
/// a 256px circle). But a cap that is too SMALL is its own bug, and a quieter
/// one: every avatar simply goes soft, on every screen, and nothing fails.
///
/// The two numbers that must stay in step live in different files and are
/// changed by different kinds of work — someone enlarging an avatar on one
/// screen has no reason to open `image_pick_policy.dart`. So this test reads
/// the decode hints straight out of `lib/` and asserts the relationship, rather
/// than restating either number.
void main() {
  /// Every `.dart` file under lib/, as (path, source).
  final sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .map((f) => (path: f.path.replaceAll(r'\', '/'), text: f.readAsStringSync()))
      .toList();

  /// Decode hints on one line: `memCacheWidth: N`, `cacheWidth: N`,
  /// `maxWidth: N` / `maxHeight: N` (the CachedNetworkImageProvider form).
  final hint = RegExp(r'\b(?:memCacheWidth|memCacheHeight|cacheWidth|cacheHeight|maxWidth|maxHeight):\s*(\d+)');

  /// Layout constraints share the `maxWidth:` spelling and are not decodes.
  bool isLayout(String line) =>
      line.contains('BoxConstraints') ||
      line.contains('AdaptiveContentWidth') ||
      line.contains('constraints:');

  test('no avatar is decoded larger than avatars are stored', () {
    final offenders = <String>[];
    for (final (path: path, text: text) in sources) {
      if (path.endsWith('image_pick_policy.dart')) continue;
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (!line.toLowerCase().contains('avatar')) continue;
        if (isLayout(line)) continue;
        for (final m in hint.allMatches(line)) {
          final px = int.parse(m.group(1)!);
          if (px > ImagePickPolicy.avatarMaxEdge) {
            offenders.add('$path:${i + 1} decodes at ${px}px');
          }
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'These sites ask for more pixels than ImagePickPolicy.avatarMaxEdge '
          '(${ImagePickPolicy.avatarMaxEdge}) ever stores, so the avatar will '
          'render soft. Either shrink the decode or raise the upload cap — but '
          'raising the cap costs every user bytes on every screen.',
    );
  });

  test('no lost & found photo is decoded larger than they are stored', () {
    final offenders = <String>[];
    for (final (path: path, text: text) in sources) {
      if (!path.contains('lost_found')) continue;
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (isLayout(lines[i])) continue;
        for (final m in hint.allMatches(lines[i])) {
          final px = int.parse(m.group(1)!);
          if (px > ImagePickPolicy.itemPhotoMaxEdge) {
            offenders.add('$path:${i + 1} decodes at ${px}px');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Exceeds ImagePickPolicy.itemPhotoMaxEdge '
            '(${ImagePickPolicy.itemPhotoMaxEdge}).');
  });

  test('no upload path picks an image without a dimension cap', () {
    // `imageQuality` alone was the whole bug: it is a JPEG quality knob and
    // never touches dimensions, so a 4000x3000 camera frame went up intact.
    // Every pick must go through ImagePickPolicy, which supplies both.
    final rawPicks = <String>[];
    for (final (path: path, text: text) in sources) {
      if (path.endsWith('image_pick_policy.dart')) continue;
      final lines = text.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('ImagePicker().pickImage') ||
            lines[i].contains('.pickMultiImage(')) {
          rawPicks.add('$path:${i + 1}');
        }
      }
    }
    expect(
      rawPicks,
      isEmpty,
      reason: 'Call ImagePickPolicy.pickAvatar() / .pickItemPhoto() instead. A '
          'bare pickImage() uploads the raw camera frame, which is what made '
          'photos slow to load on low-end phones.',
    );
  });

  test('the caps stay in the range that made them worth doing', () {
    // Guard rails on the guard rails: if someone "fixes" a blurry avatar by
    // setting the cap to 4000, the regression is silent and total.
    expect(ImagePickPolicy.avatarMaxEdge, inInclusiveRange(256, 1024));
    expect(ImagePickPolicy.itemPhotoMaxEdge, inInclusiveRange(640, 2048));
    expect(ImagePickPolicy.avatarQuality, inInclusiveRange(70, 95));
    expect(ImagePickPolicy.itemPhotoQuality, inInclusiveRange(70, 95));
  });
}
