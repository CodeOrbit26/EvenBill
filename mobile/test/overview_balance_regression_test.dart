import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:evenbill/core/di/injection.dart';
import 'package:evenbill/core/models/activity_model.dart';
import 'package:evenbill/core/models/expense_model.dart';
import 'package:evenbill/core/models/friend_model.dart';
import 'package:evenbill/core/models/group_model.dart';
import 'package:evenbill/core/models/user_model.dart';
import 'package:evenbill/core/network/token_storage.dart';
import 'package:evenbill/screens/expenses/add_edit_expense_screen.dart';
import 'package:evenbill/screens/groups/group_details_screen.dart';
import 'package:evenbill/screens/shell/app_navigation_shell.dart';
import 'mocks/mock_repositories.dart';

class _StatefulLedgerBackend {
  final String user1Id = '11111111-1111-4111-8111-111111111111';
  final String user2Id = '22222222-2222-4222-8222-222222222222';
  final String groupId = 'gggggggg-gggg-4ggg-8ggg-gggggggggggg';
  final List<ExpenseModel> expenses = <ExpenseModel>[];

  double netBalanceFor(String userId) {
    double paid = 0.0;
    double owed = 0.0;
    for (final exp in expenses) {
      for (final p in exp.payers) {
        if (p.userId == userId) paid += p.amountPaid;
      }
      for (final s in exp.splits) {
        if (s.userId == userId) owed += s.owedAmount;
      }
    }
    return paid - owed;
  }

  ActivitySummaryModel summaryFor(String userId) {
    final net = netBalanceFor(userId);
    return ActivitySummaryModel(
      totalNetBalance: net,
      youAreOwedTotal: net > 0 ? net : 0.0,
      youOweTotal: net < 0 ? net.abs() : 0.0,
      monthlySpending: expenses.fold(0.0, (sum, e) {
        final s = e.splits.where((x) => x.userId == userId).fold(0.0, (a, x) => a + x.owedAmount);
        return sum + s;
      }),
      currency: 'INR',
      activeGroupsCount: 1,
      activeFriendsCount: 1,
    );
  }
}

class _LiveGroupRepo extends MockGroupRepository {
  final _StatefulLedgerBackend backend;
  final String activeUserId;

  _LiveGroupRepo(this.backend, this.activeUserId);

  GroupModel _groupModel() => GroupModel(
        id: backend.groupId,
        name: 'Goa Crew',
        groupType: 'TRIP',
        baseCurrency: 'INR',
        inviteCode: 'GOA12345',
        createdBy: backend.user1Id,
        memberCount: 2,
        netBalance: backend.netBalanceFor(activeUserId),
      );

  @override
  Future<List<GroupModel>> listGroups() async => [_groupModel()];

  @override
  Future<GroupDetailModel> getGroupDetails(String groupId) async {
    final g = _groupModel();
    final u1Net = backend.netBalanceFor(backend.user1Id);
    final u2Net = backend.netBalanceFor(backend.user2Id);
    return GroupDetailModel(
      group: g,
      members: [
        GroupMemberModel(id: 'm1', userId: backend.user1Id, fullName: 'Alice', email: 'alice@test.com', role: 'OWNER'),
        GroupMemberModel(id: 'm2', userId: backend.user2Id, fullName: 'Bob', email: 'bob@test.com', role: 'MEMBER'),
      ],
      netBalances: [
        NetBalanceModel(userId: backend.user1Id, fullName: 'Alice', netBalance: u1Net, currency: 'INR'),
        NetBalanceModel(userId: backend.user2Id, fullName: 'Bob', netBalance: u2Net, currency: 'INR'),
      ],
      simplifiedDebts: const [],
      bilateralDebts: const [],
    );
  }
}

class _LiveActivityRepo extends MockActivityRepository {
  final _StatefulLedgerBackend backend;
  final String activeUserId;

  _LiveActivityRepo(this.backend, this.activeUserId);

  @override
  Future<ActivitySummaryModel> getActivitySummary({String? currency}) async =>
      backend.summaryFor(activeUserId);

  @override
  Future<List<ActivityItemModel>> listActivity({
    String? groupId,
    String? category,
    String? search,
    int limit = 50,
  }) async {
    return backend.expenses.reversed.map((exp) {
      return ActivityItemModel(
        id: exp.id,
        itemType: 'EXPENSE',
        title: exp.description,
        description: exp.paidBy,
        category: exp.category,
        totalAmount: exp.totalAmount,
        currency: exp.currency,
        userNetShare: exp.getUserNetShare(activeUserId),
        userPaidAmount: exp.getUserPaidAmount(activeUserId),
        userOwedAmount: exp.getUserOwedAmount(activeUserId),
        isUserInvolved: exp.isUserInvolved(activeUserId),
        groupId: exp.groupId,
        groupName: exp.groupId != null ? 'Goa Crew' : null,
        createdByName: exp.creatorName,
        timestamp: exp.createdAt,
      );
    }).toList();
  }
}

class _LiveExpenseRepo extends MockExpenseRepository {
  final _StatefulLedgerBackend backend;
  final String activeUserId;

  _LiveExpenseRepo(this.backend, this.activeUserId);

  @override
  Future<List<ExpenseModel>> listGroupExpenses(String groupId) async =>
      backend.expenses.where((e) => e.groupId == groupId).toList();

  @override
  Future<ExpenseModel> getExpense(String expenseId) async =>
      backend.expenses.firstWhere((e) => e.id == expenseId);

  @override
  Future<bool> deleteExpense(String expenseId) async {
    backend.expenses.removeWhere((e) => e.id == expenseId);
    return true;
  }

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
    final ids = (participantIds != null && participantIds.isNotEmpty)
        ? participantIds
        : [backend.user1Id, backend.user2Id];
    final perPerson = totalAmount / ids.length;
    final exp = ExpenseModel(
      id: 'exp_${backend.expenses.length + 1}',
      groupId: groupId,
      createdBy: activeUserId,
      creatorName: activeUserId == backend.user1Id ? 'Alice' : 'Bob',
      description: description,
      totalAmount: totalAmount,
      currency: currency,
      baseCurrencyAmount: totalAmount,
      splitType: splitType,
      category: category,
      expenseDate: DateTime.now(),
      createdAt: DateTime.now(),
      payers: payers ?? [PayerModel(userId: activeUserId, fullName: 'Alice', amountPaid: totalAmount)],
      splits: ids
          .map((uid) => SplitModel(
                userId: uid,
                fullName: uid == backend.user1Id ? 'Alice' : 'Bob',
                owedAmount: perPerson,
              ))
          .toList(),
    );
    backend.expenses.add(exp);
    return exp;
  }
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
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

  Future<void> configureMocksForUser(
    _StatefulLedgerBackend backend,
    String userId,
    String name,
    String email,
  ) async {
    final tokens = InMemoryTokenStorage();
    final user = UserModel(
      id: userId,
      email: email,
      fullName: name,
      defaultCurrency: 'INR',
      isActive: true,
      isVerified: true,
    );
    await tokens.saveUser(user);
    await tokens.saveTokens(accessToken: 'jwt_$userId', refreshToken: 'ref_$userId');
    final mockAuth = MockAuthRepository(tokenStorage: tokens)
      ..currentUser = user
      ..authenticated = true;
    final otherId = userId == backend.user1Id ? backend.user2Id : backend.user1Id;
    final otherName = userId == backend.user1Id ? 'Bob' : 'Alice';

    Injection.setMockRepositories(
      tokens: tokens,
      auth: mockAuth,
      group: _LiveGroupRepo(backend, userId),
      expense: _LiveExpenseRepo(backend, userId),
      settlement: MockSettlementRepository(),
      friend: MockFriendRepository()
        ..friends.clear()
        ..friends.add(FriendModel(
          id: otherId,
          name: otherName,
          email: '$otherName@test.com',
          netBalance: backend.netBalanceFor(userId),
          currency: 'INR',
        )),
      activity: _LiveActivityRepo(backend, userId),
      subscription: MockSubscriptionRepository(),
      pro: MockProRepository(),
    );
  }

  testWidgets(
    'Overview updates immediately after expense creation, across multiple expenses, after restart, and across devices',
    (tester) async {
      setMobileScreen(tester);
      final backend = _StatefulLedgerBackend();

      // 1. User 1 opens app on Device 1 -> initially 0.00
      await configureMocksForUser(backend, backend.user1Id, 'Alice', 'alice@test.com');
      await tester.pumpWidget(MaterialApp(
        key: const ValueKey('device_1_boot_1'),
        home: AppNavigationShell(
          currentThemeMode: ThemeMode.light,
          onThemeChanged: (_) {},
          onSignOut: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('You are all settled up'), findsOneWidget);

      // 2. Create first expense (₹1000.00 split equally between Alice & Bob -> +₹500.00)
      await tester.tap(find.text('Add Expense'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '1000.00');
      await tester.enterText(find.byType(TextField).at(1), 'Goa Dinner');
      await tester.pump();
      await tester.ensureVisible(find.text('Save Expense'));
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();

      // Immediately refreshed Overview reflects +₹500.00 owed to Alice
      expect(find.text('Overall, you are owed'), findsOneWidget);
      expect(find.textContaining('500.00'), findsWidgets);

      // 3. Create second expense in the same group (₹600.00 split equally -> cumulative +₹800.00)
      await tester.tap(find.text('Add Expense'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), '600.00');
      await tester.enterText(find.byType(TextField).at(1), 'Beach Cab');
      await tester.pump();
      await tester.ensureVisible(find.text('Save Expense'));
      await tester.tap(find.text('Save Expense'));
      await tester.pumpAndSettle();

      expect(find.text('Overall, you are owed'), findsOneWidget);
      expect(find.textContaining('800.00'), findsWidgets);

      // Verify Recent Expenses tab shows both expenses
      await tester.tap(find.text('Recent Expenses'));
      await tester.pumpAndSettle();
      expect(find.text('Goa Dinner'), findsOneWidget);
      expect(find.text('Beach Cab'), findsOneWidget);

      // 4. App restart simulation (brand-new widget tree + fresh in-memory cache reading backend)
      await configureMocksForUser(backend, backend.user1Id, 'Alice', 'alice@test.com');
      await tester.pumpWidget(MaterialApp(
        key: const ValueKey('device_1_restart'),
        home: AppNavigationShell(
          currentThemeMode: ThemeMode.light,
          onThemeChanged: (_) {},
          onSignOut: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Overall, you are owed'), findsOneWidget);
      expect(find.textContaining('800.00'), findsWidgets);

      // 5. Cross-device participant check: Bob opens his device and sees "Overall, you owe" ₹800.00
      await configureMocksForUser(backend, backend.user2Id, 'Bob', 'bob@test.com');
      await tester.pumpWidget(MaterialApp(
        key: const ValueKey('device_2_participant'),
        home: AppNavigationShell(
          currentThemeMode: ThemeMode.light,
          onThemeChanged: (_) {},
          onSignOut: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Overall, you owe'), findsOneWidget);
      expect(find.textContaining('800.00'), findsWidgets);
    },
  );

  testWidgets(
    'GroupDetailsScreen calculates current user net share accurately when viewing an expense paid by another member',
    (tester) async {
      setMobileScreen(tester);
      final backend = _StatefulLedgerBackend();
      backend.expenses.add(ExpenseModel(
        id: 'exp_other_paid',
        groupId: backend.groupId,
        createdBy: backend.user1Id,
        creatorName: 'Alice',
        description: 'Boat Charter',
        totalAmount: 1000.0,
        currency: 'INR',
        baseCurrencyAmount: 1000.0,
        expenseDate: DateTime.now(),
        createdAt: DateTime.now(),
        payers: [PayerModel(userId: backend.user1Id, fullName: 'Alice', amountPaid: 1000.0)],
        splits: [
          SplitModel(userId: backend.user1Id, fullName: 'Alice', owedAmount: 500.0),
          SplitModel(userId: backend.user2Id, fullName: 'Bob', owedAmount: 500.0),
        ],
      ));

      // Bob views the group -> header and expense row must show Bob's negative share (-₹500.00), not Alice's +₹500.00
      await configureMocksForUser(backend, backend.user2Id, 'Bob', 'bob@test.com');
      final group = (await Injection.groupRepository.listGroups()).first;

      await tester.pumpWidget(MaterialApp(
        home: GroupDetailsScreen(
          group: group,
          onAddExpense: () {},
          onExpenseTap: (_) {},
          onBack: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Boat Charter'), findsOneWidget);
      expect(find.textContaining('you owe'), findsWidgets);
      expect(find.textContaining('you lent'), findsNothing);
    },
  );

  testWidgets(
    'AddEditExpenseScreen displays solo-split guidance when only the current user is eligible',
    (tester) async {
      setMobileScreen(tester);
      final backend = _StatefulLedgerBackend();
      await configureMocksForUser(backend, backend.user1Id, 'Alice', 'alice@test.com');
      final emptyGroupRepo = MockGroupRepository()..groups.clear();
      final emptyFriendRepo = MockFriendRepository()..friends.clear();
      Injection.setMockRepositories(
        group: emptyGroupRepo,
        friend: emptyFriendRepo,
      );

      await tester.pumpWidget(MaterialApp(
        home: AddEditExpenseScreen(
          preselectedCurrency: 'INR',
          onSaved: () {},
          onBack: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Solo expense: only you are included, so balances with others stay at 0 until another member is added.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Solo expense shows expense amount and personal badge instead of not involved, while uninvolved viewer still sees not involved',
    (tester) async {
      setMobileScreen(tester);
      final backend = _StatefulLedgerBackend();

      // Solo expenses mirror production ww ($2000 USD) and dd (₹5000 INR)
      backend.expenses.addAll([
        ExpenseModel(
          id: 'exp_solo_ww',
          groupId: backend.groupId,
          createdBy: backend.user1Id,
          creatorName: 'Advanced Ai',
          description: 'ww',
          totalAmount: 2000.0,
          currency: 'USD',
          baseCurrencyAmount: 2000.0,
          expenseDate: DateTime.now(),
          createdAt: DateTime.now(),
          payers: [
            PayerModel(userId: backend.user1Id, fullName: 'Advanced Ai', amountPaid: 2000.0),
          ],
          splits: [
            SplitModel(userId: backend.user1Id, fullName: 'Advanced Ai', owedAmount: 2000.0),
          ],
        ),
        ExpenseModel(
          id: 'exp_solo_dd',
          groupId: backend.groupId,
          createdBy: backend.user1Id,
          creatorName: 'Advanced Ai',
          description: 'dd',
          totalAmount: 5000.0,
          currency: 'INR',
          baseCurrencyAmount: 5000.0,
          expenseDate: DateTime.now(),
          createdAt: DateTime.now(),
          payers: [
            PayerModel(userId: backend.user1Id, fullName: 'Advanced Ai', amountPaid: 5000.0),
          ],
          splits: [
            SplitModel(userId: backend.user1Id, fullName: 'Advanced Ai', owedAmount: 5000.0),
          ],
        ),
      ]);

      await configureMocksForUser(backend, backend.user1Id, 'Advanced Ai', 'adv@test.com');
      await tester.pumpWidget(MaterialApp(
        key: const ValueKey('solo_overview_device'),
        home: AppNavigationShell(
          currentThemeMode: ThemeMode.light,
          onThemeChanged: (_) {},
          onSignOut: () {},
        ),
      ));
      await tester.pumpAndSettle();

      // Switch Overview segment to Recent Expenses
      await tester.tap(find.text('Recent Expenses'));
      await tester.pumpAndSettle();

      expect(find.text('ww'), findsOneWidget);
      expect(find.text('dd'), findsOneWidget);
      expect(find.text('Paid by Advanced Ai'), findsNWidgets(2));
      expect(find.text('personal'), findsNWidgets(2));
      expect(find.textContaining('2,000.00'), findsWidgets);
      expect(find.textContaining('5,000.00'), findsWidgets);
      expect(find.text('not involved'), findsNothing);
      expect(find.text('no balance'), findsNothing);

      // When Bob views those same expenses he neither paid nor participated in,
      // "not involved" MUST still render accurately.
      await configureMocksForUser(backend, backend.user2Id, 'Bob', 'bob@test.com');
      await tester.pumpWidget(MaterialApp(
        key: const ValueKey('uninvolved_viewer_device'),
        home: AppNavigationShell(
          currentThemeMode: ThemeMode.light,
          onThemeChanged: (_) {},
          onSignOut: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Recent Expenses'));
      await tester.pumpAndSettle();

      expect(find.text('not involved'), findsNWidgets(2));
      expect(find.text('no balance'), findsNWidgets(2));
      expect(find.textContaining('Total '), findsNWidgets(2));
    },
  );

  testWidgets(
    'Overview & GroupDetails handle payer-only-for-other, unequal multi-participant splits, co-pay even shares, restart and cross-device sync',
    (tester) async {
      setMobileScreen(tester);
      final backend = _StatefulLedgerBackend();
      const user3Id = 'user_charlie';

      // 1. Alice pays ₹1,000 for Bob only (Alice owes ₹0 -> you lent ₹1,000.00)
      backend.expenses.add(ExpenseModel(
        id: 'exp_payer_for_bob',
        groupId: backend.groupId,
        createdBy: backend.user1Id,
        creatorName: 'Alice',
        description: 'Flight for Bob',
        totalAmount: 1000.0,
        currency: 'INR',
        baseCurrencyAmount: 1000.0,
        expenseDate: DateTime.now(),
        createdAt: DateTime.now().subtract(const Duration(minutes: 3)),
        payers: [PayerModel(userId: backend.user1Id, fullName: 'Alice', amountPaid: 1000.0)],
        splits: [SplitModel(userId: backend.user2Id, fullName: 'Bob', owedAmount: 1000.0)],
      ));

      // 2. Bob pays ₹900 split unequally across Alice (₹200), Bob (₹300), Charlie (₹400)
      //    Created by Alice so payerText must display Paid by Bob (not Paid by Alice).
      backend.expenses.add(ExpenseModel(
        id: 'exp_multi_unequal',
        groupId: backend.groupId,
        createdBy: backend.user1Id,
        creatorName: 'Alice',
        description: 'Group Brunch',
        totalAmount: 900.0,
        currency: 'INR',
        baseCurrencyAmount: 900.0,
        expenseDate: DateTime.now(),
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        payers: [PayerModel(userId: backend.user2Id, fullName: 'Bob', amountPaid: 900.0)],
        splits: [
          SplitModel(userId: backend.user1Id, fullName: 'Alice', owedAmount: 200.0),
          SplitModel(userId: backend.user2Id, fullName: 'Bob', owedAmount: 300.0),
          SplitModel(userId: user3Id, fullName: 'Charlie', owedAmount: 400.0),
        ],
      ));

      // 3. Co-pay where Alice pays ₹400 and owes ₹400 (net ₹0, but involved -> even share ₹400.00)
      backend.expenses.add(ExpenseModel(
        id: 'exp_copay_even',
        groupId: backend.groupId,
        createdBy: backend.user1Id,
        creatorName: 'Alice',
        description: 'Ferry Tickets',
        totalAmount: 800.0,
        currency: 'INR',
        baseCurrencyAmount: 800.0,
        expenseDate: DateTime.now(),
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
        payers: [
          PayerModel(userId: backend.user1Id, fullName: 'Alice', amountPaid: 400.0),
          PayerModel(userId: backend.user2Id, fullName: 'Bob', amountPaid: 400.0),
        ],
        splits: [
          SplitModel(userId: backend.user1Id, fullName: 'Alice', owedAmount: 400.0),
          SplitModel(userId: backend.user2Id, fullName: 'Bob', owedAmount: 400.0),
        ],
      ));

      // Alice net = +1000 - 200 + 0 = +800.00
      await configureMocksForUser(backend, backend.user1Id, 'Alice', 'alice@test.com');
      await tester.pumpWidget(MaterialApp(
        key: const ValueKey('alice_multi_device_1'),
        home: AppNavigationShell(
          currentThemeMode: ThemeMode.light,
          onThemeChanged: (_) {},
          onSignOut: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Overall, you are owed'), findsOneWidget);
      expect(find.textContaining('800.00'), findsWidgets);

      await tester.tap(find.text('Recent Expenses'));
      await tester.pumpAndSettle();

      expect(find.text('Flight for Bob'), findsOneWidget);
      expect(find.text('Group Brunch'), findsOneWidget);
      expect(find.text('Ferry Tickets'), findsOneWidget);
      expect(find.text('Paid by Bob'), findsOneWidget);
      expect(find.text('you lent'), findsOneWidget);
      expect(find.text('you borrowed'), findsOneWidget);
      expect(find.text('even share'), findsOneWidget);
      expect(find.text('not involved'), findsNothing);

      // Simulate restart + second device for Alice -> Overview totals persist accurately
      await configureMocksForUser(backend, backend.user1Id, 'Alice', 'alice@test.com');
      await tester.pumpWidget(MaterialApp(
        key: const ValueKey('alice_multi_device_2'),
        home: AppNavigationShell(
          currentThemeMode: ThemeMode.light,
          onThemeChanged: (_) {},
          onSignOut: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Overall, you are owed'), findsOneWidget);
      expect(find.textContaining('800.00'), findsWidgets);

      // Charlie logs in on his device (user3Id): owes ₹400 on Group Brunch, not involved in Ferry & Flight
      await configureMocksForUser(backend, user3Id, 'Charlie', 'charlie@test.com');
      await tester.pumpWidget(MaterialApp(
        key: const ValueKey('charlie_device'),
        home: AppNavigationShell(
          currentThemeMode: ThemeMode.light,
          onThemeChanged: (_) {},
          onSignOut: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Overall, you owe'), findsOneWidget);
      expect(find.textContaining('400.00'), findsWidgets);

      await tester.tap(find.text('Recent Expenses'));
      await tester.pumpAndSettle();
      expect(find.text('you borrowed'), findsOneWidget);
      expect(find.text('not involved'), findsNWidgets(2));
    },
  );

  test('ActivityItemModel parses backend involvement fields and keeps legacy fallback', () {
    final parsed = ActivityItemModel.fromJson({
      'id': 'act_1',
      'item_type': 'EXPENSE',
      'title': 'dd',
      'description': 'Paid by Advanced Ai',
      'category': 'GENERAL',
      'total_amount': '5000.00',
      'currency': 'INR',
      'user_net_share': '0.00',
      'user_paid_amount': '5000.00',
      'user_owed_amount': '5000.00',
      'is_user_involved': true,
      'created_by_name': 'Advanced Ai',
      'timestamp': '2026-11-26T10:00:00Z',
    });
    expect(parsed.userPaidAmount, 5000.0);
    expect(parsed.userOwedAmount, 5000.0);
    expect(parsed.isUserInvolved, isTrue);
    expect(parsed.resolvedIsUserInvolved(), isTrue);

    final explicitlyUninvolved = ActivityItemModel.fromJson({
      'id': 'act_2',
      'item_type': 'EXPENSE',
      'title': 'Team Lunch',
      'description': 'Paid by Bob',
      'category': 'FOOD',
      'total_amount': '500.00',
      'currency': 'INR',
      'user_net_share': '0.00',
      'user_paid_amount': '0.00',
      'user_owed_amount': '0.00',
      'is_user_involved': false,
      'created_by_name': 'Bob',
      'timestamp': '2026-11-26T10:00:00Z',
    });
    expect(explicitlyUninvolved.isUserInvolved, isFalse);
    expect(explicitlyUninvolved.resolvedIsUserInvolved(currentUserName: 'Bob'), isFalse);
  });
}
