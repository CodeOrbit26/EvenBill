import 'package:flutter/material.dart';
import '../../core/di/injection.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/logo/evenbill_logo.dart';
import '../../core/models/group_model.dart';
import '../../core/models/friend_model.dart';
import '../../core/models/expense_model.dart';
import '../overview/overview_screen.dart';
import '../groups/groups_list_screen.dart';
import '../groups/group_details_screen.dart';
import '../friends/friend_details_screen.dart';
import '../activity/activity_screen.dart';
import '../profile/profile_settings_screen.dart';
import '../expenses/add_edit_expense_screen.dart';
import '../expenses/expense_details_screen.dart';
import '../settlements/record_settlement_screen.dart';
import '../subscription/pro_paywall_screen.dart';
import '../analytics/spending_insights_screen.dart';
import '../expenses/search_expenses_sheet.dart';
import '../payments/scan_and_pay_screen.dart';

class AppNavigationShell extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final VoidCallback onSignOut;

  const AppNavigationShell({
    super.key,
    required this.currentThemeMode,
    required this.onThemeChanged,
    required this.onSignOut,
  });

  @override
  State<AppNavigationShell> createState() => _AppNavigationShellState();
}

class _AppNavigationShellState extends State<AppNavigationShell> {
  int _currentIndex = 0;

  // Active Sub-screen State
  GroupModel? _selectedGroup;
  FriendModel? _selectedFriend;
  ExpenseModel? _selectedExpense;
  bool _isAddingExpense = false;
  bool _isRecordingSettlement = false;
  bool _isOpenPaywall = false;
  bool _isOpenInsights = false;
  bool _isOpenSearch = false;
  bool _isOpenActivity = false;
  bool _isScanningAndPaying = false;
  int _overviewRefreshKey = 0;
  String _activeCurrency = 'INR';

  // Settlement prefill
  FriendModel? _settlementFriend;
  String? _settlementRecipientId;
  String? _settlementRecipientName;
  double? _settlementAmount;
  String? _settlementCurrency;
  String? _settlementGroupId;

  @override
  void initState() {
    super.initState();
    _loadUserCurrency();
  }

  Future<void> _loadUserCurrency() async {
    try {
      final user = await Injection.tokenStorage.getCachedUser();
      if (user != null && user.defaultCurrency.isNotEmpty && mounted) {
        setState(() => _activeCurrency = user.defaultCurrency);
      }
    } catch (_) {}
  }

  void _openSettlement({
    FriendModel? friend,
    String? recipientId,
    String? recipientName,
    double? amount,
    String? currency,
    String? groupId,
  }) {
    setState(() {
      _settlementFriend = friend;
      _settlementRecipientId = recipientId;
      _settlementRecipientName = recipientName;
      _settlementAmount = amount;
      _settlementCurrency = currency ?? _activeCurrency;
      _settlementGroupId = groupId;
      _isRecordingSettlement = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Sub-screen routing
    if (_isOpenActivity) {
      return ActivityScreen(onBack: () => setState(() => _isOpenActivity = false));
    }

    if (_isOpenPaywall) {
      return ProPaywallScreen(onBack: () => setState(() => _isOpenPaywall = false));
    }

    if (_isOpenInsights) {
      return SpendingInsightsScreen(
        initialCurrency: _activeCurrency,
        onBack: () => setState(() => _isOpenInsights = false),
      );
    }

    if (_isOpenSearch) {
      return SearchExpensesSheet(onBack: () => setState(() => _isOpenSearch = false));
    }

    if (_isScanningAndPaying) {
      return ScanAndPayScreen(
        onBack: () => setState(() => _isScanningAndPaying = false),
        defaultCurrency: _activeCurrency,
        onPaymentRecorded: (exp) {
          setState(() {
            _isScanningAndPaying = false;
            _overviewRefreshKey++;
          });
        },
      );
    }

    if (_isAddingExpense) {
      return AddEditExpenseScreen(
        initialExpense: _selectedExpense,
        preselectedGroupId: _selectedGroup?.id,
        preselectedCurrency: _activeCurrency,
        onSaved: () => setState(() {
          _isAddingExpense = false;
          _selectedExpense = null;
          _overviewRefreshKey++;
        }),
        onBack: () => setState(() {
          _isAddingExpense = false;
          _selectedExpense = null;
        }),
      );
    }

    if (_isRecordingSettlement) {
      return RecordSettlementScreen(
        preselectedFriend: _settlementFriend ?? _selectedFriend,
        preselectedRecipientId: _settlementRecipientId,
        preselectedRecipientName: _settlementRecipientName,
        preselectedAmount: _settlementAmount,
        preselectedCurrency: _settlementCurrency,
        preselectedGroupId: _settlementGroupId,
        onSettled: () => setState(() {
          _isRecordingSettlement = false;
          _settlementFriend = null;
          _settlementRecipientId = null;
          _settlementRecipientName = null;
          _overviewRefreshKey++;
        }),
        onBack: () => setState(() {
          _isRecordingSettlement = false;
          _settlementFriend = null;
          _settlementRecipientId = null;
          _settlementRecipientName = null;
        }),
      );
    }

    if (_selectedExpense != null) {
      return ExpenseDetailsScreen(
        expense: _selectedExpense!,
        onEdit: () => setState(() => _isAddingExpense = true),
        onDelete: () => setState(() => _selectedExpense = null),
        onBack: () => setState(() => _selectedExpense = null),
      );
    }

    if (_selectedGroup != null) {
      return GroupDetailsScreen(
        group: _selectedGroup!,
        onAddExpense: () => setState(() => _isAddingExpense = true),
        onExpenseTap: (exp) => setState(() => _selectedExpense = exp),
        onSettleDebt: (debtorId, debtorName, creditorId, creditorName, amount, currency) {
          _openSettlement(
            recipientId: creditorId,
            recipientName: creditorName,
            amount: amount,
            currency: currency,
            groupId: _selectedGroup!.id,
          );
        },
        onBack: () => setState(() => _selectedGroup = null),
      );
    }

    if (_selectedFriend != null) {
      return FriendDetailsScreen(
        friend: _selectedFriend!,
        onSettleUp: () => _openSettlement(friend: _selectedFriend),
        onExpenseTap: (exp) => setState(() => _selectedExpense = exp),
        onBack: () => setState(() => _selectedFriend = null),
      );
    }

    return Scaffold(
      appBar: _currentIndex == 0
          ? AppBar(
              title: const EvenBillLogo(size: 28, showWordmark: true),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  tooltip: 'Search Expenses',
                  onPressed: () => setState(() => _isOpenSearch = true),
                ),
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  tooltip: 'Activity',
                  onPressed: () => setState(() => _isOpenActivity = true),
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      body: _buildTabContent(),
      floatingActionButton: _currentIndex == 2
          ? null
          : FloatingActionButton.extended(
              backgroundColor: isDark ? AppColors.mintAccent : AppColors.forestGreen,
              foregroundColor: isDark ? AppColors.darkBackground : Colors.white,
              icon: const Icon(Icons.add_rounded, size: 22),
              label: const Text('Add Expense', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () => setState(() => _isAddingExpense = true),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group_rounded),
            label: 'Groups',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_currentIndex) {
      case 0:
        return OverviewScreen(
          key: ValueKey('overview_$_overviewRefreshKey'),
          onExpenseTap: (exp) => setState(() => _selectedExpense = exp),
          onGroupTap: (grp) => setState(() => _selectedGroup = grp),
          onSettleUpTap: () => _openSettlement(),
          onScanReceiptTap: () => setState(() => _isScanningAndPaying = true),
          onAddExpenseTap: () => setState(() => _isAddingExpense = true),
          onSessionExpired: widget.onSignOut,
          onCurrencyChanged: (curr) => setState(() => _activeCurrency = curr),
          onActivityTap: () => setState(() => _isOpenActivity = true),
        );
      case 1:
        return GroupsListScreen(
          defaultCurrency: _activeCurrency,
          onGroupTap: (grp) => setState(() => _selectedGroup = grp),
          onActivityTap: () => setState(() => _isOpenActivity = true),
        );
      case 2:
        return ProfileSettingsScreen(
          currentThemeMode: widget.currentThemeMode,
          onThemeChanged: widget.onThemeChanged,
          onCurrencyChanged: (curr) => setState(() => _activeCurrency = curr),
          onOpenPaywall: () => setState(() => _isOpenPaywall = true),
          onSignOut: widget.onSignOut,
          onActivityTap: () => setState(() => _isOpenActivity = true),
        );
      default:
        return const Center(child: Text('EvenBill'));
    }
  }
}
