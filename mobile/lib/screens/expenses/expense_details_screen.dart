import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/avatars/user_avatar.dart';
import '../../core/widgets/financial/category_icon.dart';
import '../../core/widgets/financial/amount_display.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/di/injection.dart';
import '../../core/models/expense_model.dart';

class ExpenseDetailsScreen extends StatelessWidget {
  final ExpenseModel expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onBack;

  const ExpenseDetailsScreen({
    super.key,
    required this.expense,
    required this.onEdit,
    required this.onDelete,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBack,
        ),
        title: const Text('Expense Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Expense',
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Delete Expense',
            onPressed: () => _showDeleteDialog(context),
          ),
        ],
      ),
      body: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          // Header Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  CategoryIcon(category: expense.category, size: 56),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    expense.description,
                    textAlign: TextAlign.center,
                    style: AppTypography.displayMedium(isDark),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${expense.groupName} • ${expense.dateFormatted}',
                    style: AppTypography.bodyMedium(isDark),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AmountDisplay(
                    amount: expense.totalAmount,
                    currency: expense.currency,
                    isLarge: true,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    expense.paidBy,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Payer & Split Breakdown Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Split Breakdown (${expense.splitType})',
                          style: AppTypography.labelLarge(isDark),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${expense.splits.length} participants',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.sm),
                  const Divider(),
                  const SizedBox(height: AppSpacing.sm),

                  if (expense.splits.isEmpty)
                    const Text('Equal split between group members.')
                  else
                    ...expense.splits.map((split) {
                      final isPayer = expense.payers.any((p) => p.userId == split.userId);
                      final payerRecord = expense.payers.where((p) => p.userId == split.userId).toList();
                      final paidAmount = payerRecord.isNotEmpty ? payerRecord.first.amountPaid : 0.0;

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Row(
                          children: [
                            UserAvatar(name: split.fullName, size: 36),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    split.fullName,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  if (isPayer && paidAmount > 0)
                                    Text(
                                      'Paid ${expense.currency} ${paidAmount.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'owes',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                                  ),
                                ),
                                AmountDisplay(
                                  amount: split.owedAmount,
                                  currency: expense.currency,
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Notes Card
          if (expense.notes != null && expense.notes!.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Notes', style: AppTypography.labelLarge(isDark)),
                    const SizedBox(height: 6),
                    Text(expense.notes!, style: AppTypography.bodyMedium(isDark)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Audit & Immutable History Card
          Card(
            color: isDark ? AppColors.darkCard : AppColors.lightCardSubtle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined, size: 20, color: AppColors.positiveGreen),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Recorded in immutable financial ledger • Version ${expense.version} • Created ${expense.createdAt.toIso8601String().substring(0, 10)}',
                      style: AppTypography.labelSmall(isDark).copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Expense?'),
        content: const Text(
          'This will remove the transaction and automatically recalculate group ledger balances for all members.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.negativeRed),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Injection.expenseRepository.deleteExpense(expense.id);
                if (context.mounted) {
                  AppSnackbar.showSuccess(context, 'Expense deleted and balances updated');
                  onDelete();
                }
              } catch (e) {
                if (context.mounted) {
                  AppSnackbar.showError(context, 'Failed to delete expense: $e');
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
