import 'package:uuid/uuid.dart';
import '../network/api_client.dart';
import '../models/expense_model.dart';
import '../constants/api_constants.dart';

class ExpenseRepository {
  final ApiClient apiClient;
  final _uuid = const Uuid();

  ExpenseRepository({required this.apiClient});

  Future<ExpenseModel> createExpense({
    String? idempotencyKey,
    String? groupId,
    required String description,
    required double totalAmount,
    String currency = 'USD',
    String splitType = 'EQUAL',
    String category = 'GENERAL',
    DateTime? expenseDate,
    String? notes,
    List<PayerModel>? payers,
    List<String>? participantIds,
    List<SplitModel>? splits,
    Map<String, double>? percentages,
    Map<String, double>? shares,
    Map<String, double>? adjustments,
    List<ItemizedItemInput>? items,
    double tax = 0.0,
    double tip = 0.0,
    double fee = 0.0,
    double discount = 0.0,
    String transactionType = 'EXPENSE',
    String? originalExpenseId,
    double? exchangeRate,
    String? exchangeRateSource,
  }) async {
    // Generate idempotency key if not supplied to prevent duplicate submissions on network retries
    final key = idempotencyKey ?? _uuid.v4();

    final data = <String, dynamic>{
      'idempotency_key': key,
      'group_id': groupId,
      'description': description.trim(),
      'total_amount': totalAmount,
      'currency': currency.toUpperCase(),
      'split_type': splitType.toUpperCase(),
      'category': category.toUpperCase(),
      'expense_date': (expenseDate ?? DateTime.now()).toIso8601String().substring(0, 10),
      if (notes != null && notes.isNotEmpty) 'notes': notes.trim(),
      'transaction_type': transactionType.toUpperCase(),
      if (originalExpenseId != null) 'original_expense_id': originalExpenseId,
      if (exchangeRate != null) 'exchange_rate': exchangeRate,
      if (exchangeRateSource != null) 'exchange_rate_source': exchangeRateSource,
      if (tax > 0) 'tax': tax,
      if (tip > 0) 'tip': tip,
      if (fee > 0) 'fee': fee,
      if (discount > 0) 'discount': discount,
    };

    if (payers != null && payers.isNotEmpty) {
      data['payers'] = payers.map((p) => p.toJson()).toList();
    }
    if (participantIds != null && participantIds.isNotEmpty) {
      data['participant_ids'] = participantIds;
    }
    if (splits != null && splits.isNotEmpty) {
      data['splits'] = splits.map((s) => s.toJson()).toList();
    }
    if (percentages != null && percentages.isNotEmpty) {
      data['percentages'] = percentages;
    }
    if (shares != null && shares.isNotEmpty) {
      data['shares'] = shares;
    }
    if (adjustments != null && adjustments.isNotEmpty) {
      data['adjustments'] = adjustments;
    }
    if (items != null && items.isNotEmpty) {
      data['items'] = items.map((i) => i.toJson()).toList();
    }

    final res = await apiClient.post(ApiConstants.expenses, data: data);
    return ExpenseModel.fromJson(res as Map<String, dynamic>);
  }

  Future<ExpenseModel> updateExpense(
    String expenseId, {
    String? description,
    double? totalAmount,
    String? currency,
    String? splitType,
    String? category,
    DateTime? expenseDate,
    String? notes,
    List<PayerModel>? payers,
    List<String>? participantIds,
    List<SplitModel>? splits,
    Map<String, double>? percentages,
    Map<String, double>? shares,
    Map<String, double>? adjustments,
    List<ItemizedItemInput>? items,
    double? tax,
    double? tip,
    double? fee,
    double? discount,
  }) async {
    final data = <String, dynamic>{};
    if (description != null) data['description'] = description.trim();
    if (totalAmount != null) data['total_amount'] = totalAmount;
    if (currency != null) data['currency'] = currency.toUpperCase();
    if (splitType != null) data['split_type'] = splitType.toUpperCase();
    if (category != null) data['category'] = category.toUpperCase();
    if (expenseDate != null) {
      data['expense_date'] = expenseDate.toIso8601String().substring(0, 10);
    }
    if (notes != null) data['notes'] = notes.trim();
    if (payers != null) data['payers'] = payers.map((p) => p.toJson()).toList();
    if (participantIds != null) data['participant_ids'] = participantIds;
    if (splits != null) data['splits'] = splits.map((s) => s.toJson()).toList();
    if (percentages != null) data['percentages'] = percentages;
    if (shares != null) data['shares'] = shares;
    if (adjustments != null) data['adjustments'] = adjustments;
    if (items != null) data['items'] = items.map((i) => i.toJson()).toList();
    if (tax != null) data['tax'] = tax;
    if (tip != null) data['tip'] = tip;
    if (fee != null) data['fee'] = fee;
    if (discount != null) data['discount'] = discount;

    final res = await apiClient.put('${ApiConstants.expenses}$expenseId', data: data);
    return ExpenseModel.fromJson(res as Map<String, dynamic>);
  }

  Future<bool> deleteExpense(String expenseId) async {
    final res = await apiClient.delete('${ApiConstants.expenses}$expenseId');
    return res is Map<String, dynamic> && res['deleted'] == true;
  }

  Future<ExpenseModel> getExpense(String expenseId) async {
    final res = await apiClient.get('${ApiConstants.expenses}$expenseId');
    return ExpenseModel.fromJson(res as Map<String, dynamic>);
  }

  Future<List<ExpenseModel>> listGroupExpenses(String groupId) async {
    final res = await apiClient.get('${ApiConstants.expenses}group/$groupId');
    final list = res as List<dynamic>? ?? [];
    return list.map((e) => ExpenseModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<ExpenseModel>> listPersonalExpenses() async {
    final res = await apiClient.get('${ApiConstants.expenses}personal');
    final list = res as List<dynamic>? ?? [];
    return list.map((e) => ExpenseModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> get1on1Balance(String friendId, {String currency = 'USD'}) async {
    final res = await apiClient.get(
      '${ApiConstants.expenses}balances/1on1',
      queryParameters: {
        'friend_id': friendId,
        'currency': currency.toUpperCase(),
      },
    );
    return res as Map<String, dynamic>;
  }
}
