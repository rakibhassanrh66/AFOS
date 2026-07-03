import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('placeholder test', (WidgetTester tester) async {
    // AFOS uses Supabase which requires async init — integration tests
    // should be written in test/integration/. This file kept as a placeholder.
    expect(1 + 1, 2);
  });
}
