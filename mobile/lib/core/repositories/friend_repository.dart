import '../network/api_client.dart';
import '../models/friend_model.dart';

class FriendRepository {
  final ApiClient apiClient;

  FriendRepository({required this.apiClient});

  Future<List<FriendModel>> listFriends() async {
    final res = await apiClient.get('/friends/');
    final list = res as List<dynamic>? ?? [];
    return list.map((f) => FriendModel.fromJson(f as Map<String, dynamic>)).toList();
  }

  Future<FriendModel> addFriend(String email) async {
    final res = await apiClient.post(
      '/friends/',
      data: {'email': email.trim().toLowerCase()},
    );
    return FriendModel.fromJson(res as Map<String, dynamic>);
  }
}
