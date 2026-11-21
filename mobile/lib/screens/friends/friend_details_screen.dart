import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/avatars/user_avatar.dart';
import '../../core/widgets/financial/amount_display.dart';
import '../../core/widgets/financial/expense_row.dart';
import '../../core/widgets/buttons/primary_button.dart';
import '../../core/di/injection.dart';
import '../../core/models/friend_model.dart';
import '../../core/models/expense_model.dart';

class FriendDetailsScreen extends StatefulWidget {
  final FriendModel friend;
  final VoidCallback onSettleUp;
  final Function(ExpenseModel) onExpenseTap;
  final VoidCallback onBack;

  const FriendDetailsScreen({
    super.key,
    required this.friend,
    required this.onSettleUp,
    required this.onExpenseTap,
    required this.onBack,
  });

  @override
  State<FriendDetailsScreen> createState() => _FriendDetailsScreenState();
}

class _FriendDetailsScreenState extends State<FriendDetailsScreen> {
  bool _isLoading = true;
  double _currentNetBalance = 0.0;
  List<ExpenseModel> _sharedExpenses = [];

  @override
  void initState() {
    super.initState();
    _currentNetBalance = widget.friend.netBalance;
    _loadFriendHistory();
  }

  Future<void> _loadFriendHistory() async {
    setState(() => _isLoading = true);
    try {
      final balanceFuture = Injection.expenseRepository.get1on1Balance(widget.friend.id);
      final expensesFuture = Injection.expenseRepository.listPersonalExpenses();

      final results = await Future.wait([balanceFuture, expensesFuture]);
      final balanceMap = results[0] as Map<String, dynamic>;
      final personalExpenses = results[1] as List<ExpenseModel>;

      if (mounted) {
        setState(() {
          _currentNetBalance = double.tryParse(balanceMap['net_balance']?.toString() ?? '0') ?? widget.friend.netBalance;
          _sharedExpenses = personalExpenses.where((exp) {
            return exp.payers.any((p) => p.userId == widget.friend.id) ||
                exp.splits.any((s) => s.userId == widget.friend.id);
          }).toList();
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOwed = _currentNetBalance > 0.001;
    final isOwes = _currentNetBalance < -0.001;
    final isSettled = !isOwed && !isOwes;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: Text(widget.friend.name),
      ),
      body: RefreshIndicator(
        onRefresh: _loadFriendHistory,
        color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
        child: ListView(
          padding: AppSpacing.screenPadding,
          children: [
            // Friend Balance Profile Card
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  UserAvatar(name: widget.friend.name, size: 68),
                  const SizedBox(height: AppSpacing.sm + 2),
                  Text(
                    widget.friend.name,
                    style: AppTypography.titleLarge(isDark).copyWith(fontWeight: FontWeight.w800, fontSize: 20),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.friend.email,
                    style: AppTypography.bodyMedium(isDark).copyWith(
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Divider(height: 1),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isSettled
                          ? Colors.grey.withOpacity(0.12)
                          : (isOwed
                              ? (isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen).withOpacity(0.12)
                              : (isDark ? AppColors.negativeRedDark : AppColors.negativeRed).withOpacity(0.12)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isSettled
                          ? '✓ All Settled Up'
                          : (isOwed ? '${widget.friend.name} owes you' : 'You owe ${widget.friend.name}'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSettled
                            ? Colors.grey
                            : (isOwed
                                ? (isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen)
                                : (isDark ? AppColors.negativeRedDark : AppColors.negativeRed)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  AmountDisplay(
                    amount: _currentNetBalance.abs(),
                    currency: widget.friend.currency,
                    isLarge: true,
                    overrideColor: isSettled
                        ? Colors.grey
                        : (isOwed
                            ? (isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen)
                            : (isDark ? AppColors.negativeRedDark : AppColors.negativeRed)),
                  ),
                  if (!isSettled) ...[
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      label: 'Settle Up with ${widget.friend.name.split(' ')[0]}',
                      icon: Icons.handshake_outlined,
                      onPressed: widget.onSettleUp,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Shared Expenses History (${_sharedExpenses.length})', style: AppTypography.labelLarge(isDark)),
                if (_isLoading)
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),

            if (_sharedExpenses.isEmpty && !_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36.0),
                child: Center(
                  child: Text(
                    'No direct expenses logged with this friend yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            else
              ..._sharedExpenses.map(
                (exp) => ExpenseRow(
                  description: exp.description,
                  category: exp.category,
                  groupName: 'Direct Expense',
                  dateFormatted: exp.dateFormatted,
                  payerText: exp.paidBy,
                  netShare: exp.yourNetShare,
                  currency: exp.currency,
                  onTap: () => widget.onExpenseTap(exp),
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
