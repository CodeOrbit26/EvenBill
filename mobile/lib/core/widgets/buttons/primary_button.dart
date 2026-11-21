import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final bool isFullWidth;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.isFullWidth = true,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBg = isDark ? AppColors.mintAccent : AppColors.forestGreen;
    final defaultFg = isDark ? AppColors.darkBackground : Colors.white;

    final child = Row(
      mainAxisSize: isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(foregroundColor ?? defaultFg),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ] else if (icon != null) ...[
          Icon(icon, size: 18, color: foregroundColor ?? defaultFg),
          const SizedBox(width: AppSpacing.xs),
        ],
        Text(
          label,
          style: AppTypography.labelLarge(isDark).copyWith(
            color: foregroundColor ?? defaultFg,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

    final button = ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? defaultBg,
        foregroundColor: foregroundColor ?? defaultFg,
        disabledBackgroundColor: (backgroundColor ?? defaultBg).withOpacity(0.4),
        disabledForegroundColor: (foregroundColor ?? defaultFg).withOpacity(0.5),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.roundedMd),
        padding: AppSpacing.buttonPadding,
      ),
      onPressed: isLoading ? null : onPressed,
      child: child,
    );

    return isFullWidth ? SizedBox(width: double.infinity, child: button) : button;
  }
}
