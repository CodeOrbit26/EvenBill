import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons/primary_button.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/di/injection.dart';

class ProPaywallScreen extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback? onUpgradeSuccess;

  const ProPaywallScreen({
    super.key,
    required this.onBack,
    this.onUpgradeSuccess,
  });

  @override
  State<ProPaywallScreen> createState() => _ProPaywallScreenState();
}

class _ProPaywallScreenState extends State<ProPaywallScreen> {
  bool _isAnnual = true;
  bool _isUpgrading = false;

  final List<Map<String, dynamic>> _features = [
    {
      'title': 'Unlimited Daily Expenses',
      'subtitle': 'Create unlimited new expenses every day across all your groups and friendships. (Free tier reference limit: 4 / day).',
      'icon': Icons.all_inclusive_rounded,
    },
    {
      'title': 'Unlimited AI Receipt Itemization',
      'subtitle': 'Scan paper receipts and automatically assign line items to individual diners with proportional tax and tip.',
      'icon': Icons.document_scanner_rounded,
    },
    {
      'title': 'Cross-Group Global Debt Simplification',
      'subtitle': 'Optimize settlements globally across all shared groups and 1-on-1 friendships in one aggregated transfer.',
      'icon': Icons.auto_graph_rounded,
    },
    {
      'title': 'Live Real-Time FX Rate Locking',
      'subtitle': 'Lock live institutional exchange rates at the exact minute of purchase to avoid future volatility discrepancies.',
      'icon': Icons.currency_exchange_rounded,
    },
    {
      'title': '5 GB Encrypted HD Receipt Vault',
      'subtitle': 'Store original high-resolution receipt photos and tax invoices with instant encrypted cloud recovery.',
      'icon': Icons.cloud_done_rounded,
    },
    {
      'title': 'Advanced Spending Trends & Budget Alarms',
      'subtitle': 'Custom date filters, spending velocity projections, and itemized PDF/CSV tax-compliant audit exports.',
      'icon': Icons.insights_rounded,
    },
  ];

  Future<void> _handleUpgrade() async {
    setState(() => _isUpgrading = true);
    try {
      final tier = _isAnnual ? 'PRO_ANNUAL' : 'PRO_MONTHLY';
      await Injection.subscriptionRepository.mockUpgrade(tier: tier);
      
      // Refresh current user cache
      try {
        await Injection.authRepository.getMe();
      } catch (_) {}

      if (mounted) {
        AppSnackbar.showSuccess(context, 'EvenBill Pro activated! Unlimited expenses unlocked.');
        widget.onUpgradeSuccess?.call();
        widget.onBack();
      }
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, 'Upgrade failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isUpgrading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('EvenBill Pro'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: widget.onBack,
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.screenPadding,
          child: Column(
            children: [
              // Pro Badge & Header
              Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: AppColors.mintAccent,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.star_rounded, color: AppColors.forestGreen, size: 36),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Unlock Unlimited Power',
                style: AppTypography.displayMedium(isDark),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Financial precision and automated intelligence for discerning groups.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium(isDark),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Annual vs Monthly Billing Selector
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCardSubtle,
                  borderRadius: AppRadius.roundedPill,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isAnnual = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _isAnnual
                                ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                                : Colors.transparent,
                            borderRadius: AppRadius.roundedPill,
                          ),
                          alignment: Alignment.center,
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 4,
                            children: [
                              Text(
                                'Annual (\$39.99/yr)',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                    color: _isAnnual
                                        ? (isDark ? AppColors.darkBackground : Colors.white)
                                        : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.positiveGreen,
                                  borderRadius: AppRadius.roundedPill,
                                ),
                                child: const Text(
                                  'SAVE 33%',
                                  style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _isAnnual = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: !_isAnnual
                                ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                                : Colors.transparent,
                            borderRadius: AppRadius.roundedPill,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'Monthly (\$4.99/mo)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: !_isAnnual
                                  ? (isDark ? AppColors.darkBackground : Colors.white)
                                  : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Feature Cards
              ..._features.map(
                (f) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(f['icon'] as IconData, size: 20, color: isDark ? AppColors.mintAccent : AppColors.forestGreen),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f['title'] as String, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(f['subtitle'] as String, style: AppTypography.bodyMedium(isDark).copyWith(fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Honest Non-Simulated Action with instant activation
              PrimaryButton(
                label: _isUpgrading
                    ? 'Activating Pro...'
                    : (_isAnnual ? 'Upgrade to Pro (\$39.99/yr)' : 'Upgrade to Pro (\$4.99/mo)'),
                isLoading: _isUpgrading,
                onPressed: _isUpgrading ? null : _handleUpgrade,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Cancel anytime in App Store or Google Play settings. No hidden fees.',
                textAlign: TextAlign.center,
                style: AppTypography.labelSmall(isDark),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
