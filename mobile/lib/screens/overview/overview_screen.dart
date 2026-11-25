import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/widgets/buttons/action_pill.dart';
import '../../core/widgets/financial/balance_summary_card.dart';
import '../../core/widgets/financial/expense_row.dart';
import '../../core/widgets/feedback/empty_state_view.dart';
import '../../core/widgets/feedback/error_state_view.dart';
import '../../core/widgets/feedback/loading_skeleton.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/di/injection.dart';
import '../../core/network/api_client.dart';
import '../../core/models/activity_model.dart';
import '../../core/models/expense_model.dart';
import '../../core/models/group_model.dart';
import '../../core/widgets/financial/debt_indicator_badge.dart';
import '../groups/create_group_bottom_sheet.dart';

class OverviewScreen extends StatefulWidget {
  final Function(ExpenseModel) onExpenseTap;
  final VoidCallback onSettleUpTap;
  final VoidCallback onScanReceiptTap;
  final VoidCallback onAddExpenseTap;
  final VoidCallback? onSessionExpired;
  final ValueChanged<String>? onCurrencyChanged;
  final Function(GroupModel)? onGroupTap;
  final VoidCallback? onCreateGroupTap;
  final VoidCallback? onActivityTap;

  const OverviewScreen({
    super.key,
    required this.onExpenseTap,
    required this.onSettleUpTap,
    required this.onScanReceiptTap,
    required this.onAddExpenseTap,
    this.onSessionExpired,
    this.onCurrencyChanged,
    this.onGroupTap,
    this.onCreateGroupTap,
    this.onActivityTap,
  });

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  String _errorTitle = 'Unable to Load Overview';
  bool _isAuthError = false;
  ActivitySummaryModel _summary = ActivitySummaryModel.empty();
  List<ActivityItemModel> _activities = [];
  List<GroupModel> _groups = [];
  String _overviewSection = 'GROUPS'; // 'GROUPS' or 'EXPENSES'
  String _activeFilter = 'ALL'; // ALL, LENT, BORROWED

  @override
  void initState() {
    super.initState();
    _loadOverviewData();
  }

  Future<void> _loadOverviewData({String? currencyOverride}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isAuthError = false;
    });

    try {
      String? activeCurrency = currencyOverride;
      try {
        final cachedUser = await Injection.tokenStorage.getCachedUser();
        activeCurrency ??= cachedUser?.defaultCurrency;
      } catch (_) {}

      final summaryFuture = Injection.activityRepository.getActivitySummary(currency: activeCurrency);
      final activitiesFuture = Injection.activityRepository.listActivity(limit: 20);
      final groupsFuture = Injection.groupRepository.listGroups();

      final results = await Future.wait([
        summaryFuture,
        activitiesFuture,
        groupsFuture,
      ]);
      final summary = results[0] as ActivitySummaryModel;
      final activities = results[1] as List<ActivityItemModel>;
      final groups = results[2] as List<GroupModel>;

      if (mounted) {
        setState(() {
          _summary = summary;
          _activities = activities;
          _groups = groups;
          _isLoading = false;
        });
        widget.onCurrencyChanged?.call(summary.currency);
      }
    } catch (e) {
      if (mounted) {
        if (e is ApiException) {
          setState(() {
            _isLoading = false;
            _isAuthError = e.isAuthError;
            if (e.isAuthError) {
              _errorTitle = 'Authentication Required';
              _errorMessage = 'Your session has expired or is not authenticated. Please sign in again to view your dashboard.';
            } else if (e.isConnectionError) {
              _errorTitle = 'Connection Disrupted';
              _errorMessage = 'Unable to connect to EvenBill server. Please check your network and verify the backend is running.';
            } else if (e.isForbidden) {
              _errorTitle = 'Access Restricted';
              _errorMessage = e.message;
            } else {
              _errorTitle = 'Unable to Load Overview';
              _errorMessage = e.message;
            }
          });

          if (e.isAuthError) {
            widget.onSessionExpired?.call();
          }
        } else {
          setState(() {
            _isLoading = false;
            _errorTitle = 'Unable to Load Overview';
            _errorMessage = e.toString();
            _isAuthError = false;
          });
        }
      }
    }
  }

  void _showCurrencyPickerSheet(BuildContext context) {
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
    final currentCode = _summary.currency.toUpperCase();

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
                  const Text(
                    'Active Currency',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
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
                  final isSelected = c['code'] == currentCode;
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
                        color: isSelected
                            ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                            : null,
                      ),
                    ),
                    subtitle: Text('Symbol: ${c['symbol']}'),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_circle_rounded,
                            color: isDark ? AppColors.mintAccent : AppColors.positiveGreen,
                          )
                        : null,
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        await Injection.authRepository.updateMe(
                          defaultCurrency: c['code'],
                        );
                        widget.onCurrencyChanged?.call(c['code']!);
                        if (mounted) {
                          AppSnackbar.showSuccess(
                            context,
                            'Primary currency set to ${c['flag']} ${c['code']} (${c['symbol']})',
                          );
                          await _loadOverviewData(currencyOverride: c['code']);
                        }
                      } catch (e) {
                        if (mounted) {
                          AppSnackbar.showError(context, 'Failed to update currency: $e');
                        }
                      }
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

  Future<void> _handleExpenseTap(ActivityItemModel item) async {
    try {
      final expense = await Injection.expenseRepository.getExpense(item.id);
      widget.onExpenseTap(expense);
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, 'Unable to load expense details: $e');
      }
    }
  }

  void _startNewGroup(BuildContext context) {
    if (widget.onCreateGroupTap != null) {
      widget.onCreateGroupTap!();
      return;
    }
    showCreateGroupModal(
      context: context,
      defaultCurrency: _summary.currency,
      onGroupCreated: (newGroup) {
        _loadOverviewData();
        widget.onGroupTap?.call(newGroup);
      },
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(date).inDays;

    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';

    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadOverviewData,
          color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
          child: _buildContent(isDark),
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    if (_isLoading) {
      return ListView(
        padding: AppSpacing.screenPadding,
        children: const [
          LoadingSkeleton(width: double.infinity, height: 210, borderRadius: AppRadius.roundedLg),
          SizedBox(height: AppSpacing.lg),
          ExpenseListSkeleton(),
        ],
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ErrorStateView(
            title: _errorTitle,
            message: _errorMessage!,
            retryLabel: _isAuthError ? 'Sign In Again' : 'Try Again',
            retryIcon: _isAuthError ? Icons.login_rounded : Icons.refresh_rounded,
            onRetry: () {
              if (_isAuthError) {
                widget.onSessionExpired?.call();
                Injection.apiClient.onSessionExpired?.call('Session expired. Please sign in again.');
              } else {
                _loadOverviewData();
              }
            },
          ),
        ),
      );
    }

    final lentCount = _activities.where((act) => act.userNetShare > 0).length;
    final oweCount = _activities.where((act) => act.userNetShare < 0).length;

    final filteredActivities = _activities.where((act) {
      if (_activeFilter == 'LENT') return act.userNetShare > 0;
      if (_activeFilter == 'BORROWED') return act.userNetShare < 0;
      return true;
    }).toList();

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppSpacing.screenPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        // Balance Summary Hero Card with API Data & Currency Customizer
        BalanceSummaryCard(
          totalNetBalance: _summary.totalNetBalance,
          youAreOwed: _summary.youAreOwedTotal,
          youOwe: _summary.youOweTotal,
          currency: _summary.currency,
          onSettleUp: widget.onSettleUpTap,
          onScanReceipt: widget.onScanReceiptTap,
          onCurrencyTap: () => _showCurrencyPickerSheet(context),
        ),
        const SizedBox(height: AppSpacing.md),

        // Section Navigation Pills: Your Groups vs Recent Expenses
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              ActionPill(
                label: 'Your Groups (${_groups.length})',
                isSelected: _overviewSection == 'GROUPS',
                onTap: () => setState(() => _overviewSection = 'GROUPS'),
              ),
              const SizedBox(width: AppSpacing.xs),
              ActionPill(
                label: 'Recent Expenses',
                isSelected: _overviewSection == 'EXPENSES',
                onTap: () => setState(() => _overviewSection = 'EXPENSES'),
              ),
              if (_overviewSection == 'GROUPS') ...[
                const SizedBox(width: AppSpacing.xs),
                ActionPill(
                  icon: Icons.add_rounded,
                  label: 'Start New',
                  isSelected: false,
                  onTap: () => _startNewGroup(context),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Display Active Section: Groups or Recent Expenses
        if (_overviewSection == 'GROUPS') ...[
          if (_groups.isEmpty)
            EmptyStateView(
              icon: Icons.group_work_outlined,
              title: 'No Groups Yet',
              description: 'Create a group to start sharing expenses and splitting bills with friends.',
              buttonLabel: 'Start a new group',
              onButtonPressed: () => _startNewGroup(context),
            )
          else ...[
            ..._groups.map((grp) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => widget.onGroupTap?.call(grp),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : Colors.grey.shade200,
                        ),
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              grp.type == 'HOME'
                                  ? Icons.home_rounded
                                  : (grp.type == 'TRIP'
                                      ? Icons.flight_takeoff_rounded
                                      : (grp.type == 'COUPLE'
                                          ? Icons.favorite_rounded
                                          : Icons.group_rounded)),
                              size: 22,
                              color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  grp.name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${grp.type} • ${grp.memberCount} ${grp.memberCount == 1 ? "member" : "members"}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DebtIndicatorBadge(
                            netAmount: grp.netBalance,
                            currency: grp.currency,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: AppSpacing.xs),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _startNewGroup(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard.withOpacity(0.6) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? AppColors.mintAccent.withOpacity(0.4)
                          : AppColors.forestGreen.withOpacity(0.25),
                      width: 1.5,
                    ),
                    boxShadow: [
                      if (!isDark)
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.group_add_rounded,
                          size: 18,
                          color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Start a new group',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ] else ...[
          // Sub-filters for Recent Expenses
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              children: [
                ActionPill(
                  label: 'All (${_activities.length})',
                  isSelected: _activeFilter == 'ALL',
                  onTap: () => setState(() => _activeFilter = 'ALL'),
                ),
                const SizedBox(width: AppSpacing.xs),
                ActionPill(
                  label: 'You Lent ($lentCount)',
                  isSelected: _activeFilter == 'LENT',
                  onTap: () => setState(() => _activeFilter = 'LENT'),
                ),
                const SizedBox(width: AppSpacing.xs),
                ActionPill(
                  label: 'You Owe ($oweCount)',
                  isSelected: _activeFilter == 'BORROWED',
                  onTap: () => setState(() => _activeFilter = 'BORROWED'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Activities List or Empty State
          if (filteredActivities.isEmpty)
            EmptyStateView(
              icon: Icons.receipt_long_outlined,
              title: 'No expenses recorded yet',
              description: 'Tap "+ Add Expense" below to start sharing bills with precision and clarity.',
              buttonLabel: 'Add Expense',
              onButtonPressed: widget.onAddExpenseTap,
            )
          else
            ...filteredActivities.map((act) {
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: ExpenseRow(
                  description: act.title,
                  category: act.category,
                  groupName: act.groupName ?? 'General',
                  dateFormatted: _formatDate(act.timestamp),
                  payerText: act.createdByName.isNotEmpty ? 'Paid by ${act.createdByName}' : act.itemType,
                  netShare: act.userNetShare,
                  currency: act.currency,
                  onTap: () => _handleExpenseTap(act),
                ),
              );
            }),
        ],
        ],
      ),
    );
  }
}
