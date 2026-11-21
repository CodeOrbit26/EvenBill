import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons/primary_button.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/di/injection.dart';
import '../../core/models/bank_model.dart';

class BankImportSheet extends StatefulWidget {
  final ValueChanged<BankTransactionModel> onTransactionSelected;
  final VoidCallback onBack;

  const BankImportSheet({
    super.key,
    required this.onTransactionSelected,
    required this.onBack,
  });

  @override
  State<BankImportSheet> createState() => _BankImportSheetState();
}

class _BankImportSheetState extends State<BankImportSheet> {
  bool _isLoading = true;
  BankIntegrationStatusModel? _status;
  List<BankTransactionModel> _transactions = [];
  String? _error;
  String _selectedCountry = 'US';

  @override
  void initState() {
    super.initState();
    _loadBankData();
  }

  Future<void> _loadBankData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final status = await Injection.proRepository.getBankStatus(countryCode: _selectedCountry);
      final txs = await Injection.proRepository.syncBankTransactions(
        accountId: 'acc_demo_checking_001',
        countryCode: _selectedCountry,
        isSandbox: true,
      );

      if (mounted) {
        setState(() {
          _status = status;
          _transactions = txs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.account_balance_rounded, color: AppColors.primaryForest),
                  const SizedBox(width: AppSpacing.sm),
                  Text('Bank Import (Open Banking)', style: AppTypography.titleMedium().copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: widget.onBack,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _buildComplianceCard(context),
          const SizedBox(height: AppSpacing.md),
          Text('Available Verified Transactions', style: AppTypography.titleSmall().copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: AppSpacing.xs),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: AppTypography.bodySmall()))
                    : _transactions.isEmpty
                        ? const Center(child: Text('No verified transactions available for import.'))
                        : ListView.separated(
                            itemCount: _transactions.length,
                            separatorBuilder: (context, _) => const SizedBox(height: AppSpacing.xs),
                            itemBuilder: (context, index) {
                              final tx = _transactions[index];
                              return Card(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.mintAccent.withOpacity(0.3),
                                    child: Icon(Icons.account_balance_wallet_rounded, color: AppColors.primaryForest, size: 20),
                                  ),
                                  title: Text(tx.merchantName, style: AppTypography.bodyMedium().copyWith(fontWeight: FontWeight.bold)),
                                  subtitle: Text('${tx.category} • ${tx.date}', style: AppTypography.bodySmall()),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${tx.currency} ${tx.amount.toStringAsFixed(2)}',
                                        style: AppTypography.bodyMedium().copyWith(fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Text('Tap to import', style: AppTypography.labelSmall().copyWith(color: AppColors.secondaryEvergreen)),
                                    ],
                                  ),
                                  onTap: () {
                                    widget.onTransactionSelected(tx);
                                    Navigator.of(context).pop();
                                  },
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildComplianceCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.secondaryEvergreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secondaryEvergreen.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_rounded, size: 16, color: AppColors.secondaryEvergreen),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Open Banking / PSD2 Compliance Framework',
                style: AppTypography.labelSmall().copyWith(fontWeight: FontWeight.bold, color: AppColors.secondaryEvergreen),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Read-only financial transactions are synced through approved institutional providers. Explicit consent is required. No bank imports are conducted without certified regulatory authorization.',
            style: AppTypography.bodySmall().copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
