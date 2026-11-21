import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isFullWidth;
  final bool isSubtle;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isFullWidth = true,
    this.isSubtle = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? AppColors.mintAccent : AppColors.forestGreen;

    final child = Row(
      mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.xs),
        ],
        Text(
          label,
          style: AppTypography.labelLarge(isDark).copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    final button = isSubtle
        ? TextButton(
            style: TextButton.styleFrom(
              padding: AppSpacing.buttonPadding,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.roundedMd),
            ),
            onPressed: onPressed,
            child: child,
          )
        : OutlinedButton(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: color, width: 1.4),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.roundedMd),
              padding: AppSpacing.buttonPadding,
            ),
            onPressed: onPressed,
            child: child,
          );

    return isFullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
