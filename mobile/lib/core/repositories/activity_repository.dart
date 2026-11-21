import '../network/api_client.dart';
import '../models/activity_model.dart';

class ActivityRepository {
  final ApiClient apiClient;

  ActivityRepository({required this.apiClient});

  Future<List<ActivityItemModel>> listActivity({
    String? groupId,
    String? category,
    String? search,
    int limit = 50,
  }) async {
    final params = <String, dynamic>{
      'limit': limit,
      if (groupId != null) 'group_id': groupId,
      if (category != null && category != 'ALL') 'category': category,
      if (search != null && search.isNotEmpty) 'search': search.trim(),
    };

    final res = await apiClient.get('/activity/', queryParameters: params);
    final list = res as List<dynamic>? ?? [];
    return list.map((a) => ActivityItemModel.fromJson(a as Map<String, dynamic>)).toList();
  }

  Future<ActivitySummaryModel> getActivitySummary({String? currency}) async {
    final params = <String, dynamic>{
      if (currency != null && currency.isNotEmpty) 'currency': currency,
    };
    final res = await apiClient.get('/activity/summary', queryParameters: params);
    return ActivitySummaryModel.fromJson(res as Map<String, dynamic>);
  }
}
