import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/core/navigation/nav_destinations.dart';

/// Phase 6 — the palette's ranking, which is the only part of it with an
/// opinion. The widget itself is keyboard plumbing; this is the bit that
/// decides whether typing three letters gets you where you meant to go.
void main() {
  const destinations = [
    NavDestination('Dashboard', Icons.home, '/home', Colors.blue),
    NavDestination('Class Schedule', Icons.schedule, '/schedule', Colors.blue),
    NavDestination('Transport', Icons.directions_bus, '/transport', Colors.teal),
    NavDestination('Lost & Found', Icons.search, '/lost-found', Colors.orange),
    NavDestination('Manage Users', Icons.people, '/admin/users', Colors.purple),
    NavDestination('Manage Library', Icons.book, '/admin/library', Colors.indigo),
    NavDestination('My Attendance', Icons.check, '/my-attendance', Colors.green),
    NavDestination('Settings', Icons.settings, '/settings', Colors.grey),
  ];

  List<String> labels(String q) =>
      rankDestinations(destinations, q).map((d) => d.label).toList();

  group('ranking', () {
    test('an empty query keeps menu order', () {
      // The palette's first job is "show me where I can go". Re-sorting an
      // unfiltered list would throw away the ordering the menu deliberately
      // chose.
      expect(labels(''), destinations.map((d) => d.label).toList());
      expect(labels('   '), destinations.map((d) => d.label).toList());
    });

    test('a prefix wins outright', () {
      expect(labels('trans').first, 'Transport');
      expect(labels('set').first, 'Settings');
    });

    test('initials find a two-word destination', () {
      // "mu" for Manage Users is the whole reason a palette beats a menu.
      expect(labels('mu').first, 'Manage Users');
      expect(labels('ml').first, 'Manage Library');
      expect(labels('cs').first, 'Class Schedule');
    });

    test('subsequence matching works, and non-matches are excluded', () {
      expect(labels('dshbrd'), ['Dashboard']);
      expect(labels('zzz'), isEmpty);
    });

    test('word starts outrank letters buried mid-word', () {
      // 'ma' starts a word in "Manage Users"/"Manage Library" and appears only
      // inside "My Attendance"... which also has 'a' after 'M'. The two Manage
      // entries must come first.
      final ranked = labels('ma');
      expect(ranked.take(2), containsAll(['Manage Users', 'Manage Library']));
    });

    test('case is irrelevant', () {
      expect(labels('TRANSPORT').first, 'Transport');
      expect(labels('TrAnS').first, 'Transport');
    });

    test('spaces in the query are ignored, not treated as a failure', () {
      // Someone typing "manage users" should not do worse than "manageusers".
      expect(labels('manage users').first, startsWith('Manage'));
    });

    test('ordering is stable for equal scores', () {
      // A palette whose rows reshuffle between identical queries is one you
      // cannot build muscle memory for.
      final a = labels('a');
      final b = labels('a');
      expect(a, b);
    });

    test('an ampersand counts as a word boundary', () {
      // "Lost & Found" — 'f' starts a word even though '&' precedes it.
      expect(labels('lf').first, 'Lost & Found');
    });
  });

  group('the published destination list', () {
    test('starts empty, so a palette opened before permissions resolve shows '
        'nothing rather than everything', () {
      // The failure direction matters: a permission-derived list that defaults
      // to "all" would advertise admin destinations to a student for the
      // fraction of a second before the role loads.
      expect(navDestinations.value, isEmpty);
    });
  });
}
