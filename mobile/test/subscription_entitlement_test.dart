import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenbill/core/di/injection.dart';
import 'package:evenbill/core/models/entitlement_model.dart';
import 'package:evenbill/core/models/expense_model.dart';
import 'package:evenbill/core/widgets/buttons/primary_button.dart';
import 'package:evenbill/screens/subscription/pro_paywall_screen.dart';
import 'package:evenbill/screens/expenses/add_edit_expense_screen.dart';
import 'package:evenbill/screens/profile/profile_settings_screen.dart';
import 'mocks/mock_repositories.dart';

class FailingMockExpenseRepository extends MockExpenseRepository {
  bool failWithLimitReached = false;

  @override
  Future<ExpenseModel> createExpense({
    String? idempotencyKey,
    String? groupId,
    required String description,
    required double totalAmount,
    String currency = 'USD',
    String splitType = 'EQUAL',
    String category = 'GENERAL',
    DateTime? expenseDate,
    String? notes,
    List<PayerModel>? payers,
    List<String>? participantIds,
    List<SplitModel>? splits,
    Map<String, double>? percentages,
    Map<String, double>? shares,
    Map<String, double>? adjustments,
    List<ItemizedItemInput>? items,
    double tax = 0.0,
    double tip = 0.0,
    double fee = 0.0,
    double discount = 0.0,
    String transactionType = 'EXPENSE',
    String? originalExpenseId,
    double? exchangeRate,
    String? exchangeRateSource,
  }) async {
    if (failWithLimitReached) {
      throw Exception('HTTP 403: FEATURE_LOCKED: DAILY_EXPENSE_CREATION daily limit reached');
    }
    return super.createExpense(
      idempotencyKey: idempotencyKey,
      groupId: groupId,
      description: description,
      totalAmount: totalAmount,
      currency: currency,
      splitType: splitType,
      category: category,
      expenseDate: expenseDate,
      notes: notes,
      payers: payers,
      participantIds: participantIds,
      splits: splits,
      percentages: percentages,
      shares: shares,
      adjustments: adjustments,
      items: items,
      tax: tax,
      tip: tip,
      fee: fee,
      discount: discount,
      transactionType: transactionType,
      originalExpenseId: originalExpenseId,
      exchangeRate: exchangeRate,
      exchangeRateSource: exchangeRateSource,
    );
  }
}

void main() {
  late MockAuthRepository mockAuth;
  late MockGroupRepository mockGroup;
  late FailingMockExpenseRepository mockExpense;
  late MockSettlementRepository mockSettlement;
  late MockFriendRepository mockFriend;
  late MockActivityRepository mockActivity;
  late MockSubscriptionRepository mockSubscription;

  setUp(() {
    mockAuth = MockAuthRepository();
    mockGroup = MockGroupRepository();
    mockExpense = FailingMockExpenseRepository();
    mockSettlement = MockSettlementRepository();
    mockFriend = MockFriendRepository();
    mockActivity = MockActivityRepository();
    mockSubscription = MockSubscriptionRepository();

    Injection.setMockRepositories(
      auth: mockAuth,
      group: mockGroup,
      expense: mockExpense,
      settlement: mockSettlement,
      friend: mockFriend,
      activity: mockActivity,
      subscription: mockSubscription,
    );
  });

  tearDown(() {
    Injection.reset();
  });

  void setMobileScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('Paywall screen displays honest value propositions, pricing toggle, and handles upgrade', (tester) async {
    setMobileScreen(tester);
    bool backCalled = false;
    bool upgradedCalled = false;

    await tester.pumpWidget(MaterialApp(
      home: ProPaywallScreen(
        onBack: () => backCalled = true,
        onUpgradeSuccess: () => upgradedCalled = true,
      ),
    ));
    await tester.pumpAndSettle();

    // Verify key titles and honest features without countdowns
    expect(find.text('EvenBill Pro'), findsWidgets);
    expect(find.text('Unlock Unlimited Power'), findsOneWidget);
    expect(find.text('Unlimited Daily Expenses'), findsOneWidget);
    expect(find.text('Unlimited AI Receipt Itemization'), findsOneWidget);
    expect(find.text('Cross-Group Global Debt Simplification'), findsOneWidget);
    expect(find.text('SAVE 33%'), findsOneWidget);

    // Switch between Annual and Monthly billing
    await tester.tap(find.text('Monthly (\$4.99/mo)'));
    await tester.pumpAndSettle();
    expect(find.text('Upgrade to Pro (\$4.99/mo)'), findsOneWidget);

    await tester.tap(find.textContaining('Annual'));
    await tester.pumpAndSettle();
    expect(find.text('Upgrade to Pro (\$39.99/yr)'), findsOneWidget);

    // Scroll down to bring upgrade button into view
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();

    // Tap upgrade
    await tester.tap(find.widgetWithText(PrimaryButton, 'Upgrade to Pro (\$39.99/yr)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(upgradedCalled, isTrue);
    expect(backCalled, isTrue);
    expect(mockSubscription.currentEntitlement.isPro, isTrue);
  });

  testWidgets('AddEditExpenseScreen shows Free allowance banner and preserves form data when limit reached', (tester) async {
    setMobileScreen(tester);

    // Configure expense repo to fail with limit reached error
    mockExpense.failWithLimitReached = true;

    await tester.pumpWidget(MaterialApp(
      home: AddEditExpenseScreen(
        onSaved: () {},
        onBack: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // Verify Free allowance indicator banner is visible
    expect(find.textContaining('Free Plan: 4 of 4 new expenses remaining today'), findsOneWidget);

    // Enter expense details
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '175.50');
    await tester.enterText(fields.at(1), 'Weekend Villa Booking');
    await tester.pumpAndSettle();

    // Tap Save
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Limit reached dialog appears
    expect(find.text('Daily Limit Reached'), findsOneWidget);
    expect(find.textContaining('Your draft and allocations are preserved. No data will be lost.'), findsOneWidget);

    // Tap "Keep Draft"
    await tester.tap(find.text('Keep Draft'));
    await tester.pumpAndSettle();

    // Verify dialog dismissed AND all entered data is completely preserved
    expect(find.text('Daily Limit Reached'), findsNothing);
    expect(find.text('175.50'), findsOneWidget);
    expect(find.text('Weekend Villa Booking'), findsOneWidget);
  });

  testWidgets('ProfileSettingsScreen displays subscription status and updates after upgrade', (tester) async {
    setMobileScreen(tester);

    await tester.pumpWidget(MaterialApp(
      home: ProfileSettingsScreen(
        currentThemeMode: ThemeMode.light,
        onThemeChanged: (_) {},
        onOpenPaywall: () {},
        onSignOut: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // Initial state: Free plan with remaining count
    expect(find.textContaining('Free Plan • 4 of 4 left today'), findsOneWidget);
    expect(find.text('Upgrade to EvenBill Pro'), findsOneWidget);

    // Simulate user upgrading
    await mockSubscription.mockUpgrade(tier: 'PRO_ANNUAL');
    mockAuth.currentUser = mockAuth.currentUser.copyWith(isPro: true);

    // Re-render with new key to re-mount state
    await tester.pumpWidget(MaterialApp(
      home: ProfileSettingsScreen(
        key: const Key('profile_settings_upgraded'),
        currentThemeMode: ThemeMode.light,
        onThemeChanged: (_) {},
        onOpenPaywall: () {},
        onSignOut: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // Updated state: Pro member unlimited
    expect(find.textContaining('Pro Member • Unlimited'), findsOneWidget);
  });
}
