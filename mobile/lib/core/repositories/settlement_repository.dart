import 'package:uuid/uuid.dart';
import '../network/api_client.dart';
import '../models/settlement_model.dart';
import '../constants/api_constants.dart';

class SettlementRepository {
  final ApiClient apiClient;
  final _uuid = const Uuid();

  SettlementRepository({required this.apiClient});

  Future<SettlementModel> recordSettlement({
    String? idempotencyKey,
    String? groupId,
    String? payerId,
    required String recipientId,
    required double amount,
    String currency = 'USD',
    String paymentMethod = 'CASH',
    String? transactionReference,
    String? notes,
  }) async {
    final key = idempotencyKey ?? _uuid.v4();

    final res = await apiClient.post(
      ApiConstants.settlements,
      data: {
        'idempotency_key': key,
        'group_id': groupId,
        if (payerId != null && payerId.isNotEmpty) 'payer_id': payerId,
        'recipient_id': recipientId,
        'amount': amount,
        'currency': currency.toUpperCase(),
        'payment_method': paymentMethod.toUpperCase(),
        if (transactionReference != null && transactionReference.isNotEmpty)
          'transaction_reference': transactionReference.trim(),
        if (notes != null && notes.isNotEmpty) 'notes': notes.trim(),
      },
    );
    return SettlementModel.fromJson(res as Map<String, dynamic>);
  }

  Future<List<SettlementModel>> listGroupSettlements(String groupId) async {
    final res = await apiClient.get('${ApiConstants.settlements}group/$groupId');
    final list = res as List<dynamic>? ?? [];
    return list.map((s) => SettlementModel.fromJson(s as Map<String, dynamic>)).toList();
  }
}
