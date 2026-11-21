import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

class OfflineBanner extends StatelessWidget {
  final int pendingSyncCount;
  final VoidCallback? onSyncTap;

  const OfflineBanner({
    super.key,
    this.pendingSyncCount = 0,
    this.onSyncTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.warningAmber.withOpacity(0.15),
        border: const Border(
          bottom: BorderSide(color: AppColors.warningAmber, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, size: 16, color: AppColors.warningAmber),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              pendingSyncCount > 0
                  ? 'Offline Mode — $pendingSyncCount changes queued for sync'
                  : 'Offline Mode — Showing locally cached balances',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.warningAmber,
              ),
            ),
          ),
          if (onSyncTap != null)
            GestureDetector(
              onTap: onSyncTap,
              child: const Text(
                'Retry',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  color: AppColors.warningAmber,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
