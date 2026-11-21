class EntitlementModel {
  final String plan;
  final bool isPro;
  final int? dailyLimit;
  final int dailyUsed;
  final int? dailyRemaining;
  final DateTime? resetsAt;
  final int? resetsInSeconds;
  final int windowHours;
  final bool receiptOcrEnabled;
  final bool crossGroupSimplificationEnabled;
  final String monthlyPrice;
  final String annualPrice;

  const EntitlementModel({
    required this.plan,
    required this.isPro,
    this.dailyLimit,
    this.dailyUsed = 0,
    this.dailyRemaining,
    this.resetsAt,
    this.resetsInSeconds,
    this.windowHours = 24,
    this.receiptOcrEnabled = false,
    this.crossGroupSimplificationEnabled = false,
    this.monthlyPrice = '4.99',
    this.annualPrice = '39.99',
  });

  factory EntitlementModel.fromJson(Map<String, dynamic> json) {
    final plan = (json['plan'] as String?)?.toUpperCase() ?? 'FREE';
    final isPro = json['is_pro'] as bool? ?? (plan == 'PRO');
    final features = json['features'] as Map<String, dynamic>? ?? {};

    final dailyCreation = features['DAILY_EXPENSE_CREATION'] as Map<String, dynamic>? ?? {};
    final dailyLimit = dailyCreation['limit'] as int?;
    final dailyUsed = dailyCreation['used'] as int? ?? 0;
    final dailyRemaining = dailyCreation['remaining'] as int?;
    final resetsAtStr = dailyCreation['resets_at'] as String?;
    final resetsInSeconds = dailyCreation['resets_in_seconds'] as int?;
    final windowHours = dailyCreation['window_hours'] as int? ?? 24;

    final ocr = features['RECEIPT_OCR'] as Map<String, dynamic>? ?? {};
    final receiptOcrEnabled = ocr['enabled'] as bool? ?? isPro;

    final crossGroup = features['CROSS_GROUP_SIMPLIFICATION'] as Map<String, dynamic>? ?? {};
    final crossGroupSimplificationEnabled = crossGroup['enabled'] as bool? ?? isPro;

    return EntitlementModel(
      plan: plan,
      isPro: isPro,
      dailyLimit: dailyLimit,
      dailyUsed: dailyUsed,
      dailyRemaining: dailyRemaining,
      resetsAt: resetsAtStr != null ? DateTime.tryParse(resetsAtStr) : null,
      resetsInSeconds: resetsInSeconds,
      windowHours: windowHours,
      receiptOcrEnabled: receiptOcrEnabled,
      crossGroupSimplificationEnabled: crossGroupSimplificationEnabled,
    );
  }

  EntitlementModel copyWith({
    String? plan,
    bool? isPro,
    int? dailyLimit,
    int? dailyUsed,
    int? dailyRemaining,
    DateTime? resetsAt,
    int? resetsInSeconds,
    int? windowHours,
    bool? receiptOcrEnabled,
    bool? crossGroupSimplificationEnabled,
    String? monthlyPrice,
    String? annualPrice,
  }) {
    return EntitlementModel(
      plan: plan ?? this.plan,
      isPro: isPro ?? this.isPro,
      dailyLimit: dailyLimit ?? this.dailyLimit,
      dailyUsed: dailyUsed ?? this.dailyUsed,
      dailyRemaining: dailyRemaining ?? this.dailyRemaining,
      resetsAt: resetsAt ?? this.resetsAt,
      resetsInSeconds: resetsInSeconds ?? this.resetsInSeconds,
      windowHours: windowHours ?? this.windowHours,
      receiptOcrEnabled: receiptOcrEnabled ?? this.receiptOcrEnabled,
      crossGroupSimplificationEnabled: crossGroupSimplificationEnabled ?? this.crossGroupSimplificationEnabled,
      monthlyPrice: monthlyPrice ?? this.monthlyPrice,
      annualPrice: annualPrice ?? this.annualPrice,
    );
  }
}
