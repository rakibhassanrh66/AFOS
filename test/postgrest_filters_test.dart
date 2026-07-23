import 'package:flutter_test/flutter_test.dart';
import 'package:afos_v7/core/utils/postgrest_filters.dart';

/// Guards for the PostgREST filter-string bugs found 2026-07-22.
///
/// Every expectation here mirrors behaviour verified against the project's live
/// PostgREST instance, so a "simplification" that drops the quoting fails here
/// instead of silently emptying the library search again.
void main() {
  group('escapeLikePattern — for ilike passed as a parameter', () {
    test('escapes the SQL LIKE wildcards', () {
      expect(escapeLikePattern('100%'), r'100\%');
      expect(escapeLikePattern('a_b'), r'a\_b');
    });

    test('escapes backslash first so later escapes are not doubled', () {
      expect(escapeLikePattern(r'a\b'), r'a\\b');
      expect(escapeLikePattern(r'50%\_'), r'50\%\\\_');
    });

    test('leaves ordinary text alone', () {
      expect(escapeLikePattern('Mirpur 10'), 'Mirpur 10');
    });
  });

  group('orIlike — the or=() grammar hazard', () {
    test('quotes every value', () {
      // Unquoted is what broke: PostgREST parses or=() as an expression.
      expect(orIlike(const ['title'], 'Dune'), 'title.ilike."%Dune%"');
    });

    test('a comma stays inside the quotes rather than splitting conditions', () {
      // Live, the unquoted form returned PGRST100 "failed to parse logic tree",
      // which every call site swallowed as an empty result.
      final f = orIlike(const ['title', 'author'], 'Dune, Part One');
      expect(f, 'title.ilike."%Dune, Part One%",author.ilike."%Dune, Part One%"');
      // Exactly one condition separator per extra column — the comma in the
      // value must NOT create another.
      expect(RegExp(r'\.ilike\.').allMatches(f).length, 2);
    });

    test('parentheses stay inside the quotes', () {
      // Unquoted, these did not error — they parsed as grammar and returned the
      // WRONG rows, which is worse.
      expect(orIlike(const ['name'], 'Railgate (South Bus Stop)'),
          'name.ilike."%Railgate (South Bus Stop)%"');
    });

    test('escapes the quote character so it cannot terminate the value early', () {
      expect(orIlike(const ['title'], 'say "hi"'), r'title.ilike."%say \"hi\"%"');
    });

    test('escapes backslash before quotes, so an escape cannot be forged', () {
      // A trailing backslash must not escape the closing quote.
      expect(orIlike(const ['title'], r'a\'), r'title.ilike."%a\\%"');
      expect(orIlike(const ['t'], r'a\"b'), r't.ilike."%a\\\"b%"');
    });

    test('joins multiple columns with a single comma each', () {
      expect(orIlike(const ['title', 'author', 'isbn'], 'x'),
          'title.ilike."%x%",author.ilike."%x%",isbn.ilike."%x%"');
    });

    test('handles an empty query without producing malformed syntax', () {
      expect(orIlike(const ['title'], ''), 'title.ilike."%%"');
    });
  });
}
