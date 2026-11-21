import '../config/app_config.dart';

class ApiConstants {
  // Dynamically resolved based on runtime environment:
  // - Android Emulator: http://10.0.2.2:8000/api/v1
  // - iOS Simulator / macOS: http://127.0.0.1:8000/api/v1
  // - LAN Device: --dart-define=API_BASE_URL=http://<IP>:8000/api/v1
  static String get baseUrl => AppConfig.apiBaseUrl;

  static const String register = '/auth/register';
  static const String login = '/auth/login';
  static const String refresh = '/auth/refresh';
  static const String me = '/auth/me';
  static const String oauth = '/auth/oauth';
  static const String setPassword = '/auth/set-password';

  static const String groups = '/groups/';
  static const String joinGroup = '/groups/join';
  static const String expenses = '/expenses/';
  static const String settlements = '/settlements/';
  static const String subscriptionsMe = '/subscriptions/me';
  static const String mockUpgrade = '/subscriptions/mock-upgrade';
  static const String verifyReceipt = '/subscriptions/verify-receipt';
  static const String userExport = '/users/me/export';

  // Pro Features Endpoints
  static const String receiptsUpload = '/receipts/upload';
  static const String analyticsSpending = '/analytics/spending';
  static const String fxRate = '/fx/rate';
  static const String fxConvert = '/fx/convert';
  static const String searchExpenses = '/expenses/search';
  static const String bankStatus = '/bank/status';
  static const String bankSync = '/bank/sync-transactions';
}
