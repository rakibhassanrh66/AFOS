import 'package:flutter/widgets.dart';

/// One place a user can go, as the menu understands it.
///
/// WHY THIS IS PUBLISHED RATHER THAN RECOMPUTED. The command palette needs the
/// same list the slide menu shows — and that list is not a constant. It is the
/// output of `_roleItems`, which encodes the role matrix, the per-person
/// delegated `resource:action` grants, the CR flag and the SOS toggle, and
/// whose `resource:action` pairs are deliberately the same ones
/// `app_router.dart` guards the matching routes with, so the menu and the
/// router can never disagree about who may open what.
///
/// Reimplementing that in a second place is how those two start to disagree.
/// A palette listing a destination the router will refuse is worse than no
/// palette. So the menu — which is permanently mounted in the shell — publishes
/// what it decided, and everything else reads it.
@immutable
class NavDestination {
  final String label;
  final String route;
  final IconData icon;
  final Color color;

  const NavDestination(this.label, this.icon, this.route, this.color);

  @override
  bool operator ==(Object other) =>
      other is NavDestination && other.route == route && other.label == label;

  @override
  int get hashCode => Object.hash(route, label);
}

/// What the current user can actually reach, as last decided by the slide menu.
///
/// Empty until the menu has resolved the user's role and grants — a palette
/// opened in that window shows nothing rather than showing everything, which is
/// the correct way for a permission-derived list to fail.
final ValueNotifier<List<NavDestination>> navDestinations =
    ValueNotifier<List<NavDestination>>(const []);

/// Ranks [destinations] against a typed [query].
///
/// Subsequence matching, not substring: "mgu" should find "Manage Users" the
/// way a command palette is expected to, because nobody types whole words into
/// one. Scoring rewards matches that start a word and matches that are tightly
/// packed, so "trans" ranks Transport above a destination that merely contains
/// those letters scattered.
///
/// An empty query returns everything in menu order, which is deliberate: the
/// palette's first job is "show me where I can go", and only its second is
/// "filter that".
List<NavDestination> rankDestinations(
    List<NavDestination> destinations, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return destinations;

  final scored = <({NavDestination d, int score})>[];
  for (final d in destinations) {
    final score = _score(d.label.toLowerCase(), q);
    if (score > 0) scored.add((d: d, score: score));
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    // Stable, predictable tie-break — a palette whose order jitters between
    // keystrokes is one you cannot build muscle memory for.
    return a.d.label.compareTo(b.d.label);
  });
  return [for (final s in scored) s.d];
}

/// 0 means "no match". Higher is better.
int _score(String label, String query) {
  var score = 0;
  var labelIndex = 0;
  var lastMatch = -1;

  for (final rune in query.runes) {
    final ch = String.fromCharCode(rune);
    if (ch == ' ') continue;
    final found = label.indexOf(ch, labelIndex);
    if (found < 0) return 0; // a character that is not there at all
    // Starting a word is the strongest signal: it is what an abbreviation is.
    if (found == 0 || label[found - 1] == ' ' || label[found - 1] == '&') {
      score += 8;
    } else {
      score += 1;
    }
    // Consecutive characters beat scattered ones.
    if (found == lastMatch + 1) score += 4;
    lastMatch = found;
    labelIndex = found + 1;
  }

  // A short label matched completely is a better answer than a long one that
  // merely contains the letters.
  if (label.startsWith(query)) score += 12;
  return score;
}
