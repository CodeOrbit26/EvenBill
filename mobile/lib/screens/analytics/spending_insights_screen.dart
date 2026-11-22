import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons/primary_button.dart';
import '../../core/di/injection.dart';
import '../../core/models/spending_insights_model.dart';
import '../../core/models/entitlement_model.dart';
import '../subscription/pro_paywall_screen.dart';

class SpendingInsightsScreen extends StatefulWidget {
  final String? groupId;
  final String? initialCurrency;
  final VoidCallback onBack;

  const SpendingInsightsScreen({
    super.key,
    this.groupId,
    this.initialCurrency,
    required this.onBack,
  });

  @override
  State<SpendingInsightsScreen> createState() => _SpendingInsightsScreenState();
}

class _SpendingInsightsScreenState extends State<SpendingInsightsScreen> {
  bool _isLoading = true;
  SpendingInsightsModel? _insights;
  EntitlementModel? _entitlements;
  late String _selectedCurrency;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _selectedCurrency = widget.initialCurrency ?? 'USD';
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final ent = await Injection.subscriptionRepository.getEntitlements();
      final insights = await Injection.proRepository.getSpendingInsights(
        groupId: widget.groupId,
        currency: _selectedCurrency,
      );

      if (mounted) {
        setState(() {
          _entitlements = ent;
          _insights = insights;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _openPaywall() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProPaywallScreen(
          onBack: () => Navigator.of(context).pop(),
          onUpgradeSuccess: () {
            _loadData();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPro = _entitlements?.isPro ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spending & Category Insights'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.currency_exchange_rounded),
            tooltip: 'Change Currency',
            initialValue: _selectedCurrency,
            onSelected: (curr) {
              setState(() => _selectedCurrency = curr);
              _loadData();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'USD', child: Text('USD (\$)')),
              const PopupMenuItem(value: 'EUR', child: Text('EUR (€)')),
              const PopupMenuItem(value: 'GBP', child: Text('GBP (£)')),
              const PopupMenuItem(value: 'INR', child: Text('INR (₹)')),
              const PopupMenuItem(value: 'CAD', child: Text('CAD (\$)')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
                          const SizedBox(height: AppSpacing.md),
                          Text('Failed to load insights', style: AppTypography.titleMedium()),
                          const SizedBox(height: AppSpacing.sm),
                          Text(_errorMessage!, textAlign: TextAlign.center, style: AppTypography.bodySmall()),
                          const SizedBox(height: AppSpacing.md),
                          PrimaryButton(label: 'Retry', onPressed: _loadData),
                        ],
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        if (!isPro) _buildProBanner(context),
                        _buildSummaryCards(context),
                        const SizedBox(height: AppSpacing.lg),
                        _buildCategoryBreakdown(context),
                        const SizedBox(height: AppSpacing.lg),
                        _buildMonthlyTrend(context),
                        if (_insights?.groupBreakdown.isNotEmpty ?? false) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _buildGroupBreakdown(context),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildProBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryForest.withOpacity(0.9),
            AppColors.secondaryEvergreen.withOpacity(0.9),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.mintAccent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'PRO FEATURE',
                  style: AppTypography.labelSmall().copyWith(
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Unlock Complete Insights',
                style: AppTypography.titleSmall().copyWith(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Get unlimited category distribution, monthly historical spending trend graphs, and audit exports with EvenBill Pro.',
            style: AppTypography.bodySmall().copyWith(color: Colors.white.withOpacity(0.9)),
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Upgrade to Pro',
            onPressed: _openPaywall,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(BuildContext context) {
    final insights = _insights;
    final personalShare = insights?.totalSpentPersonalShare ?? 0.0;
    final totalPaid = insights?.totalPaidByUser ?? 0.0;
    final count = insights?.totalExpensesCount ?? 0;

    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your Net Spending', style: AppTypography.labelSmall()),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$_selectedCurrency ${personalShare.toStringAsFixed(2)}',
                  style: AppTypography.headlineSmall().copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryForest,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('$count expenses tracked', style: AppTypography.bodySmall()),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Paid by You', style: AppTypography.labelSmall()),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$_selectedCurrency ${totalPaid.toStringAsFixed(2)}',
                  style: AppTypography.headlineSmall().copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondaryEvergreen,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text('Upfront payments', style: AppTypography.bodySmall()),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryBreakdown(BuildContext context) {
    final categories = _insights?.categories ?? [];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Spending by Category', style: AppTypography.titleMedium().copyWith(fontWeight: FontWeight.bold)),
              Icon(Icons.pie_chart_rounded, color: AppColors.secondaryEvergreen),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (categories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: Text('No expenses recorded for this selection.', style: AppTypography.bodySmall()),
              ),
            )
          else
            ...categories.map((c) => _buildCategoryRow(context, c)),
        ],
      ),
    );
  }

  Widget _buildCategoryRow(BuildContext context, CategorySpendingModel cat) {
    final color = _getCategoryColor(cat.category);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(cat.category, style: AppTypography.bodyMedium().copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(width: AppSpacing.xs),
                  Text('(${cat.expenseCount})', style: AppTypography.bodySmall()),
                ],
              ),
              Text(
                '$_selectedCurrency ${cat.totalAmount.toStringAsFixed(2)} (${cat.percentage.toStringAsFixed(1)}%)',
                style: AppTypography.bodyMedium().copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (cat.percentage / 100).clamp(0.0, 1.0),
              backgroundColor: Theme.of(context).dividerColor.withOpacity(0.1),
              color: color,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyTrend(BuildContext context) {
    final trends = _insights?.monthlyTrend ?? [];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Monthly Spending Timeline', style: AppTypography.titleMedium().copyWith(fontWeight: FontWeight.bold)),
              Icon(Icons.bar_chart_rounded, color: AppColors.primaryForest),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (trends.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Center(
                child: Text('No historical monthly trends available.', style: AppTypography.bodySmall()),
              ),
            )
          else
            ...trends.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(m.month, style: AppTypography.bodyMedium().copyWith(fontWeight: FontWeight.w500)),
                      Text(
                        '$_selectedCurrency ${m.totalAmount.toStringAsFixed(2)}',
                        style: AppTypography.bodyMedium().copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildGroupBreakdown(BuildContext context) {
    final groups = _insights?.groupBreakdown ?? [];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spending by Group', style: AppTypography.titleMedium().copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.sm),
          ...groups.map((g) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(g.groupName, style: AppTypography.bodyMedium()),
                    Text(
                      '$_selectedCurrency ${g.totalAmount.toStringAsFixed(2)} (${g.percentage.toStringAsFixed(1)}%)',
                      style: AppTypography.bodySmall().copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Color _getCategoryColor(String cat) {
    switch (cat.toUpperCase()) {
      case 'GROCERIES':
        return Colors.green;
      case 'DINING OUT':
      case 'DINING':
        return Colors.deepOrange;
      case 'UTILITIES':
        return Colors.blue;
      case 'ENTERTAINMENT':
        return Colors.purple;
      case 'TRANSPORTATION':
        return Colors.amber.shade800;
      case 'TRIP':
        return Colors.teal;
      default:
        return AppColors.secondaryEvergreen;
    }
  }
}
