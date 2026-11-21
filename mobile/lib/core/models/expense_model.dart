class PayerModel {
  final String userId;
  final String fullName;
  final double amountPaid;

  const PayerModel({
    required this.userId,
    required this.fullName,
    required this.amountPaid,
  });

  factory PayerModel.fromJson(Map<String, dynamic> json) {
    return PayerModel(
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String? ?? 'User',
      amountPaid: double.tryParse(json['amount_paid']?.toString() ?? '0') ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'amount_paid': amountPaid,
  };
}

class SplitModel {
  final String userId;
  final String fullName;
  final double owedAmount;
  final double? shareQuantity;

  const SplitModel({
    required this.userId,
    required this.fullName,
    required this.owedAmount,
    this.shareQuantity,
  });

  factory SplitModel.fromJson(Map<String, dynamic> json) {
    return SplitModel(
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String? ?? 'User',
      owedAmount: double.tryParse(json['owed_amount']?.toString() ?? '0') ?? 0.0,
      shareQuantity: json['share_quantity'] != null
          ? double.tryParse(json['share_quantity'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'owed_amount': owedAmount,
    if (shareQuantity != null) 'share_quantity': shareQuantity,
  };
}

class ItemizedItemInput {
  final String description;
  final double amount;
  final List<String> participantIds;

  const ItemizedItemInput({
    required this.description,
    required this.amount,
    required this.participantIds,
  });

  Map<String, dynamic> toJson() => {
    'description': description,
    'amount': amount,
    'participant_ids': participantIds,
  };
}

class ExpenseModel {
  final String id;
  final String? idempotencyKey;
  final String transactionType;
  final String? originalExpenseId;
  final String? groupId;
  final String createdBy;
  final String creatorName;
  final String description;
  final double totalAmount;
  final String currency;
  final double baseCurrencyAmount;
  final double exchangeRate;
  final String exchangeRateSource;
  final DateTime? exchangeRateTimestamp;
  final String splitType;
  final String category;
  final DateTime expenseDate;
  final String? notes;
  final bool isDeleted;
  final int version;
  final DateTime createdAt;
  final List<PayerModel> payers;
  final List<SplitModel> splits;
  final bool hasReceipt;

  const ExpenseModel({
    required this.id,
    this.idempotencyKey,
    this.transactionType = 'EXPENSE',
    this.originalExpenseId,
    this.groupId,
    required this.createdBy,
    this.creatorName = 'User',
    required this.description,
    required this.totalAmount,
    required this.currency,
    required this.baseCurrencyAmount,
    this.exchangeRate = 1.0,
    this.exchangeRateSource = 'DEFAULT',
    this.exchangeRateTimestamp,
    this.splitType = 'EQUAL',
    this.category = 'GENERAL',
    required this.expenseDate,
    this.notes,
    this.isDeleted = false,
    this.version = 1,
    required this.createdAt,
    this.payers = const [],
    this.splits = const [],
    this.hasReceipt = false,
  });

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      id: json['id'] as String,
      idempotencyKey: json['idempotency_key'] as String?,
      transactionType: json['transaction_type'] as String? ?? 'EXPENSE',
      originalExpenseId: json['original_expense_id'] as String?,
      groupId: json['group_id'] as String?,
      createdBy: json['created_by'] as String? ?? '',
      creatorName: json['creator_name'] as String? ?? 'User',
      description: json['description'] as String? ?? '',
      totalAmount: double.tryParse(json['total_amount']?.toString() ?? '0') ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      baseCurrencyAmount: double.tryParse(json['base_currency_amount']?.toString() ?? '0') ?? 0.0,
      exchangeRate: double.tryParse(json['exchange_rate']?.toString() ?? '1.0') ?? 1.0,
      exchangeRateSource: json['exchange_rate_source'] as String? ?? 'DEFAULT',
      exchangeRateTimestamp: json['exchange_rate_timestamp'] != null
          ? DateTime.tryParse(json['exchange_rate_timestamp'] as String)
          : null,
      splitType: json['split_type'] as String? ?? 'EQUAL',
      category: json['category'] as String? ?? 'GENERAL',
      expenseDate: json['expense_date'] != null
          ? DateTime.parse(json['expense_date'] as String)
          : DateTime.now(),
      notes: json['notes'] as String?,
      isDeleted: json['is_deleted'] as bool? ?? false,
      version: json['version'] as int? ?? 1,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      payers: (json['payers'] as List<dynamic>? ?? [])
          .map((p) => PayerModel.fromJson(p as Map<String, dynamic>))
          .toList(),
      splits: (json['splits'] as List<dynamic>? ?? [])
          .map((s) => SplitModel.fromJson(s as Map<String, dynamic>))
          .toList(),
      hasReceipt: json['has_receipt'] as bool? ?? false,
    );
  }

  /// Calculates net position for a user on this specific expense.
  /// Positive = user paid more than they owe (lent money).
  /// Negative = user owes more than they paid (borrowed money).
  double getUserNetShare(String userId) {
    final paid = payers.where((p) => p.userId == userId).fold<double>(0.0, (acc, p) => acc + p.amountPaid);
    final owed = splits.where((s) => s.userId == userId).fold<double>(0.0, (acc, s) => acc + s.owedAmount);
    return paid - owed;
  }

  String get dateFormatted =>
      '${expenseDate.year}-${expenseDate.month.toString().padLeft(2, '0')}-${expenseDate.day.toString().padLeft(2, '0')}';

  String get paidBy {
    if (payers.isEmpty) return 'Paid by $creatorName';
    if (payers.length == 1) return 'Paid by ${payers.first.fullName}';
    return 'Paid by ${payers.first.fullName} (+${payers.length - 1} others)';
  }

  List<String> get participants {
    if (splits.isEmpty) return ['You'];
    return splits.map((s) => s.fullName).toList();
  }

  String get groupName => groupId != null ? 'Group Expense' : 'Non-group Expense';

  double get yourNetShare {
    // If splits exist, calculate user share or default to equal
    if (payers.isNotEmpty) {
      final firstPayer = payers.first;
      final split = splits.firstWhere((s) => s.userId == firstPayer.userId, orElse: () => splits.first);
      return firstPayer.amountPaid - split.owedAmount;
    }
    return 0.0;
  }
}

