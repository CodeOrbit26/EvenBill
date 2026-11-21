import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenbill/core/di/injection.dart';
import 'package:evenbill/core/widgets/buttons/primary_button.dart';
import 'package:evenbill/screens/auth/registration_screen.dart';
import 'package:evenbill/screens/groups/groups_list_screen.dart';
import 'package:evenbill/screens/groups/group_details_screen.dart';
import 'package:evenbill/screens/expenses/add_edit_expense_screen.dart';
import 'package:evenbill/screens/expenses/expense_details_screen.dart';
import 'package:evenbill/screens/settlements/record_settlement_screen.dart';
import 'package:evenbill/screens/activity/activity_screen.dart';
import 'package:evenbill/screens/overview/overview_screen.dart';
import 'package:evenbill/screens/shell/app_navigation_shell.dart';
import 'package:evenbill/screens/profile/profile_settings_screen.dart';
import 'mocks/mock_repositories.dart';

void main() {
  late MockAuthRepository mockAuth;
  late MockGroupRepository mockGroup;
  late MockExpenseRepository mockExpense;
  late MockSettlementRepository mockSettlement;
  late MockFriendRepository mockFriend;
  late MockActivityRepository mockActivity;
  late MockSubscriptionRepository mockSubscription;

  setUp(() {
    mockAuth = MockAuthRepository();
    mockGroup = MockGroupRepository();
    mockExpense = MockExpenseRepository();
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

  testWidgets('Journey 1: New user creates an account and completes onboarding', (tester) async {
    setMobileScreen(tester);
    bool registered = false;
    await tester.pumpWidget(MaterialApp(
      home: RegistrationScreen(
        onRegisterSuccess: () => registered = true,
        onNavigateToLogin: () {},
        onBack: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Create Your Account'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Alice Smith');
    await tester.enterText(fields.at(1), 'alice@example.com');
    await tester.enterText(fields.at(2), '+1 555 123 4567');
    await tester.enterText(fields.at(3), 'supersecret123');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(PrimaryButton, 'Create Account'));
    await tester.pumpAndSettle();

    expect(registered, isTrue);
    expect(mockAuth.authenticated, isTrue);
    expect(mockAuth.currentUser.fullName, 'Alice Smith');
  });

  testWidgets('Journey 2: User creates a group for a trip, home, couple, or other purpose', (tester) async {
    setMobileScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: GroupsListScreen(onGroupTap: (_) {}),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Active Groups (4)'), findsOneWidget);

    // Tap "+ Create Group"
    await tester.tap(find.byTooltip('Create Group'));
    await tester.pumpAndSettle();

    expect(find.text('Create New Group'), findsOneWidget);
    expect(find.text('Simplify Group Debts'), findsOneWidget);

    // Enter group name & select TRIP
    final modalField = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first;
    await tester.enterText(modalField, 'Kyoto Explorer 2026');
    await tester.tap(find.widgetWithText(ChoiceChip, 'TRIP'));
    await tester.pumpAndSettle();

    // Submit group creation
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Group'));
    await tester.pumpAndSettle();

    expect(mockGroup.groups.any((g) => g.name == 'Kyoto Explorer 2026'), isTrue);
  });

  testWidgets('Journey 3: User invites members and handles active, expired, and revoked invitations', (tester) async {
    setMobileScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: GroupDetailsScreen(
        group: mockGroup.groups.first,
        onAddExpense: () {},
        onExpenseTap: (_) {},
        onBack: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // Tap Invite Members icon
    await tester.tap(find.byTooltip('Invite Members'));
    await tester.pumpAndSettle();

    // Verify friendly shareable URL without passwords or tokens
    expect(find.textContaining('https://evenbill.app/join/APT404EB'), findsOneWidget);
    expect(find.text('Copy Link'), findsOneWidget);

    // Enter email and send direct invite
    final emailField = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    ).first;
    await tester.enterText(emailField, 'clara@roommate.org');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pumpAndSettle();

    expect(mockGroup.invitations.any((i) => i.email == 'clara@roommate.org'), isTrue);

    // Revoke pending invite
    expect(find.text('alex@example.com'), findsWidgets);
    await tester.tap(find.widgetWithText(TextButton, 'Revoke').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Revoke Invitation?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Revoke'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final claraInv = mockGroup.invitations.firstWhere((i) => i.email == 'clara@roommate.org');
    expect(claraInv.status, 'REVOKED');
  });

  testWidgets('Journey 4: Members add and edit expenses with participants and split methods', (tester) async {
    setMobileScreen(tester);
    bool saved = false;
    await tester.pumpWidget(MaterialApp(
      home: AddEditExpenseScreen(
        onSaved: () => saved = true,
        onBack: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // Fill in amount & description
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '120.00');
    await tester.enterText(fields.at(1), 'Ski Equipment Rental');

    // Select EQUAL split method
    await tester.tap(find.text('Equally (=)'));
    await tester.pumpAndSettle();

    // Save expense using AppBar Save button
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(saved, isTrue);
    expect(mockExpense.expenses.any((e) => e.description == 'Ski Equipment Rental'), isTrue);
  });

  testWidgets('Journey 5: Users can view expense details, item allocations, and history', (tester) async {
    setMobileScreen(tester);
    bool deleted = false;
    final exp = mockExpense.expenses.first;

    await tester.pumpWidget(MaterialApp(
      home: ExpenseDetailsScreen(
        expense: exp,
        onEdit: () {},
        onDelete: () => deleted = true,
        onBack: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text(exp.description), findsOneWidget);
    expect(find.text('Expense Details'), findsOneWidget);
    expect(find.textContaining('Recorded in immutable financial ledger'), findsOneWidget);

    // Delete with confirmation dialog
    await tester.tap(find.byTooltip('Delete Expense'));
    await tester.pumpAndSettle();

    expect(find.text('Delete Expense?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(mockExpense.expenses.any((e) => e.id == exp.id), isFalse);
  });

  testWidgets('Journey 6 & 7: Users simplify debts and record a settlement', (tester) async {
    setMobileScreen(tester);
    bool settled = false;
    await tester.pumpWidget(MaterialApp(
      home: GroupDetailsScreen(
        group: mockGroup.groups.first,
        onAddExpense: () {},
        onExpenseTap: (_) {},
        onBack: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // Balances tab
    await tester.tap(find.text('Balances'));
    await tester.pumpAndSettle();

    expect(find.text('Debt Simplification Active'), findsOneWidget);
    expect(find.text('Marco Rossi pays Abhay Gupta'), findsOneWidget);

    // Record Settlement screen
    await tester.pumpWidget(MaterialApp(
      home: RecordSettlementScreen(
        preselectedRecipientId: 'user_1',
        preselectedRecipientName: 'Abhay Gupta',
        preselectedAmount: 40.00,
        onSettled: () => settled = true,
        onBack: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.descendant(of: find.byType(AppBar), matching: find.text('Record Settlement')), findsOneWidget);

    // Choose CASH
    await tester.tap(find.text('CASH'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(PrimaryButton, 'Record Settlement'));
    await tester.pumpAndSettle();

    expect(settled, isTrue);
    expect(mockSettlement.settlements.isNotEmpty, isTrue);
    expect(mockSettlement.settlements.first.paymentMethod, 'CASH');
  });

  testWidgets('Journey 8: Users create individual expenses without creating a group', (tester) async {
    setMobileScreen(tester);
    bool saved = false;
    await tester.pumpWidget(MaterialApp(
      home: AddEditExpenseScreen(
        initialExpense: null,
        preselectedGroupId: null,
        onSaved: () => saved = true,
        onBack: () {},
      ),
    ));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '18.50');
    await tester.enterText(fields.at(1), 'Coffee & Pastry');

    // Save via AppBar Save button
    await tester.tap(find.widgetWithText(TextButton, 'Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(saved, isTrue);
    final created = mockExpense.expenses.firstWhere((e) => e.description == 'Coffee & Pastry');
    expect(created.groupId, isNull);
  });

  testWidgets('Journey 9: Users filter activity and see meaningful spending totals', (tester) async {
    setMobileScreen(tester);
    await tester.pumpWidget(const MaterialApp(
      home: ActivityScreen(),
    ));
    await tester.pumpAndSettle();

    // Spending summary
    expect(find.text('Monthly Spending'), findsOneWidget);
    expect(find.text('Total: USD 420.50'), findsOneWidget);
    expect(find.text('You Are Owed'), findsOneWidget);
    expect(find.text('You Owe'), findsOneWidget);

    // Filter pills
    expect(find.text('All Activity'), findsOneWidget);
    expect(find.text('Expenses Only'), findsOneWidget);
    expect(find.text('Settlements Only'), findsOneWidget);

    await tester.tap(find.text('Settlements Only'));
    await tester.pumpAndSettle();

    expect(find.text('Marco paid You'), findsOneWidget);
  });

  testWidgets('Journey 10: Users manage profiles, preferences, and notifications', (tester) async {
    setMobileScreen(tester);
    bool signedOut = false;
    await tester.pumpWidget(MaterialApp(
      home: ProfileSettingsScreen(
        currentThemeMode: ThemeMode.light,
        onThemeChanged: (_) {},
        onOpenPaywall: () {},
        onSignOut: () => signedOut = true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Account & Settings'), findsOneWidget);
    expect(find.text('Abhay Gupta'), findsOneWidget);

    // Edit profile dialog
    await tester.tap(find.byTooltip('Edit Profile'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Profile'), findsOneWidget);
    final editName = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)).first;
    await tester.enterText(editName, 'Abhay S.');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
    await tester.pumpAndSettle();

    expect(mockAuth.currentUser.fullName, 'Abhay S.');

    // Notifications toggle
    expect(find.text('Push Notifications'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Push Notifications'));
    await tester.pumpAndSettle();

    // Sign out dialog
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign Out'));
    await tester.pumpAndSettle();

    expect(find.text('Sign Out?'), findsOneWidget);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign Out'));
    await tester.pumpAndSettle();

    expect(signedOut, isTrue);
  });

  testWidgets('Journey 11: Empty partners shows clear guidance and direction toggle reverses payer', (tester) async {
    setMobileScreen(tester);
    mockFriend.friends.clear();
    mockGroup.groups.clear();

    await tester.pumpWidget(MaterialApp(
      home: RecordSettlementScreen(
        onSettled: () {},
        onBack: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No members available yet'), findsOneWidget);
    expect(find.textContaining('Open a group and tap "+ Add Member"'), findsOneWidget);

    await tester.tap(find.widgetWithText(PrimaryButton, 'Record Settlement'));
    await tester.pumpAndSettle();

    expect(mockSettlement.settlements, isEmpty);
    expect(find.textContaining('No settlement partner found'), findsOneWidget);
  });

  testWidgets('Journey 12: Record settlement with Member paid You sets payerId to selected partner', (tester) async {
    setMobileScreen(tester);
    final tokens = mockAuth.tokenStorage;
    await tokens.saveUser(mockAuth.currentUser);
    Injection.setMockRepositories(
      auth: mockAuth,
      group: mockGroup,
      expense: mockExpense,
      settlement: mockSettlement,
      friend: mockFriend,
      activity: mockActivity,
      subscription: mockSubscription,
      tokens: tokens,
    );

    bool settled = false;
    await tester.pumpWidget(MaterialApp(
      home: RecordSettlementScreen(
        onSettled: () => settled = true,
        onBack: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // First partner Elena Rostova (fr_1) should be auto-selected; flip direction to Member paid You
    await tester.tap(find.text('Elena Rostova paid You'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(PrimaryButton, 'Record Settlement'));
    await tester.pumpAndSettle();

    expect(settled, isTrue);
    expect(mockSettlement.settlements.length, 1);
    expect(mockSettlement.settlements.first.payerId, 'fr_1');
    expect(mockSettlement.settlements.first.recipientId, mockAuth.currentUser.id);
  });

  testWidgets('Journey 13: Add member directly inside GroupDetailsScreen', (tester) async {
    setMobileScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: GroupDetailsScreen(
        group: mockGroup.groups.first,
        onAddExpense: () {},
        onExpenseTap: (_) {},
        onBack: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // Tap the Add Member button on the Expenses summary card
    await tester.tap(find.textContaining('+ Add'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Add Member to '), findsOneWidget);
    final nameField = find.byType(TextField).first;
    await tester.enterText(nameField, 'Rahul Sharma');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Add to Group'));
    await tester.pumpAndSettle();

    expect(mockGroup.extraMembers.length, 1);
    expect(mockGroup.extraMembers.first.fullName, 'Rahul Sharma');
    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();
    expect(find.text('Rahul Sharma'), findsOneWidget);
    expect(find.text('MEMBER • Added directly'), findsOneWidget);
  });

  testWidgets('Journey 14: Start a new group directly from OverviewScreen', (tester) async {
    setMobileScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: OverviewScreen(
        onExpenseTap: (_) {},
        onSettleUpTap: () {},
        onScanReceiptTap: () {},
        onAddExpenseTap: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // Verify Overview screen has Your Groups
    expect(find.textContaining('Your Groups'), findsOneWidget);

    // Verify Start a new group button is visible and tap it
    expect(find.text('Start a new group'), findsOneWidget);
    await tester.tap(find.text('Start a new group'));
    await tester.pumpAndSettle();

    // Verify bottom sheet modal opened
    expect(find.text('Create New Group'), findsOneWidget);
    final modalField = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first;
    await tester.enterText(modalField, 'Weekend Getaway');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Group'));
    await tester.pumpAndSettle();

    expect(mockGroup.groups.any((g) => g.name == 'Weekend Getaway'), isTrue);
  });

  testWidgets('Journey 15: Tap Activity button on top-right AppBar opens Activity feed', (tester) async {
    setMobileScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: AppNavigationShell(
        currentThemeMode: ThemeMode.light,
        onThemeChanged: (_) {},
        onSignOut: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // Verify Activity button is on the top right
    expect(find.byTooltip('Activity'), findsOneWidget);
    await tester.tap(find.byTooltip('Activity'));
    await tester.pumpAndSettle();

    expect(find.text('Activity & Audit Feed'), findsOneWidget);

    // Verify back navigation works
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Recent Expenses'), findsOneWidget);
  });

  testWidgets('Journey 16: Scan & Pay via UPI QR opens scanner, sets amount/payee, and records bank payment expense', (tester) async {
    setMobileScreen(tester);
    await tester.pumpWidget(MaterialApp(
      home: AppNavigationShell(
        currentThemeMode: ThemeMode.light,
        onThemeChanged: (_) {},
        onSignOut: () {},
      ),
    ));
    await tester.pumpAndSettle();

    // Tap Scan & Pay button on dashboard
    final scanBtn = find.text('Scan & Pay');
    expect(scanBtn, findsOneWidget);
    await tester.tap(scanBtn);
    await tester.pumpAndSettle();

    // Verify Scan & Pay Screen opened
    expect(find.text('Scan & Pay (UPI)'), findsOneWidget);
    expect(find.text('UPI QR & Bank Pay'), findsOneWidget);
    expect(find.text('Paper Bill OCR'), findsOneWidget);

    // Tap a preset QR: Sharma Tea (₹180)
    final preset = find.text('☕ Sharma Tea (₹180)');
    expect(preset, findsOneWidget);
    await tester.tap(preset);
    await tester.pumpAndSettle();

    expect(find.text('sharma.tea@paytm'), findsOneWidget);
    expect(find.text('Sharma Tea Stall'), findsOneWidget);
    expect(find.text('180.00'), findsOneWidget);

    // Quick add ₹100
    await tester.tap(find.text('+₹100'));
    await tester.pumpAndSettle();
    expect(find.text('280.00'), findsOneWidget);

    // Scroll down to the Pay button
    await tester.scrollUntilVisible(
      find.text('Pay via UPI & Split'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pay via UPI & Split'), warnIfMissed: false);
    await tester.pumpAndSettle();

    // Confirm Bank Payment in sheet
    expect(find.text('Bank UPI Payment'), findsOneWidget);
    expect(find.text('₹280.00'), findsWidgets);
    expect(find.text('Confirm Bank Payment & Record'), findsOneWidget);

    await tester.tap(find.text('Confirm Bank Payment & Record'));
    await tester.pumpAndSettle();

    // Verify Payment Success Dialog
    expect(find.text('Payment Successful!'), findsOneWidget);
    expect(find.text('Done & Return to Overview'), findsOneWidget);

    await tester.tap(find.text('Done & Return to Overview'));
    await tester.pumpAndSettle();

    // Returns to Overview
    expect(find.text('Scan & Pay'), findsOneWidget);
  });
}
