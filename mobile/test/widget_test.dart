import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenbill/main.dart';

void main() {
  testWidgets('EvenBillApp renders title and groups overview', (WidgetTester tester) async {
    await tester.pumpWidget(const EvenBillApp());
    await tester.pumpAndSettle();

    // Verify app brand is rendered
    expect(find.text('EvenBill'), findsOneWidget);

    // Verify balance card summary
    expect(find.text('Overall, you are owed'), findsOneWidget);

    // Verify Add Expense floating action button is present
    expect(find.text('Add Expense'), findsOneWidget);

    // Verify groups list header
    expect(find.text('Your Groups'), findsOneWidget);
  });
}
