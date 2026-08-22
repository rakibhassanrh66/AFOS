import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/features/admin/presentation/widgets/user_group_tree.dart';

/// Tests the REAL UserGroupTree, never a copy of it — a copied widget cannot
/// regress. All data here is synthetic; this repo is public.
void main() {
  const summer68 = UserGroup(
      l1Key: '2023|summer', l1Label: 'Summer 2023',
      l2Key: '68', l2Label: 'Batch 68', count: 3);
  const unset68 = UserGroup(
      l1Key: 'unset', l1Label: 'Intake not set',
      l2Key: '68', l2Label: 'Batch 68', count: 5);
  const unset63 = UserGroup(
      l1Key: 'unset', l1Label: 'Intake not set',
      l2Key: '63', l2Label: 'Batch 63', count: 2);

  Widget host(
    List<UserGroup> groups,
    Future<List<Map<String, dynamic>>> Function(UserGroup) rowsFor,
  ) =>
      MaterialApp(
        home: Scaffold(
          body: UserGroupTree(
            groups: groups,
            rowsFor: rowsFor,
            itemBuilder: (u) => Text('user:${u['full_name']}'),
          ),
        ),
      );

  test('the same batch label under two intakes is two different groups', () {
    // "Batch 68" appears under Summer 2023 AND under Intake not set. If
    // identity were the label, opening one would open the other and show it
    // the wrong people.
    expect(summer68.id, isNot(unset68.id));
    expect(unset68.id, isNot(unset63.id));
  });

  test('fromJson survives a group with nulls', () {
    final g = UserGroup.fromJson(const {'count': 4});
    expect(g.l1Key, 'unset');
    expect(g.l1Label, 'Not set');
    expect(g.count, 4);
  });

  testWidgets('a level-1 header sums the counts of its children',
      (tester) async {
    await tester.pumpWidget(host(
        const [summer68, unset68, unset63], (_) async => const []));
    await tester.pumpAndSettle();

    expect(find.text('SUMMER 2023'), findsOneWidget);
    expect(find.text('INTAKE NOT SET'), findsOneWidget);
    // 5 + 2 for the two "Intake not set" batches, summed on the header.
    expect(find.text('7'), findsOneWidget);
    expect(find.text('3'), findsWidgets); // Summer 2023's own total and count
  });

  testWidgets('rows are not fetched until a group is opened', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(const [summer68], (_) async {
      calls++;
      return [
        {'id': '1', 'full_name': 'Ada'}
      ];
    }));
    await tester.pumpAndSettle();

    // The whole point of grouping thousands of people: opening the screen
    // must not download anybody.
    expect(calls, 0);
    expect(find.text('user:Ada'), findsNothing);

    await tester.tap(find.text('Batch 68'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('user:Ada'), findsOneWidget);
  });

  testWidgets('a failed fetch shows an error, never an empty group',
      (tester) async {
    await tester.pumpWidget(host(const [summer68],
        (_) async => throw Exception('network is down')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Batch 68'));
    await tester.pumpAndSettle();

    // "No one here" and "we could not ask" are different answers, and this
    // screen has faked the first one before.
    expect(find.textContaining('Could not load'), findsOneWidget);
    expect(find.textContaining('No one in this group'), findsNothing);
  });

  testWidgets('an opened group that really is empty says so', (tester) async {
    await tester.pumpWidget(host(const [summer68], (_) async => const []));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Batch 68'));
    await tester.pumpAndSettle();

    expect(find.text('No one in this group.'), findsOneWidget);
  });

  testWidgets('collapsing hides the rows without refetching', (tester) async {
    var calls = 0;
    await tester.pumpWidget(host(const [summer68], (_) async {
      calls++;
      return [
        {'id': '1', 'full_name': 'Ada'}
      ];
    }));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Batch 68'));
    await tester.pumpAndSettle();
    expect(find.text('user:Ada'), findsOneWidget);

    await tester.tap(find.text('Batch 68'));
    await tester.pumpAndSettle();
    expect(find.text('user:Ada'), findsNothing);

    await tester.tap(find.text('Batch 68'));
    await tester.pumpAndSettle();
    expect(find.text('user:Ada'), findsOneWidget);
    expect(calls, 1, reason: 'rows were cached, so reopening must not refetch');
  });
}
