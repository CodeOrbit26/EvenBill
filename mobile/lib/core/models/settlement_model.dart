class SettlementModel {
  final String id;
  final String? idempotencyKey;
  final String? groupId;
  final String payerId;
  final String payerName;
  final String recipientId;
  final String recipientName;
  final double amount;
  final String currency;
  final String paymentMethod;
  final String? transactionReference;
  final String? notes;
  final DateTime settledAt;

  const SettlementModel({
    required this.id,
    this.idempotencyKey,
    this.groupId,
    required this.payerId,
    this.payerName = 'Payer',
    required this.recipientId,
    this.recipientName = 'Recipient',
    required this.amount,
    this.currency = 'USD',
    this.paymentMethod = 'CASH',
    this.transactionReference,
    this.notes,
    required this.settledAt,
  });

  factory SettlementModel.fromJson(Map<String, dynamic> json) {
    return SettlementModel(
      id: json['id'] as String,
      idempotencyKey: json['idempotency_key'] as String?,
      groupId: json['group_id'] as String?,
      payerId: json['payer_id'] as String,
      payerName: json['payer_name'] as String? ?? 'Payer',
      recipientId: json['recipient_id'] as String,
      recipientName: json['recipient_name'] as String? ?? 'Recipient',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      currency: json['currency'] as String? ?? 'USD',
      paymentMethod: json['payment_method'] as String? ?? 'CASH',
      transactionReference: json['transaction_reference'] as String?,
      notes: json['notes'] as String?,
      settledAt: json['settled_at'] != null
          ? DateTime.parse(json['settled_at'] as String)
          : DateTime.now(),
    );
  }
}
