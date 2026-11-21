class ReceiptItemModel {
  final String description;
  final double amount;
  final int quantity;
  final List<String> assignedParticipantIds;

  const ReceiptItemModel({
    required this.description,
    required this.amount,
    this.quantity = 1,
    this.assignedParticipantIds = const [],
  });

  factory ReceiptItemModel.fromJson(Map<String, dynamic> json) {
    return ReceiptItemModel(
      description: json['description'] as String? ?? 'Item',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      quantity: json['quantity'] as int? ?? 1,
      assignedParticipantIds: (json['assigned_participant_ids'] as List<dynamic>? ?? [])
          .map((id) => id.toString())
          .toList(),
    );
  }

  ReceiptItemModel copyWith({
    String? description,
    double? amount,
    int? quantity,
    List<String>? assignedParticipantIds,
  }) {
    return ReceiptItemModel(
      description: description ?? this.description,
      amount: amount ?? this.amount,
      quantity: quantity ?? this.quantity,
      assignedParticipantIds: assignedParticipantIds ?? this.assignedParticipantIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'description': description,
    'amount': amount,
    'quantity': quantity,
    'assigned_participant_ids': assignedParticipantIds,
  };
}

class ReceiptModel {
  final String id;
  final String fileName;
  final String mimeType;
  final int fileSizeBytes;
  final bool isDuplicate;
  final String ocrStatus;
  final String? extractedMerchant;
  final double? extractedTotal;
  final String extractedCurrency;
  final List<ReceiptItemModel> items;
  final double tax;
  final double tip;
  final String message;

  const ReceiptModel({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.fileSizeBytes,
    this.isDuplicate = false,
    required this.ocrStatus,
    this.extractedMerchant,
    this.extractedTotal,
    this.extractedCurrency = 'USD',
    this.items = const [],
    this.tax = 0.0,
    this.tip = 0.0,
    this.message = '',
  });

  factory ReceiptModel.fromJson(Map<String, dynamic> json) {
    final ocrData = json['ocr_data'] as Map<String, dynamic>? ?? {};
    final rawItems = (ocrData['items'] as List<dynamic>? ?? [])
        .map((i) => ReceiptItemModel.fromJson(i as Map<String, dynamic>))
        .toList();

    return ReceiptModel(
      id: json['id'] as String? ?? '',
      fileName: json['file_name'] as String? ?? 'receipt.jpg',
      mimeType: json['mime_type'] as String? ?? 'image/jpeg',
      fileSizeBytes: json['file_size_bytes'] as int? ?? 0,
      isDuplicate: json['is_duplicate'] as bool? ?? false,
      ocrStatus: json['ocr_status'] as String? ?? 'UNKNOWN',
      extractedMerchant: json['extracted_merchant'] as String? ?? ocrData['merchant_name'] as String?,
      extractedTotal: double.tryParse(json['extracted_total']?.toString() ?? ocrData['total']?.toString() ?? '0') ?? 0.0,
      extractedCurrency: json['extracted_currency'] as String? ?? ocrData['currency'] as String? ?? 'USD',
      items: rawItems,
      tax: double.tryParse(ocrData['tax']?.toString() ?? '0') ?? 0.0,
      tip: double.tryParse(ocrData['tip']?.toString() ?? '0') ?? 0.0,
      message: json['message'] as String? ?? '',
    );
  }
}
