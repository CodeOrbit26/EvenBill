import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'category_icon.dart';
import 'amount_display.dart';

class ExpenseRow extends StatelessWidget {
  final String description;
  final String category;
  final String groupName;
  final String dateFormatted;
  final String payerText;
  final double netShare;
  final String currency;
  final double? totalAmount;
  final double? userPaidAmount;
  final double? userOwedAmount;
  final bool? isUserInvolved;
  final VoidCallback onTap;

  const ExpenseRow({
    super.key,
    required this.description,
    required this.category,
    required this.groupName,
    required this.dateFormatted,
    required this.payerText,
    required this.netShare,
    this.currency = 'USD',
    this.totalAmount,
    this.userPaidAmount,
    this.userOwedAmount,
    this.isUserInvolved,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLent = netShare > 0.001;
    final isBorrowed = netShare < -0.001;
    final involved = isUserInvolved ??
        (isLent ||
            isBorrowed ||
            (userPaidAmount ?? 0).abs() >= 0.001 ||
            (userOwedAmount ?? 0).abs() >= 0.001);
    final isNotInvolved = !isLent && !isBorrowed && !involved;
    final isSoloPersonal = !isLent &&
        !isBorrowed &&
        involved &&
        totalAmount != null &&
        totalAmount! > 0.001 &&
        ((userPaidAmount ?? 0) - totalAmount!).abs() < 0.01 &&
        ((userOwedAmount ?? 0) - totalAmount!).abs() < 0.01;

    final double? neutralAmount = isSoloPersonal
        ? totalAmount
        : ((userPaidAmount ?? 0) > 0.001
            ? userPaidAmount
            : ((userOwedAmount ?? 0) > 0.001
                ? userOwedAmount
                : totalAmount));
    final hasZeroNetInvolvedAmount = !isLent && !isBorrowed && involved;
    final neutralColor = isDark ? AppColors.mintAccent : AppColors.forestGreen;

    final shareColor = isLent
        ? (isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen)
        : (isBorrowed
            ? (isDark ? AppColors.negativeRedDark : AppColors.negativeRed)
            : (involved
                ? neutralColor
                : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)));

    final shareLabel = isLent
        ? 'you lent'
        : (isBorrowed
            ? 'you borrowed'
            : (isSoloPersonal
                ? 'personal'
                : (involved ? 'even share' : 'no balance')));

    final showTotalSubcaption = totalAmount != null &&
        totalAmount! > 0.001 &&
        (isNotInvolved ||
            ((isLent || isBorrowed) &&
                (totalAmount! - netShare.abs()).abs() >= 0.01) ||
            (hasZeroNetInvolvedAmount &&
                !isSoloPersonal &&
                neutralAmount != null &&
                (totalAmount! - neutralAmount).abs() >= 0.01));

    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CategoryIcon(category: category, size: 44),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.titleMedium(isDark),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$groupName • $dateFormatted',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium(isDark).copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      payerText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelSmall(isDark).copyWith(
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: shareColor.withOpacity(isDark ? 0.18 : 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      shareLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: shareColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (isNotInvolved)
                    Text(
                      'not involved',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    )
                  else if (hasZeroNetInvolvedAmount)
                    if (neutralAmount != null && neutralAmount > 0.001)
                      AmountDisplay(
                        amount: neutralAmount,
                        currency: currency,
                        overrideColor: shareColor,
                      )
                    else
                      Text(
                        'settled',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: shareColor,
                        ),
                      )
                  else
                    AmountDisplay(
                      amount: netShare.abs(),
                      currency: currency,
                      overrideColor: shareColor,
                    ),
                  if (showTotalSubcaption) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Total ${AmountDisplay.format(totalAmount!, currency)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
