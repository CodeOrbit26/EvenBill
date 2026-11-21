import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../financial/amount_display.dart';

class CurrencyAmountField extends StatelessWidget {
  final TextEditingController controller;
  final String currency;
  final VoidCallback? onCurrencyTap;
  final ValueChanged<String>? onChanged;

  const CurrencyAmountField({
    super.key,
    required this.controller,
    this.currency = 'USD',
    this.onCurrencyTap,
    this.onChanged,
  });

  String _getCurrencySymbol(String code) => AmountDisplay.getCurrencySymbol(code);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final symbol = _getCurrencySymbol(currency);
    final flag = AmountDisplay.getCurrencyFlag(currency);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        borderRadius: AppRadius.roundedLg,
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          // Currency Selector Pill
          InkWell(
            onTap: onCurrencyTap,
            borderRadius: AppRadius.roundedPill,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCardSubtle,
                borderRadius: AppRadius.roundedPill,
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(flag, style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(
                    symbol,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    currency,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // Large Amount Input
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              style: AppTypography.numericLarge(
                isDark,
                color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
              ),
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: AppTypography.numericLarge(
                  isDark,
                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
