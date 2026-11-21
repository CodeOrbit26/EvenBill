class ActivityItemModel {
  final String id;
  final String itemType;
  final String title;
  final String description;
  final String category;
  final double totalAmount;
  final String currency;
  final double userNetShare;
  final String? groupId;
  final String? groupName;
  final String createdByName;
  final DateTime timestamp;

  const ActivityItemModel({
    required this.id,
    required this.itemType,
    required this.title,
    required this.description,
    required this.category,
    required this.totalAmount,
    required this.currency,
    required this.userNetShare,
    this.groupId,
    this.groupName,
    required this.createdByName,
    required this.timestamp,
  });

  factory ActivityItemModel.fromJson(Map<String, dynamic> json) {
    return ActivityItemModel(
      id: json['id'] as String,
      itemType: json['item_type'] as String? ?? 'EXPENSE',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'GENERAL',
      totalAmount: double.tryParse(json['total_amount']?.toString() ?? '0') ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      userNetShare: double.tryParse(json['user_net_share']?.toString() ?? '0') ?? 0.0,
      groupId: json['group_id'] as String?,
      groupName: json['group_name'] as String?,
      createdByName: json['created_by_name'] as String? ?? 'User',
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : DateTime.now(),
    );
  }
}

class ActivitySummaryModel {
  final double totalNetBalance;
  final double youAreOwedTotal;
  final double youOweTotal;
  final double monthlySpending;
  final String currency;
  final int activeGroupsCount;
  final int activeFriendsCount;

  const ActivitySummaryModel({
    required this.totalNetBalance,
    required this.youAreOwedTotal,
    required this.youOweTotal,
    required this.monthlySpending,
    this.currency = 'USD',
    required this.activeGroupsCount,
    required this.activeFriendsCount,
  });

  factory ActivitySummaryModel.fromJson(Map<String, dynamic> json) {
    return ActivitySummaryModel(
      totalNetBalance: double.tryParse(json['total_net_balance']?.toString() ?? '0') ?? 0.0,
      youAreOwedTotal: double.tryParse(json['you_are_owed_total']?.toString() ?? '0') ?? 0.0,
      youOweTotal: double.tryParse(json['you_owe_total']?.toString() ?? '0') ?? 0.0,
      monthlySpending: double.tryParse(json['monthly_spending']?.toString() ?? '0') ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      activeGroupsCount: json['active_groups_count'] as int? ?? 0,
      activeFriendsCount: json['active_friends_count'] as int? ?? 0,
    );
  }

  factory ActivitySummaryModel.empty() {
    return const ActivitySummaryModel(
      totalNetBalance: 0.0,
      youAreOwedTotal: 0.0,
      youOweTotal: 0.0,
      monthlySpending: 0.0,
      currency: 'USD',
      activeGroupsCount: 0,
      activeFriendsCount: 0,
    );
  }
}
