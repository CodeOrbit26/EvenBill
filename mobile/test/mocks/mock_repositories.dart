import 'package:evenbill/core/models/user_model.dart';
import 'package:evenbill/core/models/group_model.dart';
import 'package:evenbill/core/models/group_invitation_model.dart';
import 'package:evenbill/core/models/expense_model.dart';
import 'package:evenbill/core/models/settlement_model.dart';
import 'package:evenbill/core/models/friend_model.dart';
import 'package:evenbill/core/models/activity_model.dart';
import 'package:evenbill/core/models/entitlement_model.dart';
import 'package:evenbill/core/network/api_client.dart';
import 'package:evenbill/core/network/token_storage.dart';
import 'package:evenbill/core/repositories/auth_repository.dart';
import 'package:evenbill/core/repositories/group_repository.dart';
import 'package:evenbill/core/repositories/expense_repository.dart';
import 'package:evenbill/core/repositories/settlement_repository.dart';
import 'package:evenbill/core/repositories/friend_repository.dart';
import 'package:evenbill/core/repositories/activity_repository.dart';
import 'package:evenbill/core/repositories/subscription_repository.dart';

import 'package:evenbill/core/repositories/pro_repository.dart';
import 'package:evenbill/core/models/receipt_model.dart';
import 'package:evenbill/core/models/split_template_model.dart';
import 'package:evenbill/core/models/spending_insights_model.dart';
import 'package:evenbill/core/models/fx_model.dart';
import 'package:evenbill/core/models/bank_model.dart';

class MockAuthRepository extends AuthRepository {
  UserModel currentUser = const UserModel(
    id: 'user_1',
    email: 'test.user@evenbill.app',
    fullName: 'Abhay Gupta',
    defaultCurrency: 'USD',
    isPro: false,
  );
  bool authenticated = false;

  MockAuthRepository({TokenStorage? tokenStorage})
      : super(apiClient: ApiClient(), tokenStorage: tokenStorage ?? InMemoryTokenStorage());

  @override
  Future<UserModel> login({required String email, required String password}) async {
    authenticated = true;
    currentUser = UserModel(
      id: 'user_1',
      email: email,
      fullName: 'Abhay Gupta',
      defaultCurrency: 'USD',
    );
    return currentUser;
  }

  @override
  Future<UserModel> register({
    required String email,
    required String password,
    required String fullName,
    String? phoneNumber,
    String defaultCurrency = 'USD',
  }) async {
    authenticated = true;
    currentUser = UserModel(
      id: 'user_1',
      email: email,
      fullName: fullName,
      phoneNumber: phoneNumber,
      defaultCurrency: defaultCurrency,
    );
    return currentUser;
  }

  @override
  Future<UserModel> loginWithOAuth({
    required String provider,
    String? idToken,
    String? email,
    String? fullName,
    String? avatarUrl,
    String? phoneNumber,
    String? password,
  }) async {
    authenticated = true;
    currentUser = UserModel(
      id: 'oauth_user_1',
      email: email ?? '$provider.user@evenbill.app',
      fullName: fullName ?? (provider == 'google' ? 'Google User' : 'Apple User'),
      avatarUrl: avatarUrl,
      phoneNumber: phoneNumber,
      defaultCurrency: 'USD',
    );
    return currentUser;
  }

  @override
  Future<void> resetPasswordForEmail(String email) async {}

  @override
  Future<UserModel> setPassword({
    required String password,
    String? phoneNumber,
    String? fullName,
  }) async {
    currentUser = currentUser.copyWith(
      fullName: fullName ?? currentUser.fullName,
      phoneNumber: phoneNumber ?? currentUser.phoneNumber,
    );
    return currentUser;
  }

  @override
  Future<UserModel> getMe() async => currentUser;

  @override
  Future<UserModel> updateMe({String? fullName, String? defaultCurrency, String? avatarUrl}) async {
    currentUser = currentUser.copyWith(
      fullName: fullName ?? currentUser.fullName,
      defaultCurrency: defaultCurrency ?? currentUser.defaultCurrency,
      avatarUrl: avatarUrl ?? currentUser.avatarUrl,
    );
    return currentUser;
  }

  @override
  Future<void> signOut() async {
    authenticated = false;
    await tokenStorage.clearAll();
  }

  @override
  Future<UserModel?> getCachedUser() async => currentUser;

  @override
  Future<bool> isAuthenticated() async => authenticated;

  @override
  Future<Map<String, dynamic>> exportUserData() async => {
    'profile': currentUser.toJson(),
    'groups': [],
    'expenses': [],
    'settlements': [],
  };
}

class MockGroupRepository extends GroupRepository {
  final List<GroupModel> groups = [
    const GroupModel(
      id: 'grp_1',
      name: 'Apartment 404',
      groupType: 'HOME',
      baseCurrency: 'USD',
      simplifyDebts: true,
      inviteCode: 'APT404EB',
      createdBy: 'user_1',
      memberCount: 4,
      netBalance: 60.00,
    ),
    const GroupModel(
      id: 'grp_2',
      name: 'Tokyo Trip 2026',
      groupType: 'TRIP',
      baseCurrency: 'JPY',
      simplifyDebts: true,
      inviteCode: 'TYO2026E',
      createdBy: 'user_1',
      memberCount: 3,
      netBalance: -25.50,
    ),
    const GroupModel(
      id: 'grp_3',
      name: 'Couple Shared',
      groupType: 'COUPLE',
      baseCurrency: 'USD',
      simplifyDebts: false,
      inviteCode: 'CPL999EB',
      createdBy: 'user_1',
      memberCount: 2,
      netBalance: 32.00,
    ),
    const GroupModel(
      id: 'grp_4',
      name: 'Weekend Skiing',
      groupType: 'TRIP',
      baseCurrency: 'USD',
      simplifyDebts: true,
      inviteCode: 'SKI2026E',
      createdBy: 'user_1',
      memberCount: 5,
      netBalance: 0.00,
    ),
  ];

  final List<GroupInvitationModel> invitations = [
    GroupInvitationModel(
      id: 'inv_1',
      groupId: 'grp_1',
      email: 'alex@example.com',
      invitedBy: 'user_1',
      inviterName: 'Abhay Gupta',
      status: 'PENDING',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      expiresAt: DateTime.now().add(const Duration(days: 6)),
    ),
    GroupInvitationModel(
      id: 'inv_2',
      groupId: 'grp_1',
      email: 'sarah@example.com',
      invitedBy: 'user_1',
      inviterName: 'Abhay Gupta',
      status: 'ACCEPTED',
      createdAt: DateTime.now().subtract(const Duration(days: 5)),
      expiresAt: DateTime.now().add(const Duration(days: 2)),
    ),
  ];

  final List<GroupMemberModel> extraMembers = [];

  MockGroupRepository() : super(apiClient: ApiClient());

  @override
  Future<List<GroupModel>> listGroups() async => List.from(groups);

  @override
  Future<GroupDetailModel> getGroupDetails(String groupId) async {
    final grp = groups.firstWhere(
      (g) => g.id == groupId,
      orElse: () => groups.first,
    );

    return GroupDetailModel(
      group: grp,
      members: [
        const GroupMemberModel(id: 'm1', userId: 'user_1', fullName: 'Abhay Gupta', email: 'abhay@evenbill.app', role: 'OWNER'),
        const GroupMemberModel(id: 'm2', userId: 'user_2', fullName: 'Elena Rostova', email: 'elena@example.com', role: 'ADMIN'),
        const GroupMemberModel(id: 'm3', userId: 'user_3', fullName: 'Marco Rossi', email: 'marco@example.com', role: 'MEMBER'),
        ...extraMembers,
      ],
      netBalances: const [
        NetBalanceModel(userId: 'user_1', fullName: 'Abhay Gupta', netBalance: 60.00, currency: 'USD'),
        NetBalanceModel(userId: 'user_2', fullName: 'Elena Rostova', netBalance: -20.00, currency: 'USD'),
        NetBalanceModel(userId: 'user_3', fullName: 'Marco Rossi', netBalance: -40.00, currency: 'USD'),
      ],
      simplifiedDebts: const [
        SimplifiedDebtModel(
          debtorId: 'user_3',
          debtorName: 'Marco Rossi',
          creditorId: 'user_1',
          creditorName: 'Abhay Gupta',
          amount: 40.00,
          currency: 'USD',
        ),
        SimplifiedDebtModel(
          debtorId: 'user_2',
          debtorName: 'Elena Rostova',
          creditorId: 'user_1',
          creditorName: 'Abhay Gupta',
          amount: 20.00,
          currency: 'USD',
        ),
      ],
      bilateralDebts: const [],
    );
  }

  @override
  Future<GroupModel> createGroup({
    required String name,
    String groupType = 'OTHER',
    String baseCurrency = 'USD',
    bool simplifyDebts = true,
  }) async {
    final newGroup = GroupModel(
      id: 'grp_${groups.length + 1}',
      name: name,
      groupType: groupType,
      baseCurrency: baseCurrency,
      simplifyDebts: simplifyDebts,
      inviteCode: 'NEW${groups.length + 1}EB',
      createdBy: 'user_1',
      memberCount: 1,
      netBalance: 0.0,
    );
    groups.add(newGroup);
    return newGroup;
  }

  @override
  Future<GroupModel> updateGroup({
    required String groupId,
    String? name,
    String? groupType,
    bool? simplifyDebts,
    String? avatarUrl,
  }) async {
    final idx = groups.indexWhere((g) => g.id == groupId);
    if (idx >= 0) {
      final updated = GroupModel(
        id: groupId,
        name: name ?? groups[idx].name,
        groupType: groupType ?? groups[idx].groupType,
        baseCurrency: groups[idx].baseCurrency,
        simplifyDebts: simplifyDebts ?? groups[idx].simplifyDebts,
        inviteCode: groups[idx].inviteCode,
        createdBy: groups[idx].createdBy,
        memberCount: groups[idx].memberCount,
        netBalance: groups[idx].netBalance,
      );
      groups[idx] = updated;
      return updated;
    }
    return groups.first;
  }

  @override
  Future<bool> deleteGroup(String groupId) async {
    groups.removeWhere((g) => g.id == groupId);
    return true;
  }

  @override
  Future<GroupModel> joinGroupByCode(String inviteCode) async {
    final found = groups.firstWhere(
      (g) => g.inviteCode == inviteCode.toUpperCase(),
      orElse: () => groups.first,
    );
    return found;
  }

  @override
  Future<GroupMemberModel> addGroupMember({
    required String groupId,
    required String fullName,
    String? email,
    String? phoneNumber,
  }) async {
    final member = GroupMemberModel(
      id: 'm_${extraMembers.length + 4}',
      userId: 'user_new_${fullName.hashCode}',
      fullName: fullName.trim(),
      email: (email != null && email.trim().isNotEmpty)
          ? email.trim().toLowerCase()
          : 'member.mock@member.evenbill.local',
      role: 'MEMBER',
    );
    extraMembers.add(member);
    return member;
  }

  @override
  Future<GroupInvitationModel> createInvitation({
    required String groupId,
    required String email,
  }) async {
    final inv = GroupInvitationModel(
      id: 'inv_${invitations.length + 1}',
      groupId: groupId,
      email: email,
      invitedBy: 'user_1',
      inviterName: 'Abhay Gupta',
      status: 'PENDING',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 7)),
    );
    invitations.add(inv);
    return inv;
  }

  @override
  Future<List<GroupInvitationModel>> listInvitations(String groupId) async => List.from(invitations);

  @override
  Future<bool> revokeInvitation(String invitationId) async {
    final idx = invitations.indexWhere((i) => i.id == invitationId);
    if (idx >= 0) {
      invitations[idx] = invitations[idx].copyWith(status: 'REVOKED');
      return true;
    }
    return false;
  }
}

class MockExpenseRepository extends ExpenseRepository {
  final List<ExpenseModel> expenses = [
    ExpenseModel(
      id: 'exp_1',
      description: 'Organic Groceries',
      totalAmount: 142.50,
      currency: 'USD',
      baseCurrencyAmount: 142.50,
      category: 'GROCERIES',
      splitType: 'EQUAL',
      groupId: 'grp_1',
      createdBy: 'user_1',
      creatorName: 'Abhay Gupta',
      expenseDate: DateTime.now().subtract(const Duration(hours: 4)),
      createdAt: DateTime.now().subtract(const Duration(hours: 4)),
      payers: const [PayerModel(userId: 'user_1', fullName: 'You', amountPaid: 142.50)],
      splits: const [
        SplitModel(userId: 'user_1', fullName: 'You', owedAmount: 35.62),
        SplitModel(userId: 'user_2', fullName: 'Elena', owedAmount: 35.62),
        SplitModel(userId: 'user_3', fullName: 'Marco', owedAmount: 35.63),
        SplitModel(userId: 'user_4', fullName: 'Priya', owedAmount: 35.63),
      ],
    ),
    ExpenseModel(
      id: 'exp_2',
      description: 'Team Dinner',
      totalAmount: 85.00,
      currency: 'USD',
      baseCurrencyAmount: 85.00,
      category: 'FOOD',
      splitType: 'EQUAL',
      groupId: 'grp_1',
      createdBy: 'user_2',
      creatorName: 'Elena Rostova',
      expenseDate: DateTime.now().subtract(const Duration(days: 1)),
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      payers: const [PayerModel(userId: 'user_2', fullName: 'Elena Rostova', amountPaid: 85.00)],
      splits: const [
        SplitModel(userId: 'user_1', fullName: 'You', owedAmount: 42.50),
        SplitModel(userId: 'user_2', fullName: 'Elena Rostova', owedAmount: 42.50),
      ],
    ),
  ];

  MockExpenseRepository() : super(apiClient: ApiClient());

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
    final exp = ExpenseModel(
      id: 'exp_${expenses.length + 1}',
      description: description,
      totalAmount: totalAmount,
      currency: currency,
      baseCurrencyAmount: totalAmount,
      splitType: splitType,
      category: category,
      groupId: groupId,
      createdBy: 'user_1',
      creatorName: 'Abhay Gupta',
      expenseDate: expenseDate ?? DateTime.now(),
      createdAt: DateTime.now(),
      notes: notes,
      payers: payers ?? const [PayerModel(userId: 'user_1', fullName: 'You', amountPaid: 0)],
      splits: splits ?? const [],
    );
    expenses.insert(0, exp);
    return exp;
  }

  @override
  Future<ExpenseModel> updateExpense(
    String expenseId, {
    String? description,
    double? totalAmount,
    String? currency,
    String? splitType,
    String? category,
    DateTime? expenseDate,
    String? notes,
    List<PayerModel>? payers,
    List<String>? participantIds,
    List<SplitModel>? splits,
    Map<String, double>? percentages,
    Map<String, double>? shares,
    Map<String, double>? adjustments,
    List<ItemizedItemInput>? items,
    double? tax,
    double? tip,
    double? fee,
    double? discount,
  }) async {
    final idx = expenses.indexWhere((e) => e.id == expenseId);
    if (idx >= 0) {
      final updated = ExpenseModel(
        id: expenseId,
        description: description ?? expenses[idx].description,
        totalAmount: totalAmount ?? expenses[idx].totalAmount,
        currency: currency ?? expenses[idx].currency,
        baseCurrencyAmount: totalAmount ?? expenses[idx].baseCurrencyAmount,
        splitType: splitType ?? expenses[idx].splitType,
        category: category ?? expenses[idx].category,
        groupId: expenses[idx].groupId,
        createdBy: expenses[idx].createdBy,
        creatorName: expenses[idx].creatorName,
        expenseDate: expenseDate ?? expenses[idx].expenseDate,
        createdAt: expenses[idx].createdAt,
        notes: notes ?? expenses[idx].notes,
        payers: payers ?? expenses[idx].payers,
        splits: splits ?? expenses[idx].splits,
      );
      expenses[idx] = updated;
      return updated;
    }
    return expenses.first;
  }

  @override
  Future<bool> deleteExpense(String expenseId) async {
    expenses.removeWhere((e) => e.id == expenseId);
    return true;
  }

  @override
  Future<ExpenseModel> getExpense(String expenseId) async {
    return expenses.firstWhere(
      (e) => e.id == expenseId,
      orElse: () => expenses.first,
    );
  }

  @override
  Future<List<ExpenseModel>> listGroupExpenses(String groupId) async {
    return expenses.where((e) => e.groupId == groupId).toList();
  }

  @override
  Future<List<ExpenseModel>> listPersonalExpenses() async => List.from(expenses);

  @override
  Future<Map<String, dynamic>> get1on1Balance(String friendId, {String currency = 'USD'}) async {
    return {'net_balance': 45.00, 'currency': currency};
  }
}

class MockSettlementRepository extends SettlementRepository {
  final List<SettlementModel> settlements = [];

  MockSettlementRepository() : super(apiClient: ApiClient());

  @override
  Future<SettlementModel> recordSettlement({
    String? idempotencyKey,
    String? groupId,
    String? payerId,
    required String recipientId,
    required double amount,
    String currency = 'USD',
    String paymentMethod = 'CASH',
    String? transactionReference,
    String? notes,
  }) async {
    final s = SettlementModel(
      id: 'stl_${settlements.length + 1}',
      groupId: groupId,
      payerId: payerId ?? 'user_1',
      recipientId: recipientId,
      amount: amount,
      currency: currency,
      paymentMethod: paymentMethod,
      transactionReference: transactionReference,
      notes: notes,
      settledAt: DateTime.now(),
    );

    settlements.add(s);
    return s;
  }

  @override
  Future<List<SettlementModel>> listGroupSettlements(String groupId) async => List.from(settlements);
}

class MockFriendRepository extends FriendRepository {
  final List<FriendModel> friends = [
    const FriendModel(
      id: 'fr_1',
      name: 'Elena Rostova',
      email: 'elena@example.com',
      netBalance: 45.00,
      currency: 'USD',
    ),
    const FriendModel(
      id: 'fr_2',
      name: 'Marco Rossi',
      email: 'marco@example.com',
      netBalance: -25.50,
      currency: 'USD',
    ),
    const FriendModel(
      id: 'fr_3',
      name: 'Priya Patel',
      email: 'priya@example.com',
      netBalance: 0.00,
      currency: 'USD',
    ),
    const FriendModel(
      id: 'fr_4',
      name: 'Liam Chen',
      email: 'liam@example.com',
      netBalance: 78.25,
      currency: 'USD',
    ),
    const FriendModel(
      id: 'fr_5',
      name: 'Aisha Al-Mansoor',
      email: 'aisha@example.com',
      netBalance: -12.00,
      currency: 'USD',
    ),
  ];

  MockFriendRepository() : super(apiClient: ApiClient());

  @override
  Future<List<FriendModel>> listFriends() async => List.from(friends);

  @override
  Future<FriendModel> addFriend(String email) async {
    final fr = FriendModel(
      id: 'fr_${friends.length + 1}',
      name: email.split('@').first,
      email: email,
      netBalance: 0.0,
      currency: 'USD',
    );
    friends.add(fr);
    return fr;
  }
}

class MockActivityRepository extends ActivityRepository {
  final ActivitySummaryModel summary = const ActivitySummaryModel(
    totalNetBalance: 66.50,
    youAreOwedTotal: 146.25,
    youOweTotal: 79.75,
    monthlySpending: 420.50,
    currency: 'USD',
    activeGroupsCount: 4,
    activeFriendsCount: 5,
  );

  final List<ActivityItemModel> activities = [
    ActivityItemModel(
      id: 'exp_1',
      itemType: 'EXPENSE',
      title: 'Organic Groceries',
      description: 'Groceries at Whole Foods',
      category: 'GROCERIES',
      totalAmount: 142.50,
      currency: 'USD',
      userNetShare: 106.88,
      groupName: 'Apartment 404',
      createdByName: 'You',
      timestamp: DateTime.now().subtract(const Duration(hours: 4)),
    ),
    ActivityItemModel(
      id: 'exp_2',
      itemType: 'EXPENSE',
      title: 'Team Dinner',
      description: 'Italian dinner in Shibuya',
      category: 'FOOD',
      totalAmount: 85.00,
      currency: 'USD',
      userNetShare: -42.50,
      groupName: 'Tokyo Trip 2026',
      createdByName: 'Elena Rostova',
      timestamp: DateTime.now().subtract(const Duration(days: 1)),
    ),
    ActivityItemModel(
      id: 'stl_1',
      itemType: 'SETTLEMENT',
      title: 'Marco paid You',
      description: 'Settled ski gear share',
      category: 'GENERAL',
      totalAmount: 40.00,
      currency: 'USD',
      userNetShare: 40.00,
      groupName: 'Apartment 404',
      createdByName: 'Marco Rossi',
      timestamp: DateTime.now().subtract(const Duration(days: 2)),
    ),
  ];

  MockActivityRepository() : super(apiClient: ApiClient());

  @override
  Future<List<ActivityItemModel>> listActivity({
    String? groupId,
    String? category,
    String? search,
    int limit = 50,
  }) async {
    return List.from(activities);
  }

  @override
  Future<ActivitySummaryModel> getActivitySummary({String? currency}) async => summary;
}

class MockSubscriptionRepository extends SubscriptionRepository {
  EntitlementModel currentEntitlement = const EntitlementModel(
    plan: 'FREE',
    isPro: false,
    dailyLimit: 4,
    dailyUsed: 0,
    dailyRemaining: 4,
    windowHours: 24,
  );

  MockSubscriptionRepository() : super(apiClient: ApiClient());

  @override
  Future<EntitlementModel> getEntitlements() async => currentEntitlement;

  @override
  Future<EntitlementModel> mockUpgrade({required String tier}) async {
    final isPro = tier.toUpperCase() != 'FREE';
    currentEntitlement = currentEntitlement.copyWith(
      plan: tier.toUpperCase(),
      isPro: isPro,
      dailyLimit: isPro ? null : 4,
      dailyRemaining: isPro ? null : 4,
      receiptOcrEnabled: isPro,
      crossGroupSimplificationEnabled: isPro,
    );
    return currentEntitlement;
  }
}

class MockProRepository extends ProRepository {
  List<SplitTemplateModel> splitTemplates = [
    SplitTemplateModel(
      id: 'tmpl_1',
      groupId: 'grp_1',
      name: 'Couples (60/40 Split)',
      splitType: 'PERCENTAGE',
      allocations: const [
        SplitAllocationItem(userId: 'user_1', value: 60.0),
        SplitAllocationItem(userId: 'user_2', value: 40.0),
      ],
      isDefault: true,
      createdBy: 'user_1',
      createdAt: DateTime.now(),
    ),
  ];

  ReceiptModel? lastUploadedReceipt;
  SpendingInsightsModel insights = const SpendingInsightsModel(
    currency: 'USD',
    totalSpentPersonalShare: 142.50,
    totalPaidByUser: 250.00,
    totalExpensesCount: 8,
    categories: [
      CategorySpendingModel(category: 'GROCERIES', totalAmount: 85.00, percentage: 59.6, expenseCount: 4),
      CategorySpendingModel(category: 'DINING OUT', totalAmount: 42.50, percentage: 29.8, expenseCount: 2),
      CategorySpendingModel(category: 'UTILITIES', totalAmount: 15.00, percentage: 10.5, expenseCount: 2),
    ],
    monthlyTrend: [
      MonthlySpendingModel(month: '2026-08', totalAmount: 45.00, expenseCount: 2),
      MonthlySpendingModel(month: '2026-09', totalAmount: 52.50, expenseCount: 3),
      MonthlySpendingModel(month: '2026-10', totalAmount: 45.00, expenseCount: 3),
    ],
    groupBreakdown: [
      GroupSpendingModel(groupId: 'grp_1', groupName: 'Apartment 404', totalAmount: 142.50, percentage: 100.0),
    ],
    isPro: true,
  );

  List<BankTransactionModel> bankTransactions = const [
    BankTransactionModel(
      transactionId: 'btx_1',
      accountId: 'acc_chase_checking',
      merchantName: 'Whole Foods Market',
      amount: 64.20,
      currency: 'USD',
      date: '2026-10-21',
      category: 'GROCERIES',
      pending: false,
      suggestedExpenseDescription: 'Whole Foods Market',
    ),
    BankTransactionModel(
      transactionId: 'btx_2',
      accountId: 'acc_chase_checking',
      merchantName: 'Blue Bottle Coffee',
      amount: 14.50,
      currency: 'USD',
      date: '2026-10-22',
      category: 'DINING OUT',
      pending: false,
      suggestedExpenseDescription: 'Blue Bottle Coffee',
    ),
  ];

  MockProRepository() : super(apiClient: ApiClient());

  @override
  Future<ReceiptModel> uploadReceipt({
    required String fileName,
    required String mimeType,
    required List<int> bytes,
    String? expenseId,
  }) async {
    lastUploadedReceipt = ReceiptModel(
      id: 'rcpt_mock_123',
      fileName: fileName,
      fileSizeBytes: bytes.length,
      mimeType: mimeType,
      ocrStatus: 'COMPLETED',
      extractedMerchant: 'Trattoria Bella',
      extractedTotal: 78.50,
      extractedCurrency: 'USD',
      tax: 6.50,
      tip: 12.00,
      items: const [
        ReceiptItemModel(description: 'Margherita Pizza', amount: 22.00, assignedParticipantIds: ['user_1']),
        ReceiptItemModel(description: 'Tiramisu', amount: 14.00, assignedParticipantIds: ['user_2']),
        ReceiptItemModel(description: 'House Chianti', amount: 24.00, assignedParticipantIds: ['user_1', 'user_2']),
      ],
    );
    return lastUploadedReceipt!;
  }

  @override
  Future<Map<String, dynamic>> getReceiptSignedUrl(String receiptId) async {
    return {
      'signed_url': 'https://storage.evenbill.internal/receipts/$receiptId.jpg?signature=signed_url_token',
      'expires_in': 900,
    };
  }

  @override
  Future<bool> deleteReceipt(String receiptId) async => true;

  @override
  Future<SpendingInsightsModel> getSpendingInsights({
    String? groupId,
    DateTime? startDate,
    DateTime? endDate,
    String currency = 'USD',
  }) async {
    return insights.copyWith(currency: currency);
  }

  @override
  Future<List<SplitTemplateModel>> getSplitTemplates(String groupId) async {
    return splitTemplates.where((t) => t.groupId == groupId).toList();
  }

  @override
  Future<SplitTemplateModel> createSplitTemplate({
    required String groupId,
    required String name,
    required String splitType,
    required List<Map<String, dynamic>> allocations,
    bool isDefault = false,
  }) async {
    final newTemplate = SplitTemplateModel(
      id: 'tmpl_${splitTemplates.length + 1}',
      groupId: groupId,
      name: name,
      splitType: splitType,
      allocations: allocations.map((a) => SplitAllocationItem.fromJson(a)).toList(),
      isDefault: isDefault,
      createdBy: 'user_1',
      createdAt: DateTime.now(),
    );
    splitTemplates.add(newTemplate);
    return newTemplate;
  }

  @override
  Future<FXRateModel> getExchangeRate(String fromCurrency, String toCurrency) async {
    final rate = fromCurrency == toCurrency ? 1.0 : (fromCurrency == 'EUR' && toCurrency == 'USD' ? 1.0850 : 0.92);
    return FXRateModel(
      fromCurrency: fromCurrency,
      toCurrency: toCurrency,
      rate: rate,
      status: 'LIVE',
      source: 'ECB_DAILY_REFERENCE',
      timestamp: DateTime.now(),
      isStale: false,
    );
  }

  @override
  Future<FXConversionModel> convertCurrency({
    required double amount,
    required String fromCurrency,
    required String toCurrency,
  }) async {
    final rate = fromCurrency == toCurrency ? 1.0 : (fromCurrency == 'EUR' && toCurrency == 'USD' ? 1.0850 : 0.92);
    return FXConversionModel(
      originalAmount: amount,
      originalCurrency: fromCurrency,
      targetCurrency: toCurrency,
      exchangeRate: rate,
      convertedAmount: (amount * rate * 100).round() / 100,
      source: 'ECB_DAILY_REFERENCE',
      timestamp: DateTime.now(),
      rateStatus: 'LIVE',
    );
  }

  @override
  Future<List<ExpenseModel>> searchExpenses({
    String? query,
    String? category,
    DateTime? startDate,
    DateTime? endDate,
    double? minAmount,
    double? maxAmount,
    String? groupId,
    bool? hasReceipt,
  }) async {
    return [
      ExpenseModel(
        id: 'exp_search_1',
        description: 'Trattoria Dinner with Colleagues',
        totalAmount: 78.50,
        currency: 'USD',
        baseCurrencyAmount: 78.50,
        category: category ?? 'DINING OUT',
        expenseDate: DateTime.now(),
        createdAt: DateTime.now(),
        createdBy: 'user_1',
        hasReceipt: true,
      ),
      ExpenseModel(
        id: 'exp_search_2',
        description: 'Supermarket Groceries',
        totalAmount: 52.10,
        currency: 'USD',
        baseCurrencyAmount: 52.10,
        category: 'GROCERIES',
        expenseDate: DateTime.now().subtract(const Duration(days: 1)),
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        createdBy: 'user_1',
        hasReceipt: false,
      ),
    ];
  }

  @override
  Future<BankIntegrationStatusModel> getBankStatus({String countryCode = 'US'}) async {
    return const BankIntegrationStatusModel(
      isAvailable: true,
      providerName: 'Plaid / Tink Institutional',
      isProviderApproved: true,
      supportedCountries: ['US', 'GB', 'DE', 'FR', 'ES', 'IT', 'NL', 'SE', 'IE'],
      complianceFramework: 'Open Banking / PSD2 Directive 2015/2366',
      requiresConsent: true,
      readOnlyEnforced: true,
      credentialsConfigured: true,
      sandboxMode: true,
    );
  }

  @override
  Future<List<BankTransactionModel>> syncBankTransactions({
    required String accountId,
    String countryCode = 'US',
    bool isSandbox = true,
  }) async {
    return List.from(bankTransactions);
  }

  @override
  Future<Map<String, dynamic>> verifyPurchaseReceipt({
    required String store,
    required String purchaseToken,
    required String productId,
    bool isSandbox = true,
  }) async {
    return {
      'success': true,
      'verified': true,
      'is_pro': true,
      'store': store,
      'product_id': productId,
      'status': 'ACTIVE',
      'grace_period': false,
    };
  }
}


