import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons/action_pill.dart';
import '../../core/widgets/financial/category_icon.dart';
import '../../core/widgets/financial/amount_display.dart';
import '../../core/widgets/feedback/loading_skeleton.dart';
import '../../core/widgets/feedback/empty_state_view.dart';
import '../../core/widgets/feedback/error_state_view.dart';
import '../../core/di/injection.dart';
import '../../core/models/activity_model.dart';

class ActivityScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const ActivityScreen({super.key, this.onBack});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  ActivitySummaryModel _summary = ActivitySummaryModel.empty();
  List<ActivityItemModel> _activities = [];

  String _typeFilter = 'ALL'; // ALL, EXPENSES, SETTLEMENTS
  String _categoryFilter = 'ALL';
  final TextEditingController _searchController = TextEditingController();

  final List<String> _categories = [
    'ALL', 'FOOD', 'GROCERIES', 'TRAVEL', 'HOME', 'UTILITIES', 'ENTERTAINMENT', 'GENERAL'
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final summaryFuture = Injection.activityRepository.getActivitySummary();
      final activitiesFuture = Injection.activityRepository.listActivity(
        category: _categoryFilter == 'ALL' ? null : _categoryFilter,
        search: _searchController.text.trim(),
        limit: 50,
      );

      final results = await Future.wait([summaryFuture, activitiesFuture]);
      if (mounted) {
        setState(() {
          _summary = results[0] as ActivitySummaryModel;
          _activities = results[1] as List<ActivityItemModel>;
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack,
              )
            : null,
        title: const Text('Activity & Audit Feed'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Feed',
            onPressed: _loadData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
        child: _buildBody(isDark),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return ListView(
        padding: AppSpacing.screenPadding,
        children: const [
          LoadingSkeleton(width: double.infinity, height: 90, borderRadius: AppRadius.roundedMd),
          SizedBox(height: AppSpacing.md),
          ExpenseListSkeleton(),
        ],
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ErrorStateView(
            title: 'Could Not Load Activity',
            message: _errorMessage!,
            onRetry: _loadData,
          ),
        ),
      );
    }

    final filteredActivities = _activities.where((act) {
      if (_typeFilter == 'EXPENSES' && act.itemType != 'EXPENSE') return false;
      if (_typeFilter == 'SETTLEMENTS' && act.itemType != 'SETTLEMENT') return false;
      return true;
    }).toList();

    return ListView(
      padding: AppSpacing.screenPadding,
      children: [
        // Meaningful Spending Totals Card
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Monthly Spending', style: AppTypography.labelLarge(isDark).copyWith(fontWeight: FontWeight.w700)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.12),
                      borderRadius: AppRadius.roundedPill,
                    ),
                    child: Text(
                      'Total: ${_summary.currency} ${_summary.monthlySpending.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.arrow_downward_rounded, size: 13, color: isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen),
                            const SizedBox(width: 4),
                            Text('You Are Owed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        AmountDisplay(
                          amount: _summary.youAreOwedTotal,
                          currency: _summary.currency,
                          overrideColor: isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 38,
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.arrow_upward_rounded, size: 13, color: isDark ? AppColors.negativeRedDark : AppColors.negativeRed),
                            const SizedBox(width: 4),
                            Text('You Owe', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        AmountDisplay(
                          amount: _summary.youOweTotal,
                          currency: _summary.currency,
                          overrideColor: isDark ? AppColors.negativeRedDark : AppColors.negativeRed,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Search Bar
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by description or friend...',
              hintStyle: TextStyle(fontSize: 14, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
              prefixIcon: const Icon(Icons.search_rounded),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: () {
                        _searchController.clear();
                        _loadData();
                      },
                    )
                  : null,
            ),
            onSubmitted: (_) => _loadData(),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Type Filter Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ActionPill(
                label: 'All Activity',
                isSelected: _typeFilter == 'ALL',
                onTap: () => setState(() => _typeFilter = 'ALL'),
              ),
              const SizedBox(width: 8),
              ActionPill(
                label: 'Expenses Only',
                isSelected: _typeFilter == 'EXPENSES',
                onTap: () => setState(() => _typeFilter = 'EXPENSES'),
              ),
              const SizedBox(width: 8),
              ActionPill(
                label: 'Settlements Only',
                isSelected: _typeFilter == 'SETTLEMENTS',
                onTap: () => setState(() => _typeFilter = 'SETTLEMENTS'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),

        // Category Filter Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _categories.map((c) {
              final isSelected = _categoryFilter == c;
              return Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: FilterChip(
                  label: Text(c, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500)),
                  selected: isSelected,
                  onSelected: (val) {
                    if (val) {
                      setState(() => _categoryFilter = c);
                      _loadData();
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        if (filteredActivities.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40.0),
            child: EmptyStateView(
              icon: Icons.history_rounded,
              title: 'No Matching Activity',
              description: 'Try adjusting your search query or filters.',
            ),
          )
        else
          ...filteredActivities.map(
            (act) {
              final isExpense = act.itemType == 'EXPENSE';
              final isSettlement = act.itemType == 'SETTLEMENT';
              final isLent = !isSettlement && act.userNetShare > 0.001;
              final isBorrowed = !isSettlement && act.userNetShare < -0.001;
              final isZeroNetExpense = !isSettlement && !isLent && !isBorrowed;
              final involved = act.resolvedIsUserInvolved();
              final isNotInvolved = isZeroNetExpense && !involved;
              final isSoloPersonal = isZeroNetExpense &&
                  involved &&
                  act.totalAmount > 0.001 &&
                  ((act.userPaidAmount ?? 0) - act.totalAmount).abs() < 0.01 &&
                  ((act.userOwedAmount ?? 0) - act.totalAmount).abs() < 0.01;
              final color = isSettlement
                  ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                  : (isLent
                      ? (isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen)
                      : (isBorrowed
                          ? (isDark ? AppColors.negativeRedDark : AppColors.negativeRed)
                          : (involved
                              ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                              : (isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted))));
              final badgeLabel = isSettlement
                  ? 'settled'
                  : (isLent
                      ? 'lent'
                      : (isBorrowed
                          ? 'borrowed'
                          : (isSoloPersonal
                              ? 'personal'
                              : (involved ? 'even share' : 'no balance'))));
              final zeroNetAmount = isSoloPersonal
                  ? act.totalAmount
                  : ((act.userPaidAmount ?? 0) > 0.001
                      ? act.userPaidAmount!
                      : ((act.userOwedAmount ?? 0) > 0.001
                          ? act.userOwedAmount!
                          : act.totalAmount));

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    isExpense
                        ? CategoryIcon(category: act.category, size: 46)
                        : Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: color.withOpacity(0.25)),
                            ),
                            child: Icon(Icons.handshake_rounded, color: color, size: 24),
                          ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            act.title.isNotEmpty ? act.title : act.description,
                            style: AppTypography.titleMedium(isDark).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  act.groupName ?? 'Direct',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  act.description.isNotEmpty
                                      ? act.description
                                      : 'By ${act.createdByName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodyMedium(isDark).copyWith(fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${act.timestamp.year}-${act.timestamp.month.toString().padLeft(2, '0')}-${act.timestamp.day.toString().padLeft(2, '0')}',
                            style: AppTypography.labelSmall(isDark).copyWith(
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (isNotInvolved)
                          Text(
                            'not involved',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          )
                        else
                          AmountDisplay(
                            amount: isSettlement
                                ? act.totalAmount
                                : (isZeroNetExpense ? zeroNetAmount : act.userNetShare.abs()),
                            currency: act.currency,
                            overrideColor: color,
                          ),
                        const SizedBox(height: 3),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badgeLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 32),
      ],
    );
  }
}
