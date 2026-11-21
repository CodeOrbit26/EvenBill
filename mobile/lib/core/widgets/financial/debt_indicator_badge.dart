import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import 'amount_display.dart';

class DebtIndicatorBadge extends StatelessWidget {
  final double netAmount;
  final String currency;

  const DebtIndicatorBadge({
    super.key,
    required this.netAmount,
    this.currency = 'USD',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (netAmount.abs() < 0.001) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: (isDark ? AppColors.darkCard : AppColors.lightCardSubtle),
          borderRadius: AppRadius.roundedPill,
        ),
        child: Text(
          'settled up',
          style: TextStyle(
            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final isOwed = netAmount > 0;
    final color = isOwed
        ? (isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen)
        : (isDark ? AppColors.negativeRedDark : AppColors.negativeRed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          isOwed ? 'you are owed' : 'you owe',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(height: 1),
        AmountDisplay(
          amount: netAmount.abs(),
          currency: currency,
          overrideColor: color,
        ),
      ],
    );
  }
}
