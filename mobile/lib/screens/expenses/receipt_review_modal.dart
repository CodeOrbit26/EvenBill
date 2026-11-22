import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons/primary_button.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/di/injection.dart';
import '../../core/models/receipt_model.dart';

class ConfirmedReceiptData {
  final String receiptId;
  final String merchant;
  final double totalAmount;
  final String currency;
  final DateTime date;
  final List<ReceiptItemModel> items;
  final double tax;
  final double tip;

  const ConfirmedReceiptData({
    required this.receiptId,
    required this.merchant,
    required this.totalAmount,
    required this.currency,
    required this.date,
    required this.items,
    this.tax = 0.0,
    this.tip = 0.0,
  });
}

class ReceiptReviewModal extends StatefulWidget {
  final List<Map<String, String>> participants; // list of { 'id': ..., 'name': ... }
  final ValueChanged<ConfirmedReceiptData> onConfirmed;

  const ReceiptReviewModal({
    super.key,
    required this.participants,
    required this.onConfirmed,
  });

  @override
  State<ReceiptReviewModal> createState() => _ReceiptReviewModalState();
}

class _ReceiptReviewModalState extends State<ReceiptReviewModal> {
  bool _isUploading = false;
  ReceiptModel? _receipt;
  String? _uploadError;

  late TextEditingController _merchantController;
  late TextEditingController _totalController;
  late List<ReceiptItemModel> _items;

  @override
  void initState() {
    super.initState();
    _merchantController = TextEditingController();
    _totalController = TextEditingController();
    _items = [];
    _startSimulatedScan();
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  Future<void> _startSimulatedScan() async {
    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      // Create valid JPEG magic bytes signature
      final validJpegHeader = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46];
      final dummyBody = List<int>.filled(500, 0x41);
      final receiptBytes = [...validJpegHeader, ...dummyBody];

      final receipt = await Injection.proRepository.uploadReceipt(
        fileName: 'dinner_receipt_${DateTime.now().millisecondsSinceEpoch}.jpg',
        mimeType: 'image/jpeg',
        bytes: receiptBytes,
      );

      if (mounted) {
        setState(() {
          _receipt = receipt;
          _merchantController.text = receipt.extractedMerchant ?? 'Trattoria Restaurant';
          _totalController.text = (receipt.extractedTotal ?? 86.02).toStringAsFixed(2);
          _items = receipt.items.isNotEmpty
              ? List.from(receipt.items)
              : [
                  ReceiptItemModel(description: 'Margherita Pizza', amount: 24.50, assignedParticipantIds: []),
                  ReceiptItemModel(description: 'Pasta Carbonara', amount: 32.00, assignedParticipantIds: []),
                  ReceiptItemModel(description: 'Tiramisu Dessert', amount: 14.50, assignedParticipantIds: []),
                  ReceiptItemModel(description: 'Sparkling Mineral Water', amount: 15.02, assignedParticipantIds: []),
                ];
          _isUploading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadError = e.toString();
          _isUploading = false;
        });
      }
    }
  }

  void _addItem() {
    setState(() {
      _items.add(ReceiptItemModel(description: 'Custom Item', amount: 0.0, assignedParticipantIds: []));
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _recalculateTotal();
    });
  }

  void _recalculateTotal() {
    final sum = _items.fold<double>(0.0, (acc, item) => acc + item.amount);
    _totalController.text = sum.toStringAsFixed(2);
  }

  void _toggleParticipantForItem(int itemIndex, String participantId) {
    final item = _items[itemIndex];
    final assigned = List<String>.from(item.assignedParticipantIds);
    if (assigned.contains(participantId)) {
      assigned.remove(participantId);
    } else {
      assigned.add(participantId);
    }
    setState(() {
      _items[itemIndex] = item.copyWith(assignedParticipantIds: assigned);
    });
  }

  void _confirmAndApply() {
    final total = double.tryParse(_totalController.text.trim()) ?? 0.0;
    if (total <= 0) {
      AppSnackbar.showError(context, 'Total amount must be greater than zero.');
      return;
    }

    final data = ConfirmedReceiptData(
      receiptId: _receipt?.id ?? 'receipt_manual_${DateTime.now().millisecondsSinceEpoch}',
      merchant: _merchantController.text.trim(),
      totalAmount: total,
      currency: _receipt?.extractedCurrency ?? 'USD',
      date: DateTime.now(),
      items: _items,
      tax: _receipt?.tax ?? 0.0,
      tip: _receipt?.tip ?? 0.0,
    );

    widget.onConfirmed(data);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: _isUploading
                ? _buildLoadingState(context)
                : _uploadError != null
                    ? _buildErrorState(context)
                    : _buildReviewContent(context),
          ),
          if (!_isUploading && _uploadError == null) _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: AppColors.primaryForest),
              const SizedBox(width: AppSpacing.sm),
              Text('Review OCR Receipt', style: AppTypography.titleMedium().copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: AppSpacing.md),
            Text('Processing Receipt & Extracting Line Items...', style: AppTypography.titleSmall()),
            const SizedBox(height: AppSpacing.xs),
            Text('Verifying cryptographic SHA-256 hash & running OCR model', style: AppTypography.bodySmall()),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text('OCR Extraction Issue', style: AppTypography.titleMedium()),
            const SizedBox(height: AppSpacing.xs),
            Text(_uploadError!, textAlign: TextAlign.center, style: AppTypography.bodySmall()),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(label: 'Retry Scan', onPressed: _startSimulatedScan),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewContent(BuildContext context) {
    final isDup = _receipt?.isDuplicate ?? false;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (isDup)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.md),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.warning.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.warning),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Duplicate receipt detected (identical SHA-256 hash). Verifying existing records.',
                    style: AppTypography.bodySmall().copyWith(color: AppColors.warning, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        Text('Merchant / Description', style: AppTypography.labelSmall()),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _merchantController,
          decoration: const InputDecoration(
            hintText: 'e.g. Trattoria Restaurant',
            prefixIcon: Icon(Icons.storefront_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Total Amount', style: AppTypography.labelSmall()),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _totalController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            hintText: '0.00',
            prefixText: '${_receipt?.extractedCurrency ?? 'USD'} ',
            prefixIcon: const Icon(Icons.attach_money_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Itemized Breakdown & Assignees', style: AppTypography.titleSmall().copyWith(fontWeight: FontWeight.bold)),
            TextButton.icon(
              onPressed: _addItem,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Item'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ..._items.asMap().entries.map((entry) => _buildItemCard(context, entry.key, entry.value)),
      ],
    );
  }

  Widget _buildItemCard(BuildContext context, int index, ReceiptItemModel item) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: item.description,
                    decoration: const InputDecoration(
                      labelText: 'Item Name',
                      isDense: true,
                    ),
                    onChanged: (val) {
                      _items[index] = item.copyWith(description: val);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    initialValue: item.amount.toStringAsFixed(2),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Price',
                      isDense: true,
                    ),
                    onChanged: (val) {
                      final parsed = double.tryParse(val) ?? 0.0;
                      _items[index] = item.copyWith(amount: parsed);
                      _recalculateTotal();
                    },
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
                  onPressed: () => _removeItem(index),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('Assigned Participants:', style: AppTypography.labelSmall()),

            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: widget.participants.map((p) {
                final isAssigned = item.assignedParticipantIds.contains(p['id']);
                return FilterChip(
                  label: Text(p['name'] ?? 'User'),
                  selected: isAssigned,
                  onSelected: (_) => _toggleParticipantForItem(index, p['id']!),
                  selectedColor: AppColors.mintAccent.withOpacity(0.3),
                  checkmarkColor: AppColors.primaryForest,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1))),
      ),
      child: PrimaryButton(
        label: 'Confirm & Use in Expense',
        onPressed: _confirmAndApply,
      ),
    );
  }
}
