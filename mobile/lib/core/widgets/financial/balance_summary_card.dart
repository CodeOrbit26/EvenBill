import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'amount_display.dart';

class BalanceSummaryCard extends StatelessWidget {
  final double totalNetBalance;
  final double youAreOwed;
  final double youOwe;
  final String currency;
  final VoidCallback onSettleUp;
  final VoidCallback onScanReceipt;
  final VoidCallback? onCurrencyTap;

  const BalanceSummaryCard({
    super.key,
    required this.totalNetBalance,
    required this.youAreOwed,
    required this.youOwe,
    this.currency = 'USD',
    required this.onSettleUp,
    required this.onScanReceipt,
    this.onCurrencyTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOwed = totalNetBalance > 0;
    final isSettled = totalNetBalance.abs() < 0.001;

    final headerText = isSettled
        ? 'You are all settled up'
        : (isOwed ? 'Overall, you are owed' : 'Overall, you owe');

    final heroColor = isSettled
        ? (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)
        : (isOwed
            ? (isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen)
            : (isDark ? AppColors.negativeRedDark : AppColors.negativeRed));

    final totalActivity = youAreOwed + youOwe;
    final owedRatio = totalActivity > 0 ? (youAreOwed / totalActivity).clamp(0.05, 0.95) : 0.5;

    return Card(
      elevation: isDark ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Header Row with Currency Selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    headerText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.labelLarge(isDark).copyWith(
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onCurrencyTap != null)
                  InkWell(
                    onTap: onCurrencyTap,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCardSubtle : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AmountDisplay.getCurrencyFlag(currency),
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            currency,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 14,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Hero Amount Display
            AmountDisplay(
              amount: totalNetBalance,
              currency: currency,
              showSign: !isSettled,
              isLarge: true,
              overrideColor: heroColor,
            ),
            if (!isSettled && totalActivity > 0) ...[
              const SizedBox(height: 10),
              // Proportional health bar
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  height: 4,
                  child: Row(
                    children: [
                      if (youAreOwed > 0)
                        Expanded(
                          flex: (owedRatio * 100).toInt(),
                          child: Container(
                            color: isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen,
                          ),
                        ),
                      if (youOwe > 0)
                        Expanded(
                          flex: ((1 - owedRatio) * 100).toInt(),
                          child: Container(
                            color: isDark ? AppColors.negativeRedDark : AppColors.negativeRed,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            // Breakdown row: Owed vs Owe Dual Cards
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.positiveGreenDark.withOpacity(0.12)
                          : AppColors.positiveGreen.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen).withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.arrow_upward_rounded,
                              size: 13,
                              color: isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'You are owed',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        AmountDisplay(
                          amount: youAreOwed,
                          currency: currency,
                          overrideColor: isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.negativeRedDark.withOpacity(0.12)
                          : AppColors.negativeRed.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (isDark ? AppColors.negativeRedDark : AppColors.negativeRed).withOpacity(0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.arrow_downward_rounded,
                              size: 13,
                              color: isDark ? AppColors.negativeRedDark : AppColors.negativeRed,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'You owe',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        AmountDisplay(
                          amount: youOwe,
                          currency: currency,
                          overrideColor: isDark ? AppColors.negativeRedDark : AppColors.negativeRed,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            // Settle up & Scan CTA row
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                        color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: Icon(
                      Icons.handshake_outlined,
                      size: 18,
                      color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                    ),
                    label: Text(
                      'Settle Up',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                      ),
                    ),
                    onPressed: onSettleUp,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                      foregroundColor: isDark ? AppColors.darkBackground : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Scan & Pay', style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: onScanReceipt,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
