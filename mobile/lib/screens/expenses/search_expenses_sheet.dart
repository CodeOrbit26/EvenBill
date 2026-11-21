import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons/primary_button.dart';
import '../../core/di/injection.dart';
import '../../core/models/expense_model.dart';
import 'expense_details_screen.dart';

class SearchExpensesSheet extends StatefulWidget {
  final VoidCallback onBack;

  const SearchExpensesSheet({
    super.key,
    required this.onBack,
  });

  @override
  State<SearchExpensesSheet> createState() => _SearchExpensesSheetState();
}

class _SearchExpensesSheetState extends State<SearchExpensesSheet> {
  final TextEditingController _queryController = TextEditingController();
  final TextEditingController _minAmountController = TextEditingController();
  final TextEditingController _maxAmountController = TextEditingController();

  String? _selectedCategory;
  bool _onlyWithReceipts = false;
  bool _isSearching = false;
  List<ExpenseModel> _results = [];
  bool _hasSearched = false;

  final List<String> _categories = [
    'ALL',
    'GROCERIES',
    'DINING OUT',
    'UTILITIES',
    'TRANSPORTATION',
    'ENTERTAINMENT',
    'GENERAL',
  ];

  @override
  void dispose() {
    _queryController.dispose();
    _minAmountController.dispose();
    _maxAmountController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    setState(() {
      _isSearching = true;
      _hasSearched = true;
    });

    try {
      final minAmt = double.tryParse(_minAmountController.text.trim());
      final maxAmt = double.tryParse(_maxAmountController.text.trim());
      final cat = (_selectedCategory == null || _selectedCategory == 'ALL')
          ? null
          : _selectedCategory;

      final expenses = await Injection.proRepository.searchExpenses(
        query: _queryController.text.trim().isEmpty ? null : _queryController.text.trim(),
        category: cat,
        minAmount: minAmt,
        maxAmount: maxAmt,
        hasReceipt: _onlyWithReceipts ? true : null,
      );

      if (mounted) {
        setState(() {
          _results = expenses;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search & Filter Expenses'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: widget.onBack,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchControls(context),
            const Divider(height: 1),
            Expanded(
              child: _isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : !_hasSearched
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_rounded, size: 64, color: Theme.of(context).disabledColor),
                              const SizedBox(height: AppSpacing.sm),
                              Text('Search across all past expenses', style: AppTypography.titleSmall()),
                              const SizedBox(height: AppSpacing.xs),
                              Text('Filter by merchant, notes, category, amount, or attached receipts',
                                  style: AppTypography.bodySmall()),
                            ],
                          ),
                        )
                      : _results.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.search_off_rounded, size: 48, color: Theme.of(context).disabledColor),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text('No matching expenses found', style: AppTypography.titleSmall()),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text('Try relaxing search keywords or amount filters', style: AppTypography.bodySmall()),
                                ],
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              itemCount: _results.length,
                              separatorBuilder: (context, _) => const SizedBox(height: AppSpacing.xs),
                              itemBuilder: (context, index) {
                                final exp = _results[index];
                                return Card(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.primaryForest.withOpacity(0.1),
                                      child: Icon(
                                        exp.hasReceipt ? Icons.receipt_long_rounded : Icons.shopping_bag_outlined,
                                        color: AppColors.primaryForest,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(exp.description, style: AppTypography.bodyMedium().copyWith(fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                      '${exp.category} • ${exp.dateFormatted}',
                                      style: AppTypography.bodySmall(),
                                    ),
                                    trailing: Text(
                                      '${exp.currency} ${exp.totalAmount.toStringAsFixed(2)}',
                                      style: AppTypography.bodyMedium().copyWith(fontWeight: FontWeight.bold),
                                    ),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => ExpenseDetailsScreen(
                                            expense: exp,
                                            onEdit: () {},
                                            onDelete: () {},
                                            onBack: () => Navigator.of(context).pop(),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchControls(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _queryController,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _performSearch(),
            decoration: InputDecoration(
              hintText: 'Search description or notes...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: _performSearch,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _categories.map((cat) {
                final isSelected = (_selectedCategory == cat) || (_selectedCategory == null && cat == 'ALL');
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(cat),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedCategory = cat == 'ALL' ? null : cat;
                      });
                      _performSearch();
                    },
                    selectedColor: AppColors.mintAccent.withOpacity(0.3),
                    checkmarkColor: AppColors.primaryForest,
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _minAmountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Min Amount',
                    isDense: true,
                    prefixIcon: Icon(Icons.remove_rounded, size: 16),
                  ),
                  onSubmitted: (_) => _performSearch(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _maxAmountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Max Amount',
                    isDense: true,
                    prefixIcon: Icon(Icons.add_rounded, size: 16),
                  ),
                  onSubmitted: (_) => _performSearch(),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilterChip(
                label: const Text('Receipt'),
                avatar: const Icon(Icons.receipt_rounded, size: 14),
                selected: _onlyWithReceipts,
                onSelected: (selected) {
                  setState(() => _onlyWithReceipts = selected);
                  _performSearch();
                },
                selectedColor: AppColors.mintAccent.withOpacity(0.3),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
