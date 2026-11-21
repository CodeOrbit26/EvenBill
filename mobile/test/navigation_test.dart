import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenbill/main.dart';
import 'package:evenbill/core/di/injection.dart';
import 'package:evenbill/screens/shell/app_navigation_shell.dart';
import 'package:evenbill/core/widgets/buttons/primary_button.dart';
import 'mocks/mock_repositories.dart';

void main() {
  setUp(() {
    Injection.setMockRepositories(
      auth: MockAuthRepository(),
      group: MockGroupRepository(),
      expense: MockExpenseRepository(),
      settlement: MockSettlementRepository(),
      friend: MockFriendRepository(),
      activity: MockActivityRepository(),
      subscription: MockSubscriptionRepository(),
    );
  });

  tearDown(() {
    Injection.reset();
  });

  testWidgets('Full navigation flow from Onboarding to Shell and Tab switching', (tester) async {
    await tester.pumpWidget(const EvenBillApp());
    // Advance splash screen timer (2200ms)
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pumpAndSettle();

    // Verify Onboarding screen is shown
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);

    // Tap Sign In to go to SignInScreen
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    // Verify Sign In screen is shown
    expect(find.text('Sign In to EvenBill'), findsOneWidget);

    // Enter credentials and tap Sign In
    await tester.enterText(find.byType(TextField).first, 'abhay.gupta@gmail.com');
    await tester.enterText(find.byType(TextField).last, 'Password123!');
    final signInButton = find.widgetWithText(PrimaryButton, 'Sign In');
    await tester.ensureVisible(signInButton);
    await tester.tap(signInButton);
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

    // Switch to Settings Tab (Destination index 2)
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Account & Settings'), findsOneWidget);
    expect(find.text('Abhay Gupta'), findsOneWidget);
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

    // Open Activity feed from top-right AppBar action
    expect(find.byTooltip('Activity'), findsOneWidget);
    await tester.tap(find.byTooltip('Activity'));
    await tester.pumpAndSettle();
    expect(find.text('Activity & Audit Feed'), findsOneWidget);

    // Back from Activity feed
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Recent Expenses'), findsOneWidget);

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
