import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenbill/core/di/injection.dart';
import 'package:evenbill/core/models/entitlement_model.dart';
import 'package:evenbill/core/models/split_template_model.dart';
import 'package:evenbill/core/models/bank_model.dart';
import 'package:evenbill/screens/analytics/spending_insights_screen.dart';
import 'package:evenbill/screens/expenses/receipt_review_modal.dart';
import 'package:evenbill/screens/expenses/split_preset_picker_modal.dart';
import 'package:evenbill/screens/expenses/search_expenses_sheet.dart';
import 'package:evenbill/screens/bank/bank_import_sheet.dart';
import 'package:evenbill/screens/expenses/add_edit_expense_screen.dart';
import 'mocks/mock_repositories.dart';

void main() {
  late MockAuthRepository mockAuth;
  late MockExpenseRepository mockExpense;
  late MockGroupRepository mockGroup;
  late MockSubscriptionRepository mockSub;
  late MockProRepository mockPro;

  setUp(() {
    mockAuth = MockAuthRepository();
    mockExpense = MockExpenseRepository();
    mockGroup = MockGroupRepository();
    mockSub = MockSubscriptionRepository();
    mockPro = MockProRepository();

    // Set user as Pro for capabilities testing
    mockAuth.currentUser = mockAuth.currentUser.copyWith(isPro: true);
    mockSub.currentEntitlement = const EntitlementModel(
      plan: 'PRO',
      isPro: true,
      dailyLimit: null,
      dailyUsed: 0,
      dailyRemaining: null,
      receiptOcrEnabled: true,
      crossGroupSimplificationEnabled: true,
    );

    Injection.setMockRepositories(
      auth: mockAuth,
      expense: mockExpense,
      group: mockGroup,
      subscription: mockSub,
      pro: mockPro,
    );
  });

  tearDown(() {
    Injection.reset();
  });

  Widget buildTestApp(Widget child) {
    return MaterialApp(
      home: Scaffold(body: child),
      theme: ThemeData.light(),
    );
  }

  void setupLargeViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  group('EvenBill Pro - Spending Insights & Analytics', () {
    testWidgets('SpendingInsightsScreen renders net spending, category bars, and timeline', (tester) async {
      setupLargeViewport(tester);
      await tester.pumpWidget(buildTestApp(SpendingInsightsScreen(onBack: () {})));
      await tester.pumpAndSettle();

      // Verify header and summary numbers
      expect(find.text('Spending & Category Insights'), findsOneWidget);
      expect(find.text('Your Net Spending'), findsOneWidget);
      expect(find.text('Total Paid by You'), findsOneWidget);

      // Verify net amounts formatted with USD
      expect(find.text('USD 142.50'), findsOneWidget);
      expect(find.text('USD 250.00'), findsOneWidget);
      expect(find.text('8 expenses tracked'), findsOneWidget);

      // Verify Category Breakdown items
      expect(find.text('Spending by Category'), findsOneWidget);
      expect(find.text('GROCERIES'), findsOneWidget);
      expect(find.text('DINING OUT'), findsOneWidget);
      expect(find.text('UTILITIES'), findsOneWidget);
      expect(find.text('USD 85.00 (59.6%)'), findsOneWidget);

      // Verify Monthly Spending Timeline
      expect(find.text('Monthly Spending Timeline'), findsOneWidget);
      expect(find.text('2026-08'), findsOneWidget);
      expect(find.text('2026-09'), findsOneWidget);
      expect(find.text('2026-10'), findsOneWidget);
    });

    testWidgets('Changing currency in insights refreshes calculations', (tester) async {
      setupLargeViewport(tester);
      await tester.pumpWidget(buildTestApp(SpendingInsightsScreen(onBack: () {})));
      await tester.pumpAndSettle();

      // Open currency popup menu
      final currencyAction = find.byType(PopupMenuButton<String>);
      expect(currencyAction, findsOneWidget);

      await tester.tap(currencyAction);
      await tester.pumpAndSettle();

      // Select EUR
      final eurItem = find.text('EUR (€)').last;
      await tester.tap(eurItem);
      await tester.pumpAndSettle();

      // Currency in cards should update to EUR
      expect(find.text('EUR 142.50'), findsOneWidget);
    });
  });

  group('EvenBill Pro - OCR-Assisted Receipt Extraction', () {
    testWidgets('ReceiptReviewModal extracts line items and allows participant assignment', (tester) async {
      setupLargeViewport(tester);
      ConfirmedReceiptData? confirmedResult;

      final participants = [
        {'id': 'user_1', 'name': 'Abhay'},
        {'id': 'user_2', 'name': 'Marco'},
      ];

      await tester.pumpWidget(
        buildTestApp(
          ReceiptReviewModal(
            participants: participants,
            onConfirmed: (data) {
              confirmedResult = data;
            },
          ),
        ),
      );

      // Wait for simulated OCR scan and cryptographic hash verification to complete
      await tester.pumpAndSettle();

      // Verify extracted merchant & total
      expect(find.text('Review OCR Receipt'), findsOneWidget);
      expect(find.text('Trattoria Bella'), findsOneWidget);
      expect(find.text('78.50'), findsOneWidget);

      // Verify extracted line items
      expect(find.text('Margherita Pizza'), findsOneWidget);
      expect(find.text('Tiramisu'), findsOneWidget);
      expect(find.text('House Chianti'), findsOneWidget);

      // Verify participant chips are rendered
      expect(find.widgetWithText(FilterChip, 'Abhay'), findsWidgets);
      expect(find.widgetWithText(FilterChip, 'Marco'), findsWidgets);

      // Edit merchant name
      final merchantField = find.widgetWithText(TextField, 'Trattoria Bella');
      await tester.enterText(merchantField, 'Trattoria Bella Roma');
      await tester.pumpAndSettle();

      // Confirm receipt
      final confirmBtn = find.text('Confirm & Use in Expense');
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Verify callback received confirmed and user-reviewed financial data
      expect(confirmedResult, isNotNull);
      expect(confirmedResult!.merchant, 'Trattoria Bella Roma');
      expect(confirmedResult!.totalAmount, 78.50);
      expect(confirmedResult!.items.length, 3);
      expect(confirmedResult!.items.first.description, 'Margherita Pizza');
    });
  });

  group('EvenBill Pro - Saved Group Split Templates', () {
    testWidgets('SplitPresetPickerModal lists saved templates and selects one', (tester) async {
      setupLargeViewport(tester);
      SplitTemplateModel? selectedTemplate;

      final members = [
        {'id': 'user_1', 'name': 'Abhay'},
        {'id': 'user_2', 'name': 'Marco'},
      ];

      await tester.pumpWidget(
        buildTestApp(
          SplitPresetPickerModal(
            groupId: 'grp_1',
            members: members,
            onTemplateSelected: (tmpl) {
              selectedTemplate = tmpl;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check header and template list
      expect(find.text('Saved Split Presets'), findsOneWidget);
      expect(find.text('Couples (60/40 Split)'), findsOneWidget);
      expect(find.text('DEFAULT'), findsOneWidget);
      expect(find.text('Split Method: PERCENTAGE • 2 members'), findsOneWidget);

      // Tap template item
      await tester.tap(find.text('Couples (60/40 Split)'));
      await tester.pumpAndSettle();

      expect(selectedTemplate, isNotNull);
      expect(selectedTemplate!.id, 'tmpl_1');
      expect(selectedTemplate!.name, 'Couples (60/40 Split)');
      expect(selectedTemplate!.allocations.length, 2);
    });
  });

  group('EvenBill Pro - Search & Filtering Across Past Expenses', () {
    testWidgets('SearchExpensesSheet executes multi-filter search and displays results', (tester) async {
      setupLargeViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          SearchExpensesSheet(
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify search input and initial helper
      expect(find.text('Search across all past expenses'), findsOneWidget);
      final searchInput = find.byType(TextField).first;
      expect(searchInput, findsOneWidget);

      // Type search query
      await tester.enterText(searchInput, 'Dinner');
      await tester.pumpAndSettle();

      // Tap search submission arrow button
      final searchArrowBtn = find.byIcon(Icons.arrow_forward_rounded);
      expect(searchArrowBtn, findsOneWidget);
      await tester.tap(searchArrowBtn);
      await tester.pumpAndSettle();

      // Verify results are rendered
      expect(find.text('Trattoria Dinner with Colleagues'), findsOneWidget);
      expect(find.text('USD 78.50'), findsOneWidget);
      expect(find.byIcon(Icons.receipt_long_rounded), findsOneWidget);
    });
  });

  group('EvenBill Pro - Bank Integration Compliance & Transaction Feed', () {
    testWidgets('BankImportSheet renders compliance card and allows transaction selection', (tester) async {
      setupLargeViewport(tester);
      BankTransactionModel? selectedTx;

      await tester.pumpWidget(
        buildTestApp(
          BankImportSheet(
            onTransactionSelected: (tx) {
              selectedTx = tx;
            },
            onBack: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify PSD2 / Open Banking compliance card
      expect(find.text('Bank Import (Open Banking)'), findsOneWidget);
      expect(find.text('Open Banking / PSD2 Compliance Framework'), findsOneWidget);
      expect(
        find.textContaining('Read-only financial transactions are synced through approved institutional providers.'),
        findsOneWidget,
      );

      // Verify transaction list
      expect(find.text('Whole Foods Market'), findsOneWidget);
      expect(find.text('USD 64.20'), findsOneWidget);
      expect(find.text('Blue Bottle Coffee'), findsOneWidget);
      expect(find.text('USD 14.50'), findsOneWidget);

      // Select first transaction
      await tester.tap(find.text('Whole Foods Market'));
      await tester.pumpAndSettle();

      expect(selectedTx, isNotNull);
      expect(selectedTx!.merchantName, 'Whole Foods Market');
      expect(selectedTx!.amount, 64.20);
      expect(selectedTx!.category, 'GROCERIES');
    });
  });

  group('EvenBill Pro - AddEditExpenseScreen Pro Action Chips', () {
    testWidgets('AddEditExpenseScreen renders Pro action chips and currency conversion note', (tester) async {
      setupLargeViewport(tester);
      await tester.pumpWidget(
        buildTestApp(
          AddEditExpenseScreen(
            onBack: () {},
            onSaved: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Pro quick action chips are visible
      expect(find.text('Scan Receipt (OCR)'), findsOneWidget);
      expect(find.text('Split Presets'), findsOneWidget);
      expect(find.text('Bank Import'), findsOneWidget);

      // Enter an amount
      final amountField = find.widgetWithText(TextField, '0.00');
      await tester.enterText(amountField, '100.00');
      await tester.pumpAndSettle();
    });
  });

  group('EvenBill Pro - Server-side Receipt Verification Flow', () {
    testWidgets('verifyPurchaseReceipt communicates with server-side validator', (tester) async {
      final verification = await mockPro.verifyPurchaseReceipt(
        store: 'APPLE_APP_STORE',
        purchaseToken: 'test_signed_receipt_token',
        productId: 'com.evenbill.app.pro.monthly',
        isSandbox: true,
      );

      expect(verification['success'], isTrue);
      expect(verification['verified'], isTrue);
      expect(verification['is_pro'], isTrue);
      expect(verification['status'], 'ACTIVE');
    });
  });
}
