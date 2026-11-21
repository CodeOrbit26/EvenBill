class BankIntegrationStatusModel {
  final bool isAvailable;
  final String? providerName;
  final bool isProviderApproved;
  final List<String> supportedCountries;
  final String complianceFramework;
  final bool requiresConsent;
  final bool readOnlyEnforced;
  final bool credentialsConfigured;
  final bool sandboxMode;

  const BankIntegrationStatusModel({
    required this.isAvailable,
    this.providerName,
    required this.isProviderApproved,
    required this.supportedCountries,
    required this.complianceFramework,
    required this.requiresConsent,
    required this.readOnlyEnforced,
    required this.credentialsConfigured,
    required this.sandboxMode,
  });

  factory BankIntegrationStatusModel.fromJson(Map<String, dynamic> json) {
    return BankIntegrationStatusModel(
      isAvailable: json['is_available'] as bool? ?? false,
      providerName: json['provider_name'] as String?,
      isProviderApproved: json['is_provider_approved'] as bool? ?? false,
      supportedCountries: (json['supported_countries'] as List<dynamic>? ?? [])
          .map((c) => c.toString())
          .toList(),
      complianceFramework: json['compliance_framework'] as String? ?? 'Open Banking / PSD2 (Read-Only)',
      requiresConsent: json['requires_consent'] as bool? ?? true,
      readOnlyEnforced: json['read_only_enforced'] as bool? ?? true,
      credentialsConfigured: json['credentials_configured'] as bool? ?? false,
      sandboxMode: json['sandbox_mode'] as bool? ?? true,
    );
  }
}

class BankTransactionModel {
  final String transactionId;
  final String accountId;
  final String date;
  final double amount;
  final String currency;
  final String merchantName;
  final String category;
  final bool pending;
  final String suggestedExpenseDescription;

  const BankTransactionModel({
    required this.transactionId,
    required this.accountId,
    required this.date,
    required this.amount,
    required this.currency,
    required this.merchantName,
    required this.category,
    required this.pending,
    required this.suggestedExpenseDescription,
  });

  factory BankTransactionModel.fromJson(Map<String, dynamic> json) {
    return BankTransactionModel(
      transactionId: json['transaction_id'] as String? ?? '',
      accountId: json['account_id'] as String? ?? '',
      date: json['date'] as String? ?? '',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      merchantName: json['merchant_name'] as String? ?? 'Merchant',
      category: json['category'] as String? ?? 'General',
      pending: json['pending'] as bool? ?? false,
      suggestedExpenseDescription: json['suggested_expense_description'] as String? ?? 'Imported Transaction',
    );
  }
}
