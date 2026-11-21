class CategorySpendingModel {
  final String category;
  final double totalAmount;
  final double percentage;
  final int expenseCount;

  const CategorySpendingModel({
    required this.category,
    required this.totalAmount,
    required this.percentage,
    required this.expenseCount,
  });

  factory CategorySpendingModel.fromJson(Map<String, dynamic> json) {
    return CategorySpendingModel(
      category: json['category'] as String? ?? 'General',
      totalAmount: double.tryParse(json['total_amount']?.toString() ?? '0') ?? 0.0,
      percentage: double.tryParse(json['percentage']?.toString() ?? '0') ?? 0.0,
      expenseCount: json['expense_count'] as int? ?? 0,
    );
  }
}

class MonthlySpendingModel {
  final String month;
  final double totalAmount;
  final int expenseCount;

  const MonthlySpendingModel({
    required this.month,
    required this.totalAmount,
    required this.expenseCount,
  });

  factory MonthlySpendingModel.fromJson(Map<String, dynamic> json) {
    return MonthlySpendingModel(
      month: json['month'] as String? ?? '',
      totalAmount: double.tryParse(json['total_amount']?.toString() ?? '0') ?? 0.0,
      expenseCount: json['expense_count'] as int? ?? 0,
    );
  }
}

class GroupSpendingModel {
  final String? groupId;
  final String groupName;
  final double totalAmount;
  final double percentage;

  const GroupSpendingModel({
    this.groupId,
    required this.groupName,
    required this.totalAmount,
    required this.percentage,
  });

  factory GroupSpendingModel.fromJson(Map<String, dynamic> json) {
    return GroupSpendingModel(
      groupId: json['group_id'] as String?,
      groupName: json['group_name'] as String? ?? 'Non-group',
      totalAmount: double.tryParse(json['total_amount']?.toString() ?? '0') ?? 0.0,
      percentage: double.tryParse(json['percentage']?.toString() ?? '0') ?? 0.0,
    );
  }
}

class SpendingInsightsModel {
  final double totalSpentPersonalShare;
  final double totalPaidByUser;
  final int totalExpensesCount;
  final String currency;
  final List<CategorySpendingModel> categories;
  final List<MonthlySpendingModel> monthlyTrend;
  final List<GroupSpendingModel> groupBreakdown;
  final bool isPro;

  const SpendingInsightsModel({
    required this.totalSpentPersonalShare,
    required this.totalPaidByUser,
    required this.totalExpensesCount,
    required this.currency,
    required this.categories,
    required this.monthlyTrend,
    required this.groupBreakdown,
    required this.isPro,
  });

  factory SpendingInsightsModel.fromJson(Map<String, dynamic> json) {
    final rawCats = (json['categories'] as List<dynamic>? ?? [])
        .map((c) => CategorySpendingModel.fromJson(c as Map<String, dynamic>))
        .toList();

    final rawMonths = (json['monthly_trend'] as List<dynamic>? ?? [])
        .map((m) => MonthlySpendingModel.fromJson(m as Map<String, dynamic>))
        .toList();

    final rawGroups = (json['group_breakdown'] as List<dynamic>? ?? [])
        .map((g) => GroupSpendingModel.fromJson(g as Map<String, dynamic>))
        .toList();

    return SpendingInsightsModel(
      totalSpentPersonalShare: double.tryParse(json['total_spent_personal_share']?.toString() ?? '0') ?? 0.0,
      totalPaidByUser: double.tryParse(json['total_paid_by_user']?.toString() ?? '0') ?? 0.0,
      totalExpensesCount: json['total_expenses_count'] as int? ?? 0,
      currency: json['currency'] as String? ?? 'USD',
      categories: rawCats,
      monthlyTrend: rawMonths,
      groupBreakdown: rawGroups,
      isPro: json['is_pro'] as bool? ?? false,
    );
  }

  SpendingInsightsModel copyWith({
    double? totalSpentPersonalShare,
    double? totalPaidByUser,
    int? totalExpensesCount,
    String? currency,
    List<CategorySpendingModel>? categories,
    List<MonthlySpendingModel>? monthlyTrend,
    List<GroupSpendingModel>? groupBreakdown,
    bool? isPro,
  }) {
    return SpendingInsightsModel(
      totalSpentPersonalShare: totalSpentPersonalShare ?? this.totalSpentPersonalShare,
      totalPaidByUser: totalPaidByUser ?? this.totalPaidByUser,
      totalExpensesCount: totalExpensesCount ?? this.totalExpensesCount,
      currency: currency ?? this.currency,
      categories: categories ?? this.categories,
      monthlyTrend: monthlyTrend ?? this.monthlyTrend,
      groupBreakdown: groupBreakdown ?? this.groupBreakdown,
      isPro: isPro ?? this.isPro,
    );
  }
}

