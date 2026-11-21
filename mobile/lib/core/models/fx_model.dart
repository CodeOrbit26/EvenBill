class FXRateModel {
  final String fromCurrency;
  final String toCurrency;
  final double rate;
  final String source;
  final DateTime timestamp;
  final String status; // LIVE, STALE_FALLBACK, UNAVAILABLE
  final bool isStale;
  final String? warning;

  const FXRateModel({
    required this.fromCurrency,
    required this.toCurrency,
    required this.rate,
    required this.source,
    required this.timestamp,
    required this.status,
    this.isStale = false,
    this.warning,
  });

  factory FXRateModel.fromJson(Map<String, dynamic> json) {
    return FXRateModel(
      fromCurrency: json['from_currency'] as String? ?? 'USD',
      toCurrency: json['to_currency'] as String? ?? 'USD',
      rate: double.tryParse(json['rate']?.toString() ?? '1.0') ?? 1.0,
      source: json['source'] as String? ?? 'IDENTITY',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      status: json['status'] as String? ?? 'LIVE',
      isStale: json['is_stale'] as bool? ?? false,
      warning: json['warning'] as String?,
    );
  }
}

class FXConversionModel {
  final double originalAmount;
  final String originalCurrency;
  final double convertedAmount;
  final String targetCurrency;
  final double exchangeRate;
  final String source;
  final DateTime timestamp;
  final String rateStatus;
  final String? warning;

  const FXConversionModel({
    required this.originalAmount,
    required this.originalCurrency,
    required this.convertedAmount,
    required this.targetCurrency,
    required this.exchangeRate,
    required this.source,
    required this.timestamp,
    required this.rateStatus,
    this.warning,
  });

  factory FXConversionModel.fromJson(Map<String, dynamic> json) {
    return FXConversionModel(
      originalAmount: double.tryParse(json['original_amount']?.toString() ?? '0') ?? 0.0,
      originalCurrency: json['original_currency'] as String? ?? 'USD',
      convertedAmount: double.tryParse(json['converted_amount']?.toString() ?? '0') ?? 0.0,
      targetCurrency: json['target_currency'] as String? ?? 'USD',
      exchangeRate: double.tryParse(json['exchange_rate']?.toString() ?? '1.0') ?? 1.0,
      source: json['source'] as String? ?? 'IDENTITY',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
      rateStatus: json['rate_status'] as String? ?? 'LIVE',
      warning: json['warning'] as String?,
    );
  }
}
