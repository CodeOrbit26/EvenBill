class GroupModel {
  final String id;
  final String name;
  final String groupType;
  final String baseCurrency;
  final bool simplifyDebts;
  final String inviteCode;
  final String? avatarUrl;
  final String createdBy;
  final bool isArchived;
  final int memberCount;
  final double netBalance;
  final DateTime? createdAt;

  const GroupModel({
    required this.id,
    required this.name,
    this.groupType = 'OTHER',
    this.baseCurrency = 'USD',
    this.simplifyDebts = true,
    required this.inviteCode,
    this.avatarUrl,
    required this.createdBy,
    this.isArchived = false,
    this.memberCount = 1,
    this.netBalance = 0.0,
    this.createdAt,
  });

  String get type => groupType;
  String get currency => baseCurrency;

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      id: json['id'] as String,
      name: json['name'] as String,
      groupType: json['group_type'] as String? ?? 'OTHER',
      baseCurrency: json['base_currency'] as String? ?? 'USD',
      simplifyDebts: json['simplify_debts'] as bool? ?? true,
      inviteCode: json['invite_code'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      createdBy: json['created_by'] as String? ?? '',
      isArchived: json['is_archived'] as bool? ?? false,
      memberCount: json['member_count'] as int? ?? 1,
      netBalance: double.tryParse(json['net_balance']?.toString() ?? '0') ?? 0.0,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'group_type': groupType,
      'base_currency': baseCurrency,
      'simplify_debts': simplifyDebts,
      'invite_code': inviteCode,
      'avatar_url': avatarUrl,
      'created_by': createdBy,
      'is_archived': isArchived,
      'member_count': memberCount,
      'net_balance': netBalance,
      'created_at': createdAt?.toIso8601String(),
    };
  }
}


class GroupMemberModel {
  final String id;
  final String userId;
  final String fullName;
  final String email;
  final String? avatarUrl;
  final String role;
  final DateTime? joinedAt;

  const GroupMemberModel({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.email,
    this.avatarUrl,
    this.role = 'MEMBER',
    this.joinedAt,
  });

  factory GroupMemberModel.fromJson(Map<String, dynamic> json) {
    return GroupMemberModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String? ?? 'User',
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String? ?? 'MEMBER',
      joinedAt: json['joined_at'] != null ? DateTime.tryParse(json['joined_at'] as String) : null,
    );
  }
}

class NetBalanceModel {
  final String userId;
  final String fullName;
  final double netBalance;
  final String currency;

  const NetBalanceModel({
    required this.userId,
    required this.fullName,
    required this.netBalance,
    required this.currency,
  });

  factory NetBalanceModel.fromJson(Map<String, dynamic> json) {
    return NetBalanceModel(
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String? ?? 'User',
      netBalance: double.tryParse(json['net_balance']?.toString() ?? '0') ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
    );
  }
}

class SimplifiedDebtModel {
  final String debtorId;
  final String debtorName;
  final String creditorId;
  final String creditorName;
  final double amount;
  final String currency;

  const SimplifiedDebtModel({
    required this.debtorId,
    required this.debtorName,
    required this.creditorId,
    required this.creditorName,
    required this.amount,
    required this.currency,
  });

  factory SimplifiedDebtModel.fromJson(Map<String, dynamic> json) {
    return SimplifiedDebtModel(
      debtorId: json['debtor_id'] as String,
      debtorName: json['debtor_name'] as String? ?? 'User',
      creditorId: json['creditor_id'] as String,
      creditorName: json['creditor_name'] as String? ?? 'User',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
    );
  }
}

class BilateralDebtModel {
  final String debtorId;
  final String debtorName;
  final String creditorId;
  final String creditorName;
  final double amount;
  final String currency;

  const BilateralDebtModel({
    required this.debtorId,
    required this.debtorName,
    required this.creditorId,
    required this.creditorName,
    required this.amount,
    required this.currency,
  });

  factory BilateralDebtModel.fromJson(Map<String, dynamic> json) {
    return BilateralDebtModel(
      debtorId: json['debtor_id'] as String,
      debtorName: json['debtor_name'] as String? ?? 'User',
      creditorId: json['creditor_id'] as String,
      creditorName: json['creditor_name'] as String? ?? 'User',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
    );
  }
}

class GroupDetailModel {
  final GroupModel group;
  final List<GroupMemberModel> members;
  final List<NetBalanceModel> netBalances;
  final List<SimplifiedDebtModel> simplifiedDebts;
  final List<BilateralDebtModel> bilateralDebts;

  const GroupDetailModel({
    required this.group,
    required this.members,
    required this.netBalances,
    required this.simplifiedDebts,
    required this.bilateralDebts,
  });

  factory GroupDetailModel.fromJson(Map<String, dynamic> json) {
    return GroupDetailModel(
      group: GroupModel.fromJson(json['group'] as Map<String, dynamic>),
      members: (json['members'] as List<dynamic>? ?? [])
          .map((m) => GroupMemberModel.fromJson(m as Map<String, dynamic>))
          .toList(),
      netBalances: (json['net_balances'] as List<dynamic>? ?? [])
          .map((n) => NetBalanceModel.fromJson(n as Map<String, dynamic>))
          .toList(),
      simplifiedDebts: (json['simplified_debts'] as List<dynamic>? ?? [])
          .map((s) => SimplifiedDebtModel.fromJson(s as Map<String, dynamic>))
          .toList(),
      bilateralDebts: (json['bilateral_debts'] as List<dynamic>? ?? [])
          .map((b) => BilateralDebtModel.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }
}
