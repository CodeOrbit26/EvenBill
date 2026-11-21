import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../network/api_client.dart';
import '../constants/api_constants.dart';
import '../models/receipt_model.dart';
import '../models/split_template_model.dart';
import '../models/spending_insights_model.dart';
import '../models/fx_model.dart';
import '../models/bank_model.dart';
import '../models/expense_model.dart';

class ProRepository {
  final ApiClient apiClient;

  ProRepository({required this.apiClient});

  // ==========================================
  // RECEIPTS & OCR
  // ==========================================

  Future<ReceiptModel> uploadReceipt({
    required String fileName,
    required String mimeType,
    required List<int> bytes,
    String? expenseId,
  }) async {
    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: fileName),
      if (expenseId != null) 'expense_id': expenseId,
    });

    final res = await apiClient.post(
      ApiConstants.receiptsUpload,
      data: formData,
    );
    return ReceiptModel.fromJson(res as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getReceiptSignedUrl(String receiptId) async {
    final res = await apiClient.get('/receipts/$receiptId/signed-url');
    return res as Map<String, dynamic>;
  }

  Future<bool> deleteReceipt(String receiptId) async {
    final res = await apiClient.delete('/receipts/$receiptId');
    return (res as Map<String, dynamic>)['deleted'] as bool? ?? true;
  }

  // ==========================================
  // SPENDING ANALYTICS & INSIGHTS
  // ==========================================

  Future<SpendingInsightsModel> getSpendingInsights({
    String? groupId,
    DateTime? startDate,
    DateTime? endDate,
    String currency = 'USD',
  }) async {
    final queryParams = <String, dynamic>{
      'currency': currency,
      if (groupId != null) 'group_id': groupId,
      if (startDate != null) 'start_date': startDate.toIso8601String().substring(0, 10),
      if (endDate != null) 'end_date': endDate.toIso8601String().substring(0, 10),
    };

    final res = await apiClient.get(
      ApiConstants.analyticsSpending,
      queryParameters: queryParams,
    );
    return SpendingInsightsModel.fromJson(res as Map<String, dynamic>);
  }

  // ==========================================
  // GROUP SPLIT TEMPLATES
  // ==========================================

  Future<List<SplitTemplateModel>> getSplitTemplates(String groupId) async {
    final res = await apiClient.get('/groups/$groupId/split-templates');
    final list = res as List<dynamic>? ?? [];
    return list.map((item) => SplitTemplateModel.fromJson(item as Map<String, dynamic>)).toList();
  }

  Future<SplitTemplateModel> createSplitTemplate({
    required String groupId,
    required String name,
    required String splitType,
    required List<Map<String, dynamic>> allocations,
    bool isDefault = false,
  }) async {
    final res = await apiClient.post(
      '/groups/$groupId/split-templates',
      data: {
        'name': name,
        'split_type': splitType,
        'allocations': allocations,
        'is_default': isDefault,
      },
    );
    return SplitTemplateModel.fromJson(res as Map<String, dynamic>);
  }

  Future<SplitTemplateModel> updateSplitTemplate({
    required String groupId,
    required String templateId,
    String? name,
    String? splitType,
    List<Map<String, dynamic>>? allocations,
    bool? isDefault,
  }) async {
    final res = await apiClient.put(
      '/groups/$groupId/split-templates/$templateId',
      data: {
        if (name != null) 'name': name,
        if (splitType != null) 'split_type': splitType,
        if (allocations != null) 'allocations': allocations,
        if (isDefault != null) 'is_default': isDefault,
      },
    );
    return SplitTemplateModel.fromJson(res as Map<String, dynamic>);
  }

  Future<bool> deleteSplitTemplate(String groupId, String templateId) async {
    final res = await apiClient.delete('/groups/$groupId/split-templates/$templateId');
    return (res as Map<String, dynamic>)['deleted'] as bool? ?? true;
  }

  // ==========================================
  // FX CURRENCY CONVERSION
  // ==========================================

  Future<FXRateModel> getExchangeRate(String fromCurrency, String toCurrency) async {
    final res = await apiClient.get(
      ApiConstants.fxRate,
      queryParameters: {
        'from_currency': fromCurrency,
        'to_currency': toCurrency,
      },
    );
    return FXRateModel.fromJson(res as Map<String, dynamic>);
  }

  Future<FXConversionModel> convertCurrency({
    required double amount,
    required String fromCurrency,
    required String toCurrency,
  }) async {
    final res = await apiClient.post(
      ApiConstants.fxConvert,
      data: {
        'amount': amount,
        'from_currency': fromCurrency,
        'to_currency': toCurrency,
      },
    );
    return FXConversionModel.fromJson(res as Map<String, dynamic>);
  }

  // ==========================================
  // EXPENSE SEARCH & FILTERING
  // ==========================================

  Future<List<ExpenseModel>> searchExpenses({
    String? query,
    String? category,
    DateTime? startDate,
    DateTime? endDate,
    double? minAmount,
    double? maxAmount,
    String? groupId,
    bool? hasReceipt,
  }) async {
    final queryParams = <String, dynamic>{
      if (query != null && query.isNotEmpty) 'q': query,
      if (category != null && category.isNotEmpty) 'category': category,
      if (startDate != null) 'start_date': startDate.toIso8601String().substring(0, 10),
      if (endDate != null) 'end_date': endDate.toIso8601String().substring(0, 10),
      if (minAmount != null) 'min_amount': minAmount,
      if (maxAmount != null) 'max_amount': maxAmount,
      if (groupId != null) 'group_id': groupId,
      if (hasReceipt != null) 'has_receipt': hasReceipt,
    };

    final res = await apiClient.get(
      ApiConstants.searchExpenses,
      queryParameters: queryParams,
    );
    final list = res as List<dynamic>? ?? [];
    return list.map((item) => ExpenseModel.fromJson(item as Map<String, dynamic>)).toList();
  }

  // ==========================================
  // BANK INTEGRATION COMPLIANCE & SYNC
  // ==========================================

  Future<BankIntegrationStatusModel> getBankStatus({String countryCode = 'US'}) async {
    final res = await apiClient.get(
      ApiConstants.bankStatus,
      queryParameters: {'country_code': countryCode},
    );
    return BankIntegrationStatusModel.fromJson(res as Map<String, dynamic>);
  }

  Future<List<BankTransactionModel>> syncBankTransactions({
    required String accountId,
    String countryCode = 'US',
    bool isSandbox = true,
  }) async {
    final res = await apiClient.post(
      ApiConstants.bankSync,
      data: {
        'account_id': accountId,
        'country_code': countryCode,
        'is_sandbox': isSandbox,
      },
    );
    final list = res as List<dynamic>? ?? [];
    return list.map((item) => BankTransactionModel.fromJson(item as Map<String, dynamic>)).toList();
  }

  // ==========================================
  // MOBILE PURCHASE SERVER VERIFICATION
  // ==========================================

  Future<Map<String, dynamic>> verifyPurchaseReceipt({
    required String store,
    required String purchaseToken,
    required String productId,
    bool isSandbox = true,
  }) async {
    final res = await apiClient.post(
      ApiConstants.verifyReceipt,
      data: {
        'store': store,
        'purchase_token': purchaseToken,
        'product_id': productId,
        'is_sandbox': isSandbox,
      },
    );
    return res as Map<String, dynamic>;
  }
}
