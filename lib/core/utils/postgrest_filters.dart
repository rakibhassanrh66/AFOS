/// Safe construction of PostgREST filter strings from user-typed text.
///
/// Exists because building `or=(...)` by string interpolation is a live defect
/// generator, not a theoretical one. All behaviour below was verified against
/// this project's actual PostgREST instance, not inferred from docs.
library;

/// Escapes a value used as a PostgREST `ilike` **parameter** —
/// `client.from(t).ilike(col, pattern)` — where the pattern travels as its own
/// URL-encoded query parameter.
///
/// `%` and `_` are SQL LIKE wildcards, so an unescaped query like "100%" or
/// "a_b" matches far more than the user typed. Backslash is escaped first, or
/// it would double-escape the characters added after it.
///
/// Do **not** use this for [orIlike] — see the note there about why the LIKE
/// escape does not survive that path.
String escapeLikePattern(String q) =>
    q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

/// Builds the argument for `.or(...)`: [query] matched with `ilike` against
/// every column in [columns].
///
/// **The bug this exists to prevent.** PostgREST parses `or=(...)` as an
/// *expression* — commas separate conditions, parentheses group them — so a raw
/// value containing either corrupts the filter. Verified live:
///
///   * comma — `or=(title.ilike.%Dune, Part%,...)` →
///     `PGRST100 "failed to parse logic tree"`. Every call site wraps its search
///     in `catch (_) {}`, so this surfaced as *silently empty results*.
///   * parenthesis — `or=(name.ilike.%Railgate (South%,...)` did **not** error.
///     It parsed as grammar and returned rows matching something else entirely,
///     which is worse than failing.
///
/// This matters for ordinary content, not edge cases: 10 of 18 rows in `books`
/// have a comma or parenthesis in the title or author.
///
/// Double-quoting the value makes both characters literal. Inside quotes, `\`
/// and `"` must themselves be escaped.
///
/// **Deliberate limitation, measured rather than assumed:** the LIKE escape from
/// [escapeLikePattern] does *not* survive this path — a probe with `\_` inside a
/// quoted value still behaved as a wildcard, because PostgREST consumes the
/// backslash while unescaping the quoted string. `%`, `_` and `*` therefore stay
/// wildcards here. That only ever *broadens* a search, so it is accepted; the
/// grammar corruption above is the defect worth fixing. When exact wildcard
/// handling matters, fetch and filter client-side instead (see the transport
/// source in `global_search_screen.dart`).
String orIlike(List<String> columns, String query) {
  final value = query.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return columns.map((c) => '$c.ilike."%$value%"').join(',');
}
