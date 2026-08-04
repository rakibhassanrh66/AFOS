@Tags(['source-scan'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A standing source-level guard against the starve shape, across the WHOLE app.
///
/// WHY THIS EXISTS ALONGSIDE THE RENDERING SWEEP.
///
/// `layout_probe` is precise — it measures real pixels — but it can only drive
/// widgets a test can construct. This app has **281 private widget classes**
/// (`_AttendanceCard`, `_SubmissionCard`, `_StopRow`, …) sealed inside their
/// screens, and those screens are full Scaffolds that fetch in `initState`. To
/// render-probe all 62 screens, every one of those would have to be extracted
/// first. That is a mechanical refactor measured in days, and until it is done
/// the pixel sweep covers two features and the shared widgets.
///
/// So this catches the same bug a different way: by SHAPE, in the source, in
/// every file at once. It is less precise — it cannot tell you how many pixels
/// were lost — but it cannot be out of date either, and it covers the screens
/// the renderer cannot reach yet.
///
/// THE SHAPE. A `Row` lays its non-flex children out first at their full
/// intrinsic width and gives `Expanded`/`Flexible` only what is left. So a
/// `Row` that contains BOTH a flex child AND a bare badge or button is the
/// exact arrangement that has now produced a starved title eight times in this
/// repo — most recently a course title rendered at 0.0px, at an ordinary 1.0x
/// text scale, in the card nine screens are built from.
///
/// The fix is never to cap the victim's text. It is one of:
///   * move the badge onto its own line (see JoinRequestCard, OfferingCard);
///   * wrap the offender in `Flexible` so it shrinks instead of taking;
///   * bound it with a `ConstrainedBox` (see InfoCard's trailing);
///   * for a button pair, `rowAction()` from config/theme/button_styles.dart.
void main() {
  test('no Row puts a bare badge or button beside a flex child', () {
    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final source = _stripCommentsAndStrings(file.readAsStringSync());
      for (final row in _findRows(source)) {
        final children = _topLevelChildren(row.body);
        if (children.isEmpty) continue;

        // Only a flex child that can LOSE SOMETHING READABLE counts.
        //
        // `Expanded(child: Divider())` is squeezed by design — a divider is a
        // spacer, and it being 0px wide beside a badge costs the user nothing.
        // Flagging it would be noise, and noise is how a guard like this gets
        // ignored. The bug is text being taken away, so require text.
        final losesText = children.any((c) =>
            (c.startsWith('Expanded(') || c.startsWith('Flexible(')) &&
            c.contains('Text('));
        if (!losesText) continue;

        final bare = children.where(_isBareGreedyChild).toList();
        if (bare.isEmpty) continue;

        final line = '\n'.allMatches(source.substring(0, row.start)).length + 1;
        offenders.add('${file.path.replaceAll(r'\', '/')}:$line  '
            'Row has a flex child and bare ${bare.map(_name).join(', ')}');
      }
    }

    expect(offenders, isEmpty,
        reason: 'These Rows can starve their flex child to 0px:\n'
            '${offenders.join('\n')}\n\n'
            'Fix by moving the badge to its own line, wrapping it in Flexible, '
            'bounding it with a ConstrainedBox, or using rowAction() for a '
            'button pair — not by adding maxLines to the text that lost.');
  });
}

/// Widgets that take whatever width they like and therefore starve a sibling.
///
/// Deliberately a short, specific list rather than "any widget": the point is
/// the greedy ones. A plain `Icon` or `SizedBox` is a fixed handful of pixels
/// and has never caused this.
const _greedy = [
  'PillBadge(',
  'OutlinedButton(',
  'OutlinedButton.icon(',
  'ElevatedButton(',
  'ElevatedButton.icon(',
  'FilledButton(',
  'FilledButton.icon(',
  'TextButton(',
  'TextButton.icon(',
];

String _name(String child) =>
    _greedy.firstWhere(child.startsWith, orElse: () => child).replaceAll('(', '');

bool _isBareGreedyChild(String child) {
  // A button that is given a bounded width is not greedy any more — that IS
  // the fix, so seeing it here means the call site is already correct.
  if (child.startsWith('Expanded(') ||
      child.startsWith('Flexible(') ||
      child.startsWith('SizedBox(') ||
      child.startsWith('ConstrainedBox(')) {
    return false;
  }
  if (!_greedy.any(child.startsWith)) return false;
  // rowAction() overrides the theme's infinite minimumSize, which is the whole
  // reason a button is greedy in the first place.
  return !child.contains('rowAction(');
}

class _Row {
  final int start;
  final String body;
  _Row(this.start, this.body);
}

/// Finds every `Row(...)` and returns its argument text.
List<_Row> _findRows(String source) {
  final rows = <_Row>[];
  final pattern = RegExp(r'\bRow\s*\(');
  for (final m in pattern.allMatches(source)) {
    final open = source.indexOf('(', m.start);
    final close = _matching(source, open, '(', ')');
    if (close < 0) continue;
    rows.add(_Row(m.start, source.substring(open + 1, close)));
  }
  return rows;
}

/// The top-level entries of a `children: [...]` list, as trimmed strings.
List<String> _topLevelChildren(String rowBody) {
  final key = RegExp(r'children\s*:\s*\[');
  final m = key.firstMatch(rowBody);
  if (m == null) return const [];
  final open = rowBody.indexOf('[', m.start);
  final close = _matching(rowBody, open, '[', ']');
  if (close < 0) return const [];

  final list = rowBody.substring(open + 1, close);
  final out = <String>[];
  var depth = 0, last = 0;
  for (var i = 0; i < list.length; i++) {
    final c = list[i];
    if (c == '(' || c == '[' || c == '{') depth++;
    if (c == ')' || c == ']' || c == '}') depth--;
    if (c == ',' && depth == 0) {
      out.add(_normalise(list.substring(last, i)));
      last = i + 1;
    }
  }
  out.add(_normalise(list.substring(last)));
  return out.where((e) => e.isNotEmpty).toList();
}

/// Strips the prefixes that do not change what a child IS — `const`, a
/// collection-`if` guard, a spread — so `if (isLab) const PillBadge(...)` is
/// recognised as a PillBadge.
String _normalise(String raw) {
  var s = raw.trim();
  var changed = true;
  while (changed) {
    changed = false;
    for (final p in ['const ', '...', 'else ']) {
      if (s.startsWith(p)) {
        s = s.substring(p.length).trim();
        changed = true;
      }
    }
    final ifMatch = RegExp(r'^if\s*\(').firstMatch(s);
    if (ifMatch != null) {
      final close = _matching(s, s.indexOf('('), '(', ')');
      if (close > 0) {
        s = s.substring(close + 1).trim();
        changed = true;
      }
    }
  }
  return s;
}

int _matching(String s, int openIndex, String open, String close) {
  var depth = 0;
  for (var i = openIndex; i < s.length; i++) {
    if (s[i] == open) depth++;
    if (s[i] == close) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// Blanks out comments and string bodies so their contents cannot be mistaken
/// for code — this repo's comments quote widget names constantly, and every one
/// of them would otherwise be a false positive.
String _stripCommentsAndStrings(String src) {
  final out = StringBuffer();
  var i = 0;
  while (i < src.length) {
    final rest = src.length - i;
    if (rest >= 2 && src[i] == '/' && src[i + 1] == '/') {
      while (i < src.length && src[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (rest >= 2 && src[i] == '/' && src[i + 1] == '*') {
      while (i < src.length && !(src[i] == '*' && i + 1 < src.length && src[i + 1] == '/')) {
        out.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      i += 2;
      out.write('  ');
      continue;
    }
    if (src[i] == "'" || src[i] == '"') {
      final quote = src[i];
      out.write(' ');
      i++;
      while (i < src.length && src[i] != quote) {
        if (src[i] == r'\') {
          out.write(' ');
          i++;
          if (i < src.length) {
            out.write(' ');
            i++;
          }
          continue;
        }
        out.write(src[i] == '\n' ? '\n' : ' ');
        i++;
      }
      if (i < src.length) {
        out.write(' ');
        i++;
      }
      continue;
    }
    out.write(src[i]);
    i++;
  }
  return out.toString();
}
