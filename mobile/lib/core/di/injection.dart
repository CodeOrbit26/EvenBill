import '../network/api_client.dart';
import '../network/token_storage.dart';
import '../repositories/auth_repository.dart';
import '../repositories/group_repository.dart';
import '../repositories/expense_repository.dart';
import '../repositories/settlement_repository.dart';
import '../repositories/friend_repository.dart';
import '../repositories/activity_repository.dart';
import '../repositories/subscription_repository.dart';
import '../repositories/pro_repository.dart';

class Injection {
  static TokenStorage? _tokenStorage;
  static ApiClient? _apiClient;
  static AuthRepository? _authRepository;
  static GroupRepository? _groupRepository;
  static ExpenseRepository? _expenseRepository;
  static SettlementRepository? _settlementRepository;
  static FriendRepository? _friendRepository;
  static ActivityRepository? _activityRepository;
  static SubscriptionRepository? _subscriptionRepository;
  static ProRepository? _proRepository;

  static TokenStorage get tokenStorage => _tokenStorage ??= TokenStorage();
  static ApiClient get apiClient => _apiClient ??= ApiClient(customTokenStorage: tokenStorage);

  static AuthRepository get authRepository =>
      _authRepository ??= AuthRepository(apiClient: apiClient, tokenStorage: tokenStorage);

  static GroupRepository get groupRepository =>
      _groupRepository ??= GroupRepository(apiClient: apiClient);

  static ExpenseRepository get expenseRepository =>
      _expenseRepository ??= ExpenseRepository(apiClient: apiClient);

  static SettlementRepository get settlementRepository =>
      _settlementRepository ??= SettlementRepository(apiClient: apiClient);

  static FriendRepository get friendRepository =>
      _friendRepository ??= FriendRepository(apiClient: apiClient);

  static ActivityRepository get activityRepository =>
      _activityRepository ??= ActivityRepository(apiClient: apiClient);

  static SubscriptionRepository get subscriptionRepository =>
      _subscriptionRepository ??= SubscriptionRepository(apiClient: apiClient);

  static ProRepository get proRepository =>
      _proRepository ??= ProRepository(apiClient: apiClient);

  /// Allows tests to swap in custom or mock implementations
  static void setMockRepositories({
    AuthRepository? auth,
    GroupRepository? group,
    ExpenseRepository? expense,
    SettlementRepository? settlement,
    FriendRepository? friend,
    ActivityRepository? activity,
    SubscriptionRepository? subscription,
    ProRepository? pro,
    TokenStorage? tokens,
    ApiClient? client,
  }) {
    if (auth != null) _authRepository = auth;
    if (group != null) _groupRepository = group;
    if (expense != null) _expenseRepository = expense;
    if (settlement != null) _settlementRepository = settlement;
    if (friend != null) _friendRepository = friend;
    if (activity != null) _activityRepository = activity;
    if (subscription != null) _subscriptionRepository = subscription;
    if (pro != null) _proRepository = pro;
    if (tokens != null) _tokenStorage = tokens;
    if (client != null) _apiClient = client;
  }

  static void reset() {
    _tokenStorage = null;
    _apiClient = null;
    _authRepository = null;
    _groupRepository = null;
    _expenseRepository = null;
    _settlementRepository = null;
    _friendRepository = null;
    _activityRepository = null;
    _subscriptionRepository = null;
    _proRepository = null;
  }
}
