import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons/primary_button.dart';
import '../../core/widgets/buttons/action_pill.dart';
import '../../core/widgets/inputs/app_text_field.dart';
import '../../core/widgets/inputs/currency_amount_field.dart';
import '../../core/widgets/financial/category_icon.dart';
import '../../core/widgets/financial/amount_display.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/di/injection.dart';
import '../../core/models/expense_model.dart';
import '../../core/models/group_model.dart';
import '../../core/models/friend_model.dart';
import '../../core/models/entitlement_model.dart';
import '../../core/models/user_model.dart';
import '../../core/utils/identity_utils.dart';
import 'receipt_review_modal.dart';
import 'split_preset_picker_modal.dart';
import '../bank/bank_import_sheet.dart';
import '../subscription/pro_paywall_screen.dart';

class AddEditExpenseScreen extends StatefulWidget {
  final ExpenseModel? initialExpense;
  final String? preselectedGroupId;
  final String? preselectedCurrency;
  final VoidCallback onSaved;
  final VoidCallback onBack;

  const AddEditExpenseScreen({
    super.key,
    this.initialExpense,
    this.preselectedGroupId,
    this.preselectedCurrency,
    required this.onSaved,
    required this.onBack,
  });

  @override
  State<AddEditExpenseScreen> createState() => _AddEditExpenseScreenState();
}

class _AddEditExpenseScreenState extends State<AddEditExpenseScreen> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController = TextEditingController();

  String _selectedCurrency = 'INR';
  String _selectedCategory = 'FOOD';
  String? _selectedGroupId; // null means Direct Expense (No Group)
  UserModel? _currentUser;
  String _paidByUserId = '';
  String _paidByName = 'You';
  bool _hasExplicitPayerSelection = false;
  String? _contextLoadError;
  String _splitType = 'EQUAL'; // EQUAL, EXACT, PERCENTAGE, SHARES, ADJUSTMENT, ITEMIZED
  bool _isSubmitting = false;
  bool _isDirty = false;
  EntitlementModel? _entitlement;

  List<GroupModel> _groups = [];
  List<FriendModel> _friends = [];
  List<Map<String, String>> _availableParticipants = []; // [ {'id': ..., 'name': ...} ]
  Set<String> _selectedParticipantIds = {};

  // Custom Split Controllers
  final Map<String, TextEditingController> _exactControllers = {};
  final Map<String, TextEditingController> _percentControllers = {};
  final Map<String, TextEditingController> _sharesControllers = {};
  final Map<String, TextEditingController> _adjustmentControllers = {};

  // Itemized line items
  final List<Map<String, dynamic>> _itemizedItems = [];
  final _taxController = TextEditingController(text: '0');
  final _tipController = TextEditingController(text: '0');

  final List<String> _categories = [
    'FOOD', 'GROCERIES', 'TRAVEL', 'HOME', 'UTILITIES', 'ENTERTAINMENT', 'GENERAL'
  ];

  @override
  void initState() {
    super.initState();
    if (widget.preselectedCurrency != null && widget.preselectedCurrency!.isNotEmpty) {
      _selectedCurrency = widget.preselectedCurrency!;
    }
    _amountController.addListener(_markDirty);
    _descriptionController.addListener(_markDirty);
    _notesController.addListener(_markDirty);

    _selectedGroupId = widget.preselectedGroupId ?? widget.initialExpense?.groupId;

    if (widget.initialExpense != null) {
      final exp = widget.initialExpense!;
      _amountController.text = exp.totalAmount.toStringAsFixed(2);
      _descriptionController.text = exp.description;
      _selectedCurrency = exp.currency;
      _selectedCategory = exp.category.toUpperCase();
      _selectedGroupId = exp.groupId;
      _splitType = exp.splitType.toUpperCase();
      _notesController.text = exp.notes ?? '';

      if (exp.payers.isNotEmpty) {
        _paidByUserId = exp.payers.first.userId;
        _paidByName = exp.payers.first.fullName;
        _hasExplicitPayerSelection = !isPlaceholderUserId(_paidByUserId);
      }
    }

    _loadContextData();
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _taxController.dispose();
    _tipController.dispose();
    for (final c in _exactControllers.values) {
      c.dispose();
    }
    for (final c in _percentControllers.values) {
      c.dispose();
    }
    for (final c in _sharesControllers.values) {
      c.dispose();
    }
    for (final c in _adjustmentControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadContextData() async {
    try {
      final currentUser = await resolveAuthenticatedUser();
      final groups = await Injection.groupRepository.listGroups();
      final friends = await Injection.friendRepository.listFriends();
      try {
        final ent = await Injection.subscriptionRepository.getEntitlements();
        if (mounted) setState(() => _entitlement = ent);
      } catch (_) {}

      // Pre-customization: Automatically sync default currency with chosen preference or group
      String resolvedCurrency = widget.preselectedCurrency ?? _selectedCurrency;
      if (widget.initialExpense == null) {
        if (_selectedGroupId != null) {
          final grp = groups.where((g) => g.id == _selectedGroupId).firstOrNull;
          if (grp != null && grp.baseCurrency.isNotEmpty) {
            resolvedCurrency = grp.baseCurrency;
          }
        } else if (groups.length == 1) {
          _selectedGroupId = groups.first.id;
          if (groups.first.baseCurrency.isNotEmpty) {
            resolvedCurrency = groups.first.baseCurrency;
          }
        } else if (currentUser != null && currentUser.defaultCurrency.isNotEmpty) {
          resolvedCurrency = currentUser.defaultCurrency;
        }
      }

      if (mounted) {
        setState(() {
          _currentUser = currentUser;
          _groups = groups;
          _friends = friends;
          _contextLoadError = null;
          if (widget.initialExpense == null) {
            _selectedCurrency = resolvedCurrency;
            if (!_hasExplicitPayerSelection &&
                currentUser != null &&
                !isPlaceholderUserId(currentUser.id)) {
              _paidByUserId = currentUser.id;
              _paidByName = currentUser.fullName.isNotEmpty ? currentUser.fullName : 'You';
            }
          }
        });

        await _updateParticipantsForSelection();
      }
    } catch (_) {
      final currentUser = await resolveAuthenticatedUser();
      if (mounted) {
        setState(() {
          _currentUser = currentUser;
          if (currentUser != null && !isPlaceholderUserId(currentUser.id)) {
            if (widget.initialExpense == null && !_hasExplicitPayerSelection) {
              _paidByUserId = currentUser.id;
              _paidByName = currentUser.fullName.isNotEmpty ? currentUser.fullName : 'You';
            }
            _availableParticipants = [
              {
                'id': currentUser.id,
                'name': currentUser.fullName.isNotEmpty ? currentUser.fullName : 'You',
              },
            ];
            _selectedParticipantIds = {currentUser.id};
            _contextLoadError = null;
            _initParticipantControllers();
          } else {
            _availableParticipants = [];
            _selectedParticipantIds = {};
            _contextLoadError =
                'Unable to resolve your authenticated profile. Please refresh or sign in again.';
          }
        });
      }
    }
  }

  Future<void> _updateParticipantsForSelection() async {
    final currentUser = _currentUser ?? await resolveAuthenticatedUser();
    if (!mounted) return;
    _currentUser = currentUser;

    if (_selectedGroupId != null) {
      // Group selected: load group members with canonical UUIDs
      try {
        final detail = await Injection.groupRepository.getGroupDetails(_selectedGroupId!);
        final participants = detail.members
            .where((m) => !isPlaceholderUserId(m.userId))
            .map((m) => {'id': m.userId, 'name': m.fullName})
            .toList();
        if (participants.isEmpty && currentUser != null && !isPlaceholderUserId(currentUser.id)) {
          participants.add({
            'id': currentUser.id,
            'name': currentUser.fullName.isNotEmpty ? currentUser.fullName : 'You',
          });
        }
        if (mounted) {
          setState(() {
            _availableParticipants = participants;
            _selectedParticipantIds = participants.map((p) => p['id']!).toSet();
            if (widget.initialExpense == null && !_hasExplicitPayerSelection) {
              final selfMatch = currentUser != null
                  ? participants.where((p) => p['id'] == currentUser.id).firstOrNull
                  : null;
              final defaultPayer = selfMatch ?? (participants.isNotEmpty ? participants.first : null);
              if (defaultPayer != null) {
                _paidByUserId = defaultPayer['id']!;
                _paidByName = defaultPayer['name']!;
              }
            }
            _contextLoadError = participants.isEmpty
                ? 'No valid group members found. Please reload this group.'
                : null;
            _initParticipantControllers();
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _availableParticipants = [];
            _selectedParticipantIds = {};
            _contextLoadError = 'Unable to load group members. Please check connection and retry.';
          });
        }
      }
    } else {
      // Direct Expense (No Group): authenticated user UUID + friends
      if (currentUser == null || isPlaceholderUserId(currentUser.id)) {
        setState(() {
          _availableParticipants = [];
          _selectedParticipantIds = {};
          _contextLoadError = 'Authenticated user profile is required to record an expense.';
        });
        return;
      }

      final participants = <Map<String, String>>[
        {
          'id': currentUser.id,
          'name': currentUser.fullName.isNotEmpty ? currentUser.fullName : 'You',
        },
        ..._friends
            .where((f) => f.id != currentUser.id && !isPlaceholderUserId(f.id))
            .map((f) => {'id': f.id, 'name': f.name}),
      ];
      setState(() {
        _availableParticipants = participants;
        _selectedParticipantIds = participants.map((p) => p['id']!).toSet();
        if (widget.initialExpense == null && !_hasExplicitPayerSelection) {
          _paidByUserId = currentUser.id;
          _paidByName = currentUser.fullName.isNotEmpty ? currentUser.fullName : 'You';
        }
        _contextLoadError = null;
        _initParticipantControllers();
      });
    }
  }

  void _initParticipantControllers() {
    for (final p in _availableParticipants) {
      final id = p['id']!;
      _exactControllers.putIfAbsent(id, () => TextEditingController(text: '0.00'));
      _percentControllers.putIfAbsent(id, () => TextEditingController(text: (100 / _availableParticipants.length).toStringAsFixed(1)));
      _sharesControllers.putIfAbsent(id, () => TextEditingController(text: '1'));
      _adjustmentControllers.putIfAbsent(id, () => TextEditingController(text: '0.00'));
    }
  }

  Future<bool> _handleWillPop() async {
    final hasContent = (_amountController.text.trim().isNotEmpty &&
            _amountController.text.trim() != '0.00' &&
            _amountController.text.trim() != '0') ||
        _descriptionController.text.trim().isNotEmpty;
    if (!_isDirty || !hasContent) return true;

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Unsaved Changes?'),
        content: const Text('You have unsaved changes to this expense. Are you sure you want to discard them?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Editing')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.negativeRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    return discard ?? false;
  }

  Future<void> _handleSave() async {
    final amountText = _amountController.text.trim();
    final description = _descriptionController.text.trim();

    if (amountText.isEmpty || double.tryParse(amountText) == null || double.parse(amountText) <= 0) {
      AppSnackbar.showError(context, 'Please enter a valid expense amount greater than 0');
      return;
    }

    if (description.isEmpty) {
      AppSnackbar.showError(context, 'Please enter a description for the expense');
      return;
    }

    if (_selectedParticipantIds.isEmpty) {
      AppSnackbar.showError(
        context,
        _contextLoadError ?? 'Please select at least one participant',
      );
      return;
    }

    if (isPlaceholderUserId(_paidByUserId)) {
      final resolved = _currentUser ?? await resolveAuthenticatedUser();
      if (!mounted) return;
      if (resolved != null && !isPlaceholderUserId(resolved.id)) {
        setState(() {
          _currentUser = resolved;
          _paidByUserId = resolved.id;
          _paidByName = resolved.fullName.isNotEmpty ? resolved.fullName : 'You';
        });
      } else {
        AppSnackbar.showError(
          context,
          'Authenticated user identity unavailable. Please sign in again.',
        );
        return;
      }
    }

    if (_selectedParticipantIds.any(isPlaceholderUserId)) {
      AppSnackbar.showError(
        context,
        'One or more selected participants lack valid user IDs. Please reload.',
      );
      return;
    }

    final totalAmount = double.parse(amountText);
    setState(() => _isSubmitting = true);

    try {
      // Build split payloads based on method
      List<SplitModel>? splits;
      Map<String, double>? percentages;
      Map<String, double>? shares;
      Map<String, double>? adjustments;
      List<ItemizedItemInput>? items;

      if (_splitType == 'EXACT') {
        splits = [];
        double exactSum = 0;
        for (final pId in _selectedParticipantIds) {
          final amt = double.tryParse(_exactControllers[pId]?.text ?? '0') ?? 0;
          exactSum += amt;
          final pName = _availableParticipants.firstWhere((p) => p['id'] == pId, orElse: () => {'name': 'User'})['name']!;
          splits.add(SplitModel(userId: pId, fullName: pName, owedAmount: amt));
        }
        if ((exactSum - totalAmount).abs() > 0.05) {
          AppSnackbar.showError(context, 'Exact splits sum (\$$exactSum) must match total (\$$totalAmount)');
          setState(() => _isSubmitting = false);
          return;
        }
      } else if (_splitType == 'PERCENTAGE') {
        percentages = {};
        double pctSum = 0;
        for (final pId in _selectedParticipantIds) {
          final pct = double.tryParse(_percentControllers[pId]?.text ?? '0') ?? 0;
          pctSum += pct;
          percentages[pId] = pct;
        }
        if ((pctSum - 100.0).abs() > 0.1) {
          AppSnackbar.showError(context, 'Percentages must total exactly 100% (currently $pctSum%)');
          setState(() => _isSubmitting = false);
          return;
        }
      } else if (_splitType == 'SHARES') {
        shares = {};
        for (final pId in _selectedParticipantIds) {
          final sh = double.tryParse(_sharesControllers[pId]?.text ?? '1') ?? 1;
          shares[pId] = sh;
        }
      } else if (_splitType == 'ADJUSTMENT') {
        adjustments = {};
        for (final pId in _selectedParticipantIds) {
          final adj = double.tryParse(_adjustmentControllers[pId]?.text ?? '0') ?? 0;
          adjustments[pId] = adj;
        }
      } else if (_splitType == 'ITEMIZED' && _itemizedItems.isNotEmpty) {
        items = _itemizedItems.map((it) {
          return ItemizedItemInput(
            description: it['description'] as String,
            amount: it['amount'] as double,
            participantIds: (it['participant_ids'] as List<dynamic>).map((e) => e.toString()).toList(),
          );
        }).toList();
      }

      final payerList = [
        PayerModel(
          userId: _paidByUserId,
          fullName: _paidByName,
          amountPaid: totalAmount,
        )
      ];

      if (widget.initialExpense != null) {
        await Injection.expenseRepository.updateExpense(
          widget.initialExpense!.id,
          description: description,
          totalAmount: totalAmount,
          currency: _selectedCurrency,
          splitType: _splitType,
          category: _selectedCategory,
          notes: _notesController.text.trim(),
          payers: payerList,
          participantIds: _selectedParticipantIds.toList(),
          splits: splits,
          percentages: percentages,
          shares: shares,
          adjustments: adjustments,
          items: items,
          tax: double.tryParse(_taxController.text) ?? 0,
          tip: double.tryParse(_tipController.text) ?? 0,
        );
        if (mounted) {
          AppSnackbar.showSuccess(context, 'Expense updated successfully!');
          widget.onSaved();
        }
      } else {
        await Injection.expenseRepository.createExpense(
          groupId: _selectedGroupId,
          description: description,
          totalAmount: totalAmount,
          currency: _selectedCurrency,
          splitType: _splitType,
          category: _selectedCategory,
          notes: _notesController.text.trim(),
          payers: payerList,
          participantIds: _selectedParticipantIds.toList(),
          splits: splits,
          percentages: percentages,
          shares: shares,
          adjustments: adjustments,
          items: items,
          tax: double.tryParse(_taxController.text) ?? 0,
          tip: double.tryParse(_tipController.text) ?? 0,
        );
        if (mounted) {
          AppSnackbar.showSuccess(context, 'Expense logged and balances recalculated!');
          widget.onSaved();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        final err = e.toString();
        if (err.contains('FEATURE_LOCKED') ||
            err.contains('DAILY_EXPENSE_CREATION') ||
            err.contains('daily limit') ||
            err.contains('403')) {
          _showLimitReachedDialog(
            context,
            'You have reached your daily limit of ${_entitlement?.dailyLimit ?? 4} new expenses on the Free plan. Your entered data and allocations are completely preserved!',
          );
        } else {
          AppSnackbar.showError(context, 'Failed to save expense: $e');
        }
      }
    }
  }

  void _showLimitReachedDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_clock_rounded, color: AppColors.forestGreen),
            SizedBox(width: 8),
            Flexible(child: Text('Daily Limit Reached')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.mintAccent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: AppColors.forestGreen),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your draft and allocations are preserved. No data will be lost.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.forestGreen),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Draft'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.forestGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProPaywallScreen(
                    onBack: () => Navigator.pop(context),
                    onUpgradeSuccess: () async {
                      try {
                        final ent = await Injection.subscriptionRepository.getEntitlements();
                        if (mounted) setState(() => _entitlement = ent);
                      } catch (_) {}
                    },
                  ),
                ),
              );
            },
            child: const Text('Upgrade to Pro'),
          ),
        ],
      ),
    );
  }

  List<double> _getQuickAmountDeltas() {
    switch (_selectedCurrency.toUpperCase()) {
      case 'INR':
      case 'JPY':
        return [100, 500, 1000, 2000, 5000];
      default:
        return [10, 25, 50, 100, 200];
    }
  }

  void _addQuickAmount(double delta) {
    final cur = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final updated = cur + delta;
    setState(() {
      _amountController.text = updated.truncateToDouble() == updated
          ? updated.toInt().toString()
          : updated.toStringAsFixed(2);
      _markDirty();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = widget.initialExpense != null;

    return PopScope(
      canPop: !_isDirty,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        final shouldPop = await _handleWillPop();
        if (shouldPop && context.mounted) {
          widget.onBack();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () async {
              final shouldPop = await _handleWillPop();
              if (shouldPop) widget.onBack();
            },
          ),
          title: Text(isEditing ? 'Edit Expense' : 'Add Expense'),
          actions: [
            TextButton(
              onPressed: _isSubmitting ? null : _handleSave,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Allowance status banner for Free users (compact inline ribbon)
                if (!isEditing && _entitlement != null && !_entitlement!.isPro) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: (_entitlement!.dailyRemaining ?? 0) > 0
                          ? (isDark ? AppColors.darkCard : AppColors.lightCardSubtle)
                          : AppColors.negativeRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (_entitlement!.dailyRemaining ?? 0) > 0
                            ? (isDark ? AppColors.darkBorder : AppColors.lightBorder)
                            : AppColors.negativeRed.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          (_entitlement!.dailyRemaining ?? 0) > 0
                              ? Icons.info_outline_rounded
                              : Icons.warning_amber_rounded,
                          size: 15,
                          color: (_entitlement!.dailyRemaining ?? 0) > 0
                              ? AppColors.forestGreen
                              : AppColors.negativeRed,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Free Plan: ${_entitlement!.dailyRemaining ?? 0} of ${_entitlement!.dailyLimit ?? 4} new expenses remaining today',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : AppColors.primaryText,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProPaywallScreen(
                                  onBack: () => Navigator.pop(context),
                                  onUpgradeSuccess: () async {
                                    try {
                                      final ent = await Injection.subscriptionRepository.getEntitlements();
                                      if (mounted) setState(() => _entitlement = ent);
                                    } catch (_) {}
                                  },
                                ),
                              ),
                            );
                          },
                          child: const Text(
                            'Upgrade',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.forestGreen,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Pro Quick Actions: Scan Receipt, Split Presets, Bank Import (compact horizontal chips)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: const Icon(Icons.document_scanner_rounded, size: 14, color: AppColors.forestGreen),
                        label: const Text('Scan Receipt (OCR)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5)),
                        onPressed: _openReceiptScanner,
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: const Icon(Icons.tune_rounded, size: 14, color: AppColors.secondaryEvergreen),
                        label: const Text('Split Presets', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5)),
                        onPressed: _openSplitPresets,
                      ),
                      const SizedBox(width: 6),
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        avatar: const Icon(Icons.account_balance_rounded, size: 14, color: Colors.indigo),
                        label: const Text('Bank Import', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5)),
                        onPressed: _openBankImport,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // Currency & Amount Input (hero compact)
                CurrencyAmountField(
                  controller: _amountController,
                  currency: _selectedCurrency,
                  onCurrencyTap: () => _showCurrencyPicker(context),
                ),

                // Quick Amount Increment Chips (compact)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 2),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ..._getQuickAmountDeltas().map((delta) {
                          final sym = AmountDisplay.getCurrencySymbol(_selectedCurrency);
                          final label = '+$sym${delta.toInt()}';
                          return Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: ActionChip(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              label: Text(label),
                              labelStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                              ),
                              backgroundColor: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.08),
                              side: BorderSide(
                                color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.2),
                              ),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              onPressed: () => _addQuickAmount(delta),
                            ),
                          );
                        }),
                        if (_amountController.text.isNotEmpty && _amountController.text != '0' && _amountController.text != '0.00')
                          Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: ActionChip(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              label: const Text('Clear'),
                              labelStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.grey),
                              backgroundColor: Colors.transparent,
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              onPressed: () {
                                setState(() {
                                  _amountController.text = '';
                                  _markDirty();
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_selectedCurrency != 'USD')
                  Padding(
                    padding: const EdgeInsets.only(top: 2, bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.currency_exchange_rounded, size: 12, color: AppColors.secondaryEvergreen),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Text(
                            'Original amount preserved. Converted with audited ECB rates.',
                            style: TextStyle(fontSize: 10.5, color: AppColors.secondaryEvergreen),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),

                // Description input
                AppTextField(
                  label: 'Description',
                  hintText: 'e.g. Dinner, Groceries, Flight tickets',
                  controller: _descriptionController,
                  prefixIcon: Icons.description_outlined,
                ),
                const SizedBox(height: 8),

                // Group & Category in ONE streamlined row
                Row(
                  children: [
                    // Group Selector
                    Expanded(
                      flex: 5,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Group / Shared Context',
                            style: AppTypography.labelLarge(isDark).copyWith(fontSize: 11.5),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String?>(
                                isExpanded: true,
                                value: (_selectedGroupId != null && _groups.any((g) => g.id == _selectedGroupId))
                                    ? _selectedGroupId
                                    : null,
                                icon: const Icon(Icons.arrow_drop_down, size: 18),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Row(
                                      children: [
                                        Icon(Icons.person_outline_rounded, size: 15),
                                        SizedBox(width: 6),
                                        Expanded(child: Text('Direct (No Group)', style: TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                                      ],
                                    ),
                                  ),
                                  ..._groups.map((g) => DropdownMenuItem<String?>(
                                        value: g.id,
                                        child: Row(
                                          children: [
                                            Icon(Icons.group_outlined, size: 15),
                                            SizedBox(width: 6),
                                            Expanded(child: Text('${g.name} (${g.type})', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                                          ],
                                        ),
                                      )),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _selectedGroupId = val;
                                    _markDirty();
                                    if (val != null) {
                                      final g = _groups.where((grp) => grp.id == val).firstOrNull;
                                      if (g != null && g.baseCurrency.isNotEmpty) {
                                        _selectedCurrency = g.baseCurrency;
                                      }
                                    } else {
                                      Injection.tokenStorage.getCachedUser().then((u) {
                                        if (u != null && mounted) {
                                          setState(() => _selectedCurrency = u.defaultCurrency);
                                        }
                                      });
                                    }
                                  });
                                  _updateParticipantsForSelection();
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Category Selector
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Category',
                            style: AppTypography.labelLarge(isDark).copyWith(fontSize: 11.5),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            height: 40,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                value: _selectedCategory,
                                icon: const Icon(Icons.arrow_drop_down, size: 18),
                                items: _categories.map((c) => DropdownMenuItem(
                                      value: c,
                                      child: Row(
                                        children: [
                                          CategoryIcon(category: c, size: 16),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              c,
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _selectedCategory = val;
                                      _markDirty();
                                    });
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Paid By & Split Method unified compact card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Paid by: ',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                              InkWell(
                                onTap: () => _showPaidByPicker(context),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _paidByName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        Icons.arrow_drop_down,
                                        size: 16,
                                        color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Text(
                            'Split method',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ActionPill(
                              label: 'Equally (=)',
                              isSelected: _splitType == 'EQUAL',
                              onTap: () {
                                setState(() => _splitType = 'EQUAL');
                                _markDirty();
                              },
                            ),
                            const SizedBox(width: 6),
                            ActionPill(
                              label: 'Exact Amounts (${AmountDisplay.getCurrencySymbol(_selectedCurrency)})',
                              isSelected: _splitType == 'EXACT',
                              onTap: () {
                                setState(() => _splitType = 'EXACT');
                                _markDirty();
                              },
                            ),
                            const SizedBox(width: 6),
                            ActionPill(
                              label: 'Percentages (%)',
                              isSelected: _splitType == 'PERCENTAGE',
                              onTap: () {
                                setState(() => _splitType = 'PERCENTAGE');
                                _markDirty();
                              },
                            ),
                            const SizedBox(width: 6),
                            ActionPill(
                              label: 'Shares (1x, 2x)',
                              isSelected: _splitType == 'SHARES',
                              onTap: () {
                                setState(() => _splitType = 'SHARES');
                                _markDirty();
                              },
                            ),
                            const SizedBox(width: 6),
                            ActionPill(
                              label: 'Adjustments (+/-)',
                              isSelected: _splitType == 'ADJUSTMENT',
                              onTap: () {
                                setState(() => _splitType = 'ADJUSTMENT');
                                _markDirty();
                              },
                            ),
                            const SizedBox(width: 6),
                            ActionPill(
                              label: 'Itemized (Receipt)',
                              isSelected: _splitType == 'ITEMIZED',
                              onTap: () {
                                setState(() => _splitType = 'ITEMIZED');
                                _markDirty();
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Participants Selector & Split Breakdown Card (Compact)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Split Between (${_selectedParticipantIds.length}/${_availableParticipants.length})',
                            style: AppTypography.labelLarge(isDark).copyWith(fontSize: 12),
                          ),
                          if (_availableParticipants.length > 1)
                            InkWell(
                              onTap: () {
                                setState(() {
                                  if (_selectedParticipantIds.length == _availableParticipants.length) {
                                    final fallbackId = (_paidByUserId.isNotEmpty && !isPlaceholderUserId(_paidByUserId))
                                        ? _paidByUserId
                                        : _availableParticipants
                                            .map((p) => p['id'] ?? '')
                                            .firstWhere((id) => id.isNotEmpty && !isPlaceholderUserId(id), orElse: () => '');
                                    _selectedParticipantIds = fallbackId.isNotEmpty ? {fallbackId} : {};
                                  } else {
                                    _selectedParticipantIds = _availableParticipants.map((p) => p['id']!).toSet();
                                  }
                                  _markDirty();
                                });
                              },
                              child: Text(
                                _selectedParticipantIds.length == _availableParticipants.length ? 'Reset' : 'Select All',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ..._availableParticipants.map((p) {
                        final id = p['id']!;
                        final name = p['name']!;
                        final isIncluded = _selectedParticipantIds.contains(id);
                        final totalAmt = double.tryParse(_amountController.text.trim()) ?? 0.0;
                        final activeCount = _selectedParticipantIds.isEmpty ? 1 : _selectedParticipantIds.length;
                        final equalShare = isIncluded ? totalAmt / activeCount : 0.0;
                        final sym = AmountDisplay.getCurrencySymbol(_selectedCurrency);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2.0),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 26,
                                height: 26,
                                child: Checkbox(
                                  value: isIncluded,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedParticipantIds.add(id);
                                      } else {
                                        if (_selectedParticipantIds.length > 1) {
                                          _selectedParticipantIds.remove(id);
                                        }
                                      }
                                      _markDirty();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: isIncluded ? FontWeight.w700 : FontWeight.w500,
                                    color: isIncluded
                                        ? (isDark ? AppColors.darkTextPrimary : AppColors.primaryText)
                                        : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                                  ),
                                ),
                              ),
                              if (_splitType == 'EQUAL' && isIncluded && totalAmt > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '$sym${equalShare.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                                    ),
                                  ),
                                ),
                              if (isIncluded && _splitType == 'EXACT')
                                SizedBox(
                                  width: 80,
                                  height: 34,
                                  child: TextField(
                                    controller: _exactControllers[id],
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      prefixText: sym,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    ),
                                  ),
                                )
                              else if (isIncluded && _splitType == 'PERCENTAGE')
                                SizedBox(
                                  width: 70,
                                  height: 34,
                                  child: TextField(
                                    controller: _percentControllers[id],
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      suffixText: '%',
                                      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    ),
                                  ),
                                )
                              else if (isIncluded && _splitType == 'SHARES')
                                SizedBox(
                                  width: 60,
                                  height: 34,
                                  child: TextField(
                                    controller: _sharesControllers[id],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      suffixText: 'x',
                                      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    ),
                                  ),
                                )
                              else if (isIncluded && _splitType == 'ADJUSTMENT')
                                SizedBox(
                                  width: 80,
                                  height: 34,
                                  child: TextField(
                                    controller: _adjustmentControllers[id],
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                    decoration: const InputDecoration(
                                      isDense: true,
                                      prefixText: '+/-',
                                      contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Itemized Breakdown (if ITEMIZED split selected)
                if (_splitType == 'ITEMIZED') ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Line Items', style: AppTypography.labelLarge(isDark)),
                              TextButton.icon(
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('Add Item'),
                                onPressed: () => _showAddItemDialog(context),
                              ),
                            ],
                          ),
                          if (_itemizedItems.isEmpty)
                            const Text('No line items yet. Tap Add Item to specify items.', style: TextStyle(color: Colors.grey, fontSize: 12))
                          else
                            ..._itemizedItems.map(
                              (it) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(it['description'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text('Assigned to ${(it['participant_ids'] as List).length} members'),
                                trailing: Text('\$${(it['amount'] as double).toStringAsFixed(2)}'),
                              ),
                            ),
                          const Divider(),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _taxController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(labelText: 'Tax Amount', isDense: true),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextField(
                                  controller: _tipController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(labelText: 'Tip Amount', isDense: true),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],

                PrimaryButton(
                  label: _isSubmitting
                      ? 'Saving...'
                      : (isEditing ? 'Update Expense' : 'Save Expense'),
                  onPressed: _isSubmitting ? () {} : _handleSave,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddItemDialog(BuildContext context) {
    final itemDesc = TextEditingController();
    final itemAmt = TextEditingController();
    final assigned = Set<String>.from(_selectedParticipantIds);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDS) => AlertDialog(
          title: const Text('Add Line Item'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: itemDesc, decoration: const InputDecoration(labelText: 'Item Name')),
              const SizedBox(height: 8),
              TextField(controller: itemAmt, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Price')),
              const SizedBox(height: 12),
              const Align(alignment: Alignment.centerLeft, child: Text('Assigned To:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12))),
              ..._availableParticipants.map((p) {
                final isChecked = assigned.contains(p['id']);
                return CheckboxListTile(
                  dense: true,
                  title: Text(p['name']!),
                  value: isChecked,
                  onChanged: (val) {
                    setDS(() {
                      if (val == true) {
                        assigned.add(p['id']!);
                      } else {
                        assigned.remove(p['id']!);
                      }
                    });
                  },
                );
              }),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final amt = double.tryParse(itemAmt.text) ?? 0;
                if (itemDesc.text.isNotEmpty && amt > 0 && assigned.isNotEmpty) {
                  setState(() {
                    _itemizedItems.add({
                      'description': itemDesc.text.trim(),
                      'amount': amt,
                      'participant_ids': assigned.toList(),
                    });
                    _markDirty();
                  });
                  Navigator.pop(ctx);
                }
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showCurrencyPicker(BuildContext context) {
    final currencies = [
      {'code': 'INR', 'name': 'Indian Rupee', 'symbol': '₹', 'flag': '🇮🇳'},
      {'code': 'USD', 'name': 'US Dollar', 'symbol': '\$', 'flag': '🇺🇸'},
      {'code': 'EUR', 'name': 'Euro', 'symbol': '€', 'flag': '🇪🇺'},
      {'code': 'GBP', 'name': 'British Pound', 'symbol': '£', 'flag': '🇬🇧'},
      {'code': 'JPY', 'name': 'Japanese Yen', 'symbol': '¥', 'flag': '🇯🇵'},
      {'code': 'CAD', 'name': 'Canadian Dollar', 'symbol': 'C\$', 'flag': '🇨🇦'},
      {'code': 'AUD', 'name': 'Australian Dollar', 'symbol': 'A\$', 'flag': '🇦🇺'},
      {'code': 'AED', 'name': 'UAE Dirham', 'symbol': 'AED', 'flag': '🇦🇪'},
      {'code': 'SGD', 'name': 'Singapore Dollar', 'symbol': 'S\$', 'flag': '🇸🇬'},
      {'code': 'CHF', 'name': 'Swiss Franc', 'symbol': 'CHF', 'flag': '🇨🇭'},
    ];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.roundedTopSheet),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Select Expense Currency', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  Text(
                    'Consistent across app',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: currencies.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
                itemBuilder: (context, index) {
                  final c = currencies[index];
                  final isSelected = _selectedCurrency == c['code'];
                  return ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? (isDark ? AppColors.mintAccent.withOpacity(0.2) : AppColors.forestGreen.withOpacity(0.1))
                            : (isDark ? AppColors.darkCardSubtle : Colors.grey.shade100),
                        shape: BoxShape.circle,
                      ),
                      child: Text(c['flag']!, style: const TextStyle(fontSize: 20)),
                    ),
                    title: Text(
                      '${c['code']} - ${c['name']}',
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? (isDark ? AppColors.mintAccent : AppColors.forestGreen) : null,
                      ),
                    ),
                    subtitle: Text('Symbol: ${c['symbol']}'),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded, color: isDark ? AppColors.mintAccent : AppColors.positiveGreen)
                        : null,
                    onTap: () async {
                      setState(() => _selectedCurrency = c['code']!);
                      _markDirty();
                      Navigator.pop(ctx);
                      try {
                        await Injection.authRepository.updateMe(defaultCurrency: c['code']);
                      } catch (_) {}
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPaidByPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.roundedTopSheet),
      builder: (ctx) => ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 20),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text('Who Paid For This Bill?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          ..._availableParticipants.map(
            (p) => ListTile(
              title: Text(p['name']!, style: const TextStyle(fontWeight: FontWeight.w700)),
              trailing: _paidByUserId == p['id'] ? const Icon(Icons.check, color: AppColors.positiveGreen) : null,
              onTap: () {
                setState(() {
                  _paidByUserId = p['id']!;
                  _paidByName = p['name']!;
                  _hasExplicitPayerSelection = true;
                });
                _markDirty();
                Navigator.pop(ctx);
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openReceiptScanner() {
    final isPro = _entitlement?.isPro ?? false;
    if (!isPro) {
      _showProGateDialog(
        title: 'Receipt Scanning & OCR',
        description: 'Auto-extract line items, taxes, tips, and assign individual diners to items with EvenBill Pro.',
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ReceiptReviewModal(
        participants: _availableParticipants,
        onConfirmed: (confirmed) {
          setState(() {
            _descriptionController.text = confirmed.merchant;
            _amountController.text = confirmed.totalAmount.toStringAsFixed(2);
            _selectedCurrency = confirmed.currency;
            if (confirmed.items.isNotEmpty) {
              _splitType = 'ITEMIZED';
              _itemizedItems.clear();
              for (final it in confirmed.items) {
                _itemizedItems.add({
                  'description': it.description,
                  'amount': it.amount,
                  'participant_ids': it.assignedParticipantIds.isNotEmpty
                      ? it.assignedParticipantIds
                      : _selectedParticipantIds.toList(),
                });
              }
              _taxController.text = confirmed.tax.toStringAsFixed(2);
              _tipController.text = confirmed.tip.toStringAsFixed(2);
            }
            _markDirty();
          });
          AppSnackbar.showSuccess(context, 'Receipt items confirmed and applied to expense!');
        },
      ),
    );
  }

  void _openSplitPresets() {
    if (_selectedGroupId == null) {
      AppSnackbar.showError(context, 'Please select a group first to apply saved group split presets.');
      return;
    }

    final isPro = _entitlement?.isPro ?? false;
    if (!isPro) {
      _showProGateDialog(
        title: 'Saved Group Split Presets',
        description: 'Save custom recurring split ratios (e.g. 60/40 or custom weighted shares) for your group with EvenBill Pro.',
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SplitPresetPickerModal(
        groupId: _selectedGroupId!,
        members: _availableParticipants,
        onTemplateSelected: (tmpl) {
          setState(() {
            _splitType = tmpl.splitType;
            if (tmpl.splitType == 'PERCENTAGE') {
              for (final alloc in tmpl.allocations) {
                _percentControllers[alloc.userId]?.text = alloc.value.toStringAsFixed(0);
              }
            } else if (tmpl.splitType == 'SHARES') {
              for (final alloc in tmpl.allocations) {
                _sharesControllers[alloc.userId]?.text = alloc.value.toStringAsFixed(0);
              }
            } else if (tmpl.splitType == 'EXACT') {
              for (final alloc in tmpl.allocations) {
                _exactControllers[alloc.userId]?.text = alloc.value.toStringAsFixed(2);
              }
            }
            _markDirty();
          });
          AppSnackbar.showSuccess(context, 'Applied split preset "${tmpl.name}"');
        },
      ),
    );
  }

  void _openBankImport() {
    final isPro = _entitlement?.isPro ?? false;
    if (!isPro) {
      _showProGateDialog(
        title: 'Open Banking Import',
        description: 'Securely sync and import read-only transactions from your bank with EvenBill Pro.',
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BankImportSheet(
        onBack: () => Navigator.of(ctx).pop(),
        onTransactionSelected: (tx) {
          setState(() {
            _descriptionController.text = tx.suggestedExpenseDescription;
            _amountController.text = tx.amount.toStringAsFixed(2);
            _selectedCurrency = tx.currency;
            _selectedCategory = tx.category.toUpperCase();
            _markDirty();
          });
          AppSnackbar.showSuccess(context, 'Imported bank transaction: ${tx.merchantName}');
        },
      ),
    );
  }

  void _showProGateDialog({required String title, required String description}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.star_rounded, color: AppColors.forestGreen),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(description),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.forestGreen,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProPaywallScreen(
                    onBack: () => Navigator.pop(context),
                    onUpgradeSuccess: () async {
                      try {
                        final ent = await Injection.subscriptionRepository.getEntitlements();
                        if (mounted) setState(() => _entitlement = ent);
                      } catch (_) {}
                    },
                  ),
                ),
              );
            },
            child: const Text('Unlock with Pro'),
          ),
        ],
      ),
    );
  }
}
