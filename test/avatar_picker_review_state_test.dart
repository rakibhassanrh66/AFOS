import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:afos_v7/shared/widgets/avatar_picker.dart';
import 'package:afos_v7/shared/widgets/pill_badge.dart';

/// AvatarPicker now stages a submitted photo for admin review instead of
/// writing avatar_url directly (Phase A, mandatory-photo-with-review). This
/// pins the one thing that had no coverage before: whether the review state
/// actually renders, since the RPC round trip is covered on the SQL side.
void main() {
  Widget harness({String? reviewStatus, String? reviewReason}) => MaterialApp(
        home: Scaffold(
          body: AvatarPicker(
            avatarUrl: null,
            initials: 'AB',
            reviewStatus: reviewStatus,
            reviewReason: reviewReason,
            onChanged: (_) {},
          ),
        ),
      );

  testWidgets('no badge when there is nothing pending or rejected', (tester) async {
    await tester.pumpWidget(harness(reviewStatus: 'none'));
    expect(find.byType(PillBadge), findsNothing);
  });

  testWidgets('shows a pending badge while a photo awaits review', (tester) async {
    await tester.pumpWidget(harness(reviewStatus: 'pending'));
    expect(find.byType(PillBadge), findsOneWidget);
    expect(find.textContaining('PENDING'), findsOneWidget);
  });

  testWidgets('shows the rejection reason when a photo was declined', (tester) async {
    await tester.pumpWidget(harness(reviewStatus: 'rejected', reviewReason: 'Not a formal photo'));
    expect(find.byType(PillBadge), findsOneWidget);
    expect(find.textContaining('REJECTED'), findsOneWidget);
    expect(find.text('Not a formal photo'), findsOneWidget);
  });

  testWidgets('no badge once approved', (tester) async {
    await tester.pumpWidget(harness(reviewStatus: 'approved'));
    expect(find.byType(PillBadge), findsNothing);
  });
}
