import 'package:app_availability_guard_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offline example opens and dismisses optional update', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Optional update'));
    await tester.pumpAndSettle();
    expect(find.text('New update available'), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.text('App guard example'), findsOneWidget);
    await tester.tap(find.text('Mandatory update'));
    await tester.pump();
    expect(find.text('Update required'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('App guard example'), findsOneWidget);
  });
}
