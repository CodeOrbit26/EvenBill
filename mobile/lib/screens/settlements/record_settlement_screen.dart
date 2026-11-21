import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons/primary_button.dart';
import '../../core/widgets/buttons/action_pill.dart';
import '../../core/widgets/inputs/currency_amount_field.dart';
import '../../core/widgets/inputs/app_text_field.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/di/injection.dart';
import '../../core/models/friend_model.dart';

class RecordSettlementScreen extends StatefulWidget {
  final FriendModel? preselectedFriend;
  final String? preselectedRecipientId;
  final String? preselectedRecipientName;
  final double? preselectedAmount;
  final String? preselectedCurrency;
  final String? preselectedGroupId;
  final VoidCallback onSettled;
  final VoidCallback onBack;

  const RecordSettlementScreen({
    super.key,
    this.preselectedFriend,
    this.preselectedRecipientId,
    this.preselectedRecipientName,
    this.preselectedAmount,
    this.preselectedCurrency,
    this.preselectedGroupId,
    required this.onSettled,
    required this.onBack,
  });

  @override
  State<RecordSettlementScreen> createState() => _RecordSettlementScreenState();
}

class _RecordSettlementScreenState extends State<RecordSettlementScreen> {
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  String? _currentUserId;
  String? _recipientId;
  String _recipientName = 'Member';
  String _currency = 'INR';
  String _paymentMethod = 'UPI'; // UPI, CASH, BANK_TRANSFER
  bool _isYouPaying = true;
  bool _isLoadingPartners = true;
  bool _isSubmitting = false;

  List<FriendModel> _partners = [];
  final List<String> _methods = ['UPI', 'CASH', 'BANK_TRANSFER'];

  @override
  void initState() {
    super.initState();
    if (widget.preselectedFriend != null) {
      _recipientId = widget.preselectedFriend!.id;
      _recipientName = widget.preselectedFriend!.name;
      _currency = widget.preselectedFriend!.currency;
      _amountController.text = widget.preselectedFriend!.netBalance.abs().toStringAsFixed(2);
      _isYouPaying = widget.preselectedFriend!.netBalance < 0;
    } else if (widget.preselectedRecipientId != null) {
      _recipientId = widget.preselectedRecipientId;
      _recipientName = widget.preselectedRecipientName ?? 'Member';
      _currency = widget.preselectedCurrency ?? 'INR';
      if (widget.preselectedAmount != null && widget.preselectedAmount! > 0) {
        _amountController.text = widget.preselectedAmount!.toStringAsFixed(2);
      } else {
        _amountController.text = '500.00';
      }
    } else {
      _currency = widget.preselectedCurrency ?? 'INR';
      _amountController.text = '500.00';
    }

    _loadPartners();
  }

  Future<void> _loadPartners() async {
    try {
      var cachedUser = await Injection.tokenStorage.getCachedUser();
      if (cachedUser == null) {
        try {
          cachedUser = await Injection.authRepository.getMe();
        } catch (_) {}
      }
      final currentUserId = cachedUser?.id;
      final byUserId = <String, FriendModel>{};

      if (widget.preselectedGroupId != null) {
        try {
          final detail = await Injection.groupRepository.getGroupDetails(widget.preselectedGroupId!);
          for (final m in detail.members) {
            if (m.userId != currentUserId) {
              byUserId[m.userId] = FriendModel(
                id: m.userId,
                name: m.fullName,
                email: m.email,
                avatarUrl: m.avatarUrl,
                netBalance: 0.0,
                currency: detail.group.currency,
              );
            }
          }
        } catch (_) {}
      } else {
        try {
          final friends = await Injection.friendRepository.listFriends();
          for (final f in friends) {
            if (f.id != currentUserId) {
              byUserId[f.id] = f;
            }
          }
        } catch (_) {}

        try {
          final groups = await Injection.groupRepository.listGroups();
          for (final g in groups) {
            try {
              final detail = await Injection.groupRepository.getGroupDetails(g.id);
              for (final m in detail.members) {
                if (m.userId != currentUserId && !byUserId.containsKey(m.userId)) {
                  byUserId[m.userId] = FriendModel(
                    id: m.userId,
                    name: m.fullName,
                    email: m.email,
                    avatarUrl: m.avatarUrl,
                    netBalance: 0.0,
                    currency: g.currency,
                  );
                }
              }
            } catch (_) {}
          }
        } catch (_) {}
      }

      final partners = byUserId.values.toList();
      if (mounted) {
        setState(() {
          _currentUserId = currentUserId;
          _partners = partners;
          _isLoadingPartners = false;
          if (_recipientId == null && partners.isNotEmpty) {
            _recipientId = partners.first.id;
            _recipientName = partners.first.name;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingPartners = false);
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _addQuickAmount(double delta) {
    final current = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final updated = current + delta;
    setState(() {
      _amountController.text = updated.toStringAsFixed(2);
    });
  }

  Future<void> _handleRecord() async {
    final amtText = _amountController.text.trim();
    if (amtText.isEmpty || double.tryParse(amtText) == null || double.parse(amtText) <= 0) {
      AppSnackbar.showError(context, 'Please enter a valid settlement amount');
      return;
    }

    if (_recipientId == null) {
      AppSnackbar.showError(
        context,
        'No settlement partner found — add a member to a group first',
      );
      return;
    }

    final amount = double.parse(amtText);
    final bool reverseDirection = !_isYouPaying && _currentUserId != null;
    final String? payerId = reverseDirection ? _recipientId! : null;
    final String recipientId = reverseDirection ? _currentUserId! : _recipientId!;

    setState(() => _isSubmitting = true);

    try {
      await Injection.settlementRepository.recordSettlement(
        groupId: widget.preselectedGroupId,
        payerId: payerId,
        recipientId: recipientId,
        amount: amount,
        currency: _currency,
        paymentMethod: _paymentMethod,
        transactionReference: _referenceController.text.trim(),
        notes: _notesController.text.trim(),
      );

      if (mounted) {
        AppSnackbar.showSuccess(
          context,
          'Settlement of $_currency $amtText with $_recipientName recorded! Debt balances cleared.',
        );
        widget.onSettled();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        AppSnackbar.showError(context, 'Failed to record settlement: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final currencySign = _currency == 'INR'
        ? '₹'
        : (_currency == 'EUR'
            ? '€'
            : (_currency == 'GBP' ? '£' : '\$'));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: widget.onBack,
        ),
        title: const Text('Record Settlement'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: AppSpacing.screenPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Direction Switcher (You pay vs You received)
              Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _isYouPaying = true),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: _isYouPaying
                                ? (isDark ? AppColors.mintAccent.withOpacity(0.2) : AppColors.forestGreen.withOpacity(0.12))
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _isYouPaying
                                  ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.arrow_outward_rounded,
                                size: 16,
                                color: _isYouPaying
                                    ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                                    : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'You paid $_recipientName',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: _isYouPaying ? FontWeight.w800 : FontWeight.w600,
                                    fontSize: 12,
                                    color: _isYouPaying
                                        ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                                        : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => _isYouPaying = false),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                          decoration: BoxDecoration(
                            color: !_isYouPaying
                                ? (isDark ? AppColors.mintAccent.withOpacity(0.2) : AppColors.forestGreen.withOpacity(0.12))
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: !_isYouPaying
                                  ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                                  : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.arrow_downward_rounded,
                                size: 16,
                                color: !_isYouPaying
                                    ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                                    : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '$_recipientName paid You',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: !_isYouPaying ? FontWeight.w800 : FontWeight.w600,
                                    fontSize: 12,
                                    color: !_isYouPaying
                                        ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                                        : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Large Amount Field
              CurrencyAmountField(
                controller: _amountController,
                currency: _currency,
                onCurrencyTap: () {
                  final currencies = [
                    {'code': 'INR', 'flag': '🇮🇳', 'name': 'Indian Rupee (₹)'},
                    {'code': 'USD', 'flag': '🇺🇸', 'name': 'US Dollar (\$)'},
                    {'code': 'EUR', 'flag': '🇪🇺', 'name': 'Euro (€)'},
                    {'code': 'GBP', 'flag': '🇬🇧', 'name': 'British Pound (£)'},
                    {'code': 'JPY', 'flag': '🇯🇵', 'name': 'Japanese Yen (¥)'},
                    {'code': 'CAD', 'flag': '🇨🇦', 'name': 'Canadian Dollar (C\$)'},
                  ];
                  showModalBottomSheet(
                    context: context,
                    shape: const RoundedRectangleBorder(borderRadius: AppRadius.roundedTopSheet),
                    builder: (ctx) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('Select Settlement Currency', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          ),
                          const Divider(height: 1),
                          Flexible(
                            child: ListView(
                              shrinkWrap: true,
                              children: currencies.map((c) => ListTile(
                                leading: Text(c['flag']!, style: const TextStyle(fontSize: 22)),
                                title: Text(c['name']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                                trailing: _currency == c['code']
                                    ? Icon(Icons.check_circle_rounded, color: isDark ? AppColors.mintAccent : AppColors.forestGreen)
                                    : null,
                                onTap: () {
                                  setState(() => _currency = c['code']!);
                                  Navigator.pop(ctx);
                                },
                              )).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.xs),

              // Quick Amount Increment Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ActionChip(
                      label: Text('+$currencySign 100'),
                      onPressed: () => _addQuickAmount(100),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: Text('+$currencySign 500'),
                      onPressed: () => _addQuickAmount(500),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: Text('+$currencySign 1,000'),
                      onPressed: () => _addQuickAmount(1000),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: Text('+$currencySign 2,000'),
                      onPressed: () => _addQuickAmount(2000),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(Icons.refresh_rounded, size: 14),
                      label: const Text('Clear'),
                      onPressed: () => setState(() => _amountController.text = '0.00'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Settlement Partner Selector
              Text('Settlement Partner', style: AppTypography.labelLarge(isDark).copyWith(fontSize: 13)),
              const SizedBox(height: AppSpacing.xxs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                  borderRadius: AppRadius.roundedMd,
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _recipientId,
                    hint: Text(
                      _isLoadingPartners
                          ? 'Loading members...'
                          : (_partners.isEmpty ? 'No members available yet' : _recipientName),
                    ),
                    items: [
                      if (_recipientId != null && !_partners.any((f) => f.id == _recipientId))
                        DropdownMenuItem<String?>(
                          value: _recipientId,
                          child: Text(_recipientName),
                        ),
                      ..._partners.map((f) => DropdownMenuItem<String?>(
                            value: f.id,
                            child: Text(f.name),
                          )),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        final found = _partners.firstWhere(
                          (f) => f.id == val,
                          orElse: () => FriendModel(id: val, name: _recipientName, email: '', netBalance: 0),
                        );
                        setState(() {
                          _recipientId = val;
                          _recipientName = found.name;
                        });
                      }
                    },
                  ),
                ),
              ),
              if (!_isLoadingPartners && _partners.isEmpty && _recipientId == null) ...[
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.warningAmber.withOpacity(0.12),
                    borderRadius: AppRadius.roundedMd,
                    border: Border.all(color: AppColors.warningAmber.withOpacity(0.35)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.group_add_outlined, size: 18, color: AppColors.warningAmber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your groups currently have no other members. Open a group and tap "+ Add Member" to add someone before recording a settlement.',
                          style: AppTypography.bodyMedium(isDark).copyWith(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),

              // Payment Method Chooser with Icons
              Text('Payment Method', style: AppTypography.labelLarge(isDark).copyWith(fontSize: 13)),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _methods.map((m) {
                  final isSelected = _paymentMethod == m;
                  return ActionPill(
                    label: m,
                    isSelected: isSelected,
                    onTap: () => setState(() => _paymentMethod = m),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.md),

              // Transaction Reference (e.g. UPI Ref / Bank Transfer ID)
              AppTextField(
                label: 'Payment Reference (Optional)',
                hintText: 'e.g. UPI Ref / Bank Transfer ID',
                controller: _referenceController,
                prefixIcon: Icons.receipt_long_outlined,
              ),
              const SizedBox(height: AppSpacing.md),

              AppTextField(
                label: 'Notes',
                hintText: 'e.g. Cleared ski trip balance',
                controller: _notesController,
                maxLines: 2,
              ),
              const SizedBox(height: AppSpacing.xl),

              PrimaryButton(
                label: _isSubmitting ? 'Recording Settlement...' : 'Record Settlement',
                icon: Icons.check_circle_outline_rounded,
                onPressed: _isSubmitting ? () {} : _handleRecord,
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
