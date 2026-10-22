import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenbill/main.dart';
import 'package:evenbill/screens/shell/app_navigation_shell.dart';

void main() {
  testWidgets('Full navigation flow from Onboarding to Shell and Tab switching', (tester) async {
    await tester.pumpWidget(const EvenBillApp());
    // Advance splash screen timer (2200ms)
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pumpAndSettle();

    // Verify Onboarding screen is shown
    expect(find.text('Explore Demo'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    // Tap Explore Demo to jump straight into authenticated shell
    await tester.tap(find.text('Explore Demo'));
    await tester.pumpAndSettle();

    // Verify we are in the main shell on the Overview tab
    expect(find.byType(AppNavigationShell), findsOneWidget);
    expect(find.text('Recent Expenses'), findsOneWidget);
    expect(find.text('Add Expense'), findsOneWidget);

    // Switch to Groups Tab (Destination index 1)
    await tester.tap(find.text('Groups'));
    await tester.pumpAndSettle();
    expect(find.text('Active Groups (4)'), findsOneWidget);
    expect(find.text('Apartment 404'), findsOneWidget);

    // Switch to Friends Tab (Destination index 2)
    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(find.text('All Friends (5)'), findsOneWidget);
    expect(find.text('Elena Rostova'), findsOneWidget);

    // Switch to Activity Tab (Destination index 3)
    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Activity & Audit Feed'), findsOneWidget);

    // Switch to Settings Tab (Destination index 4)
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Account & Settings'), findsOneWidget);
    expect(find.text('Abhay Sharma'), findsOneWidget);
    expect(find.text('Upgrade to EvenBill Pro'), findsOneWidget);

    // Open Pro Paywall from settings banner
    await tester.tap(find.text('Upgrade to EvenBill Pro'));
    await tester.pumpAndSettle();
    expect(find.text('EvenBill Pro'), findsOneWidget);
    expect(find.text('Unlimited AI Receipt Itemization'), findsOneWidget);

    // Close Paywall
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    // Switch back to Overview
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();

    // Tap Add Expense FAB
    await tester.tap(find.text('Add Expense'));
    await tester.pumpAndSettle();
    expect(find.text('Description'), findsOneWidget);
    expect(find.text('Split method'), findsOneWidget);

    // Close Add Expense
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
  });
}
