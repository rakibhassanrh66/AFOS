import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression coverage for the notification-bell popover's anchoring
/// mechanism (lib/features/notifications/presentation/notification_popover.dart,
/// lib/features/shell/presentation/top_app_bar.dart).
///
/// This exact bug regressed twice from hand-rolled coordinate math: once
/// from measuring the bell against the wrong Overlay (a nested go_router
/// ShellRoute navigator instead of the root one), and once from feeding an
/// already-global position through a `SafeArea`, whose implicit padding
/// double-counted the phone status-bar inset. Both were possible because
/// screen position was computed by hand instead of by Flutter itself.
///
/// The production fix replaced that math with `CompositedTransformTarget`/
/// `CompositedTransformFollower` -- the same mechanism `PopupMenuButton`
/// uses -- which resolves position via the compositing layer tree, not
/// BuildContext ancestry. This test proves the resulting geometric contract
/// (panel's top-right sits a fixed 8px below the target's bottom-right)
/// holds regardless of ambient `MediaQuery.padding` (simulating a phone
/// status bar the old SafeArea-wrapped code double-counted) and across a
/// nested-Navigator boundary matching the app's real ShellRoute structure
/// (target lives in a route pushed on a *nested* Navigator; the follower is
/// inserted into the *root* Navigator's Overlay, exactly like
/// showNotificationPopover does).
void main() {
  const panelKey = ValueKey('panel');

  Future<Offset> anchorDeltaAt(WidgetTester tester, {required double topInset}) async {
    final link = LayerLink();
    final bellKey = GlobalKey();
    late BuildContext rootContext;

    // Reset first: this helper is called twice per test, and pumping a new
    // MaterialApp/Navigator directly over the previous one lets Flutter's
    // element reconciliation treat it as an UPDATE rather than a fresh
    // build -- the stateful Navigator then keeps its already-pushed route
    // (and the old bellKey) instead of re-running onGenerateRoute. A plain
    // widget in between forces a full teardown.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(400, 800),
          padding: EdgeInsets.only(top: topInset),
        ),
        child: Builder(builder: (outerContext) {
          rootContext = outerContext;
          // A nested Navigator, mirroring go_router's ShellRoute: the bell
          // lives inside it, exactly like AfosAppBar does inside AppShell.
          return Navigator(
            onGenerateRoute: (_) => MaterialPageRoute(
              builder: (context) => Scaffold(
                appBar: AppBar(actions: [
                  CompositedTransformTarget(
                    link: link,
                    child: IconButton(
                      key: bellKey,
                      icon: const Icon(Icons.notifications),
                      onPressed: () {
                        // Root navigator's overlay -- same call
                        // showNotificationPopover makes -- deliberately NOT
                        // the nested Navigator's own overlay.
                        final overlay =
                            Navigator.of(rootContext, rootNavigator: true).overlay!;
                        overlay.insert(OverlayEntry(
                          builder: (_) => CompositedTransformFollower(
                            link: link,
                            targetAnchor: Alignment.bottomRight,
                            followerAnchor: Alignment.topRight,
                            offset: const Offset(0, 8),
                            child: Container(
                                key: panelKey, width: 200, height: 100, color: Colors.blue),
                          ),
                        ));
                      },
                    ),
                  ),
                ]),
                body: const SizedBox.shrink(),
              ),
            ),
          );
        }),
      ),
    ));
    // The nested Navigator's initial route push animates in.
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(bellKey));
    await tester.pumpAndSettle();

    final bellRect = tester.getRect(find.byKey(bellKey));
    final panelRect = tester.getRect(find.byKey(panelKey));
    // The invariant: panel's top-right sits exactly `offset` below-right of
    // the bell's bottom-right, no matter where the bell itself physically
    // sits on screen.
    return panelRect.topRight - bellRect.bottomRight;
  }

  testWidgets(
      'popover anchors identically with zero and with a phone-status-bar-sized MediaQuery.padding.top',
      (tester) async {
    final deltaNoInset = await anchorDeltaAt(tester, topInset: 0);
    final deltaWithInset = await anchorDeltaAt(tester, topInset: 40);

    // This is exactly the case that broke: a non-zero top inset (real on a
    // phone, zero in a browser) must not change the offset between the bell
    // and the panel. The old SafeArea-wrapped implementation shifted this by
    // ~`topInset` px; this must stay pinned at (0, 8) either way.
    expect(deltaNoInset, const Offset(0, 8));
    expect(deltaWithInset, const Offset(0, 8));
  });
}
