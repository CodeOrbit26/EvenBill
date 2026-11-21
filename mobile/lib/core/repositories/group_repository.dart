import '../network/api_client.dart';
import '../models/group_model.dart';
import '../models/group_invitation_model.dart';
import '../constants/api_constants.dart';

class GroupRepository {
  final ApiClient apiClient;

  GroupRepository({required this.apiClient});

  Future<List<GroupModel>> listGroups() async {
    final res = await apiClient.get(ApiConstants.groups);
    final list = res as List<dynamic>? ?? [];
    return list.map((g) => GroupModel.fromJson(g as Map<String, dynamic>)).toList();
  }

  Future<GroupDetailModel> getGroupDetails(String groupId) async {
    final res = await apiClient.get('${ApiConstants.groups}$groupId');
    return GroupDetailModel.fromJson(res as Map<String, dynamic>);
  }

  Future<GroupModel> createGroup({
    required String name,
    String groupType = 'OTHER',
    String baseCurrency = 'USD',
    bool simplifyDebts = true,
  }) async {
    final res = await apiClient.post(
      ApiConstants.groups,
      data: {
        'name': name.trim(),
        'group_type': groupType.toUpperCase(),
        'base_currency': baseCurrency.toUpperCase(),
        'simplify_debts': simplifyDebts,
      },
    );
    return GroupModel.fromJson(res as Map<String, dynamic>);
  }

  Future<GroupModel> updateGroup({
    required String groupId,
    String? name,
    String? groupType,
    bool? simplifyDebts,
    String? avatarUrl,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name.trim();
    if (groupType != null) data['group_type'] = groupType.toUpperCase().trim();
    if (simplifyDebts != null) data['simplify_debts'] = simplifyDebts;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl.trim();

    final res = await apiClient.put('${ApiConstants.groups}$groupId', data: data);
    return GroupModel.fromJson(res as Map<String, dynamic>);
  }

  Future<bool> deleteGroup(String groupId) async {
    final res = await apiClient.delete('${ApiConstants.groups}$groupId');
    if (res is Map<String, dynamic> && res['deleted'] == true) {
      return true;
    }
    return true;
  }

  Future<GroupModel> joinGroupByCode(String inviteCode) async {
    final cleanCode = inviteCode.trim().toUpperCase();
    final res = await apiClient.post('${ApiConstants.joinGroup}/$cleanCode');
    return GroupModel.fromJson(res as Map<String, dynamic>);
  }

  Future<GroupMemberModel> addGroupMember({
    required String groupId,
    required String fullName,
    String? email,
    String? phoneNumber,
  }) async {
    final cleanEmail = email?.trim().toLowerCase();
    final cleanPhone = phoneNumber?.trim();
    final res = await apiClient.post(
      '${ApiConstants.groups}$groupId/members',
      data: {
        'full_name': fullName.trim(),
        if (cleanEmail != null && cleanEmail.isNotEmpty) 'email': cleanEmail,
        if (cleanPhone != null && cleanPhone.isNotEmpty) 'phone_number': cleanPhone,
      },
    );
    return GroupMemberModel.fromJson(res as Map<String, dynamic>);
  }

  Future<GroupInvitationModel> createInvitation({
    required String groupId,
    required String email,
  }) async {
    final res = await apiClient.post(
      '${ApiConstants.groups}$groupId/invitations',
      data: {'email': email.trim().toLowerCase()},
    );
    return GroupInvitationModel.fromJson(res as Map<String, dynamic>);
  }

  Future<List<GroupInvitationModel>> listInvitations(String groupId) async {
    final res = await apiClient.get('${ApiConstants.groups}$groupId/invitations');
    final list = res as List<dynamic>? ?? [];
    return list.map((i) => GroupInvitationModel.fromJson(i as Map<String, dynamic>)).toList();
  }

  Future<bool> revokeInvitation(String invitationId) async {
    final res = await apiClient.post('${ApiConstants.groups}invitations/$invitationId/revoke');
    return res is Map<String, dynamic> && res['revoked'] == true;
  }

  Future<bool> acceptInvitation(String invitationId) async {
    final res = await apiClient.post('${ApiConstants.groups}invitations/$invitationId/accept');
    return res is Map<String, dynamic> && res['accepted'] == true;
  }
}
