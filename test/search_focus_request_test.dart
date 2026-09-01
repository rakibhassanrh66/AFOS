import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/features/search/presentation/global_search_screen.dart';

/// The double-tap-to-search shortcut has to work EVERY time, not once.
///
/// THE BUG THIS LOCKS DOWN. The shortcut was implemented as a navigation:
/// `context.go('/search?focus=1')`. The first double tap set that URL and the
/// field focused. Every double tap after produced an IDENTICAL URI, so
/// GoRouter had nothing to rebuild, the widget's `autofocus` never changed
/// from true to true, and the keyboard never appeared again. It looked like
/// the feature had never worked at all.
///
/// It was also the wrong model. By the time the second tap lands, the search
/// screen is already open — the user is not asking to navigate, they are
/// asking for the cursor. So it is a repeatable signal now, and these tests
/// assert the two properties the route-based version could not hold:
/// it fires again, and a request survives the gap before the screen mounts.
void main() {
  setUp(SearchFocusRequest.consume);

  test('fires every time, not just once', () {
    final seen = <int>[];
    void listener() => seen.add(SearchFocusRequest.tick.value);
    SearchFocusRequest.tick.addListener(listener);
    addTearDown(() => SearchFocusRequest.tick.removeListener(listener));

    SearchFocusRequest.fire();
    SearchFocusRequest.fire();
    SearchFocusRequest.fire();

    expect(seen.length, 3,
        reason: 'the URL-based version notified once and then went quiet');
  });

  test('a request survives the gap before the screen mounts', () {
    // The first tap of the pair starts the navigation; the second lands while
    // the route is still building, so nothing is listening yet. The screen has
    // to be able to ask "was one just made?" when it appears.
    SearchFocusRequest.fire();
    expect(SearchFocusRequest.pending(), isTrue);
  });

  test('consuming it stops the next screen inheriting a stale focus', () {
    SearchFocusRequest.fire();
    SearchFocusRequest.consume();
    expect(SearchFocusRequest.pending(), isFalse);
  });

  test('an old request is ignored', () {
    SearchFocusRequest.fire();
    // A request from minutes ago must not steal focus when the user later
    // opens Search deliberately.
    expect(SearchFocusRequest.pending(window: Duration.zero), isFalse);
  });

  test('no request at all is not pending', () {
    expect(SearchFocusRequest.pending(), isFalse);
  });
}
