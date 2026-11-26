import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

class AmountDisplay extends StatelessWidget {
  final double amount;
  final String currency;
  final bool showSign;
  final bool isLarge;
  final Color? overrideColor;

  const AmountDisplay({
    super.key,
    required this.amount,
    this.currency = 'USD',
    this.showSign = false,
    this.isLarge = false,
    this.overrideColor,
  });

  static String format(double amount, String currency, {bool showSign = false}) {
    final formatter = NumberFormat.currency(
      symbol: getCurrencySymbol(currency),
      decimalDigits: 2,
    );
    final formatted = formatter.format(amount.abs());
    if (showSign) {
      if (amount > 0) return '+$formatted';
      if (amount < 0) return '-$formatted';
    }
    return amount < 0 ? '-$formatted' : formatted;
  }

  String _formatAmount() => format(amount, currency, showSign: showSign);

  static String getCurrencySymbol(String code) {
    switch (code.toUpperCase()) {
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'INR':
        return '₹';
      case 'JPY':
        return '¥';
      case 'CAD':
        return 'C\$';
      case 'AUD':
        return 'A\$';
      case 'AED':
        return 'AED ';
      case 'SGD':
        return 'S\$';
      case 'CHF':
        return 'CHF ';
      case 'USD':
      default:
        return '\$';
    }
  }

  static String getCurrencyFlag(String code) {
    switch (code.toUpperCase()) {
      case 'INR':
        return '🇮🇳';
      case 'EUR':
        return '🇪🇺';
      case 'GBP':
        return '🇬🇧';
      case 'JPY':
        return '🇯🇵';
      case 'CAD':
        return '🇨🇦';
      case 'AUD':
        return '🇦🇺';
      case 'AED':
        return '🇦🇪';
      case 'SGD':
        return '🇸🇬';
      case 'CHF':
        return '🇨🇭';
      case 'USD':
      default:
        return '🇺🇸';
    }
  }

  Color _resolveColor(bool isDark) {
    if (overrideColor != null) return overrideColor!;
    if (amount > 0) return isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen;
    if (amount < 0) return isDark ? AppColors.negativeRedDark : AppColors.negativeRed;
    return isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _resolveColor(isDark);
    final formatted = _formatAmount();

    return Text(
      formatted,
      style: isLarge
          ? AppTypography.numericLarge(isDark, color: color)
          : AppTypography.numericMedium(isDark, color: color),
    );
  }
}
