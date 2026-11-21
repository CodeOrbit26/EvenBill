import '../network/api_client.dart';
import '../models/entitlement_model.dart';
import '../constants/api_constants.dart';

class SubscriptionRepository {
  final ApiClient apiClient;

  SubscriptionRepository({required this.apiClient});

  Future<EntitlementModel> getEntitlements() async {
    final res = await apiClient.get(ApiConstants.subscriptionsMe);
    return EntitlementModel.fromJson(res as Map<String, dynamic>);
  }

  Future<EntitlementModel> mockUpgrade({required String tier}) async {
    final res = await apiClient.post(
      ApiConstants.mockUpgrade,
      data: {'tier': tier},
    );
    return EntitlementModel.fromJson(res as Map<String, dynamic>);
  }
}
