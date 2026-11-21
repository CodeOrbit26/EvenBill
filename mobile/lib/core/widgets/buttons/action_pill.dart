import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class ActionPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? activeColor;

  const ActionPill({
    super.key,
    required this.label,
    this.icon,
    this.isSelected = false,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryAccent = activeColor ?? (isDark ? AppColors.mintAccent : AppColors.forestGreen);

    final bg = isSelected
        ? primaryAccent.withOpacity(isDark ? 0.25 : 0.15)
        : (isDark ? AppColors.darkCard : AppColors.lightCardSubtle);

    final border = isSelected
        ? primaryAccent
        : (isDark ? AppColors.darkBorder : AppColors.lightBorder);

    final textCol = isSelected
        ? primaryAccent
        : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary);

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.roundedPill,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: AppRadius.roundedPill,
          border: Border.all(color: border, width: isSelected ? 1.5 : 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: textCol),
              const SizedBox(width: AppSpacing.xxs),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: AppTypography.labelSmall(isDark).copyWith(
                  color: textCol,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}
