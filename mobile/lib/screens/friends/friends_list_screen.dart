import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/avatars/user_avatar.dart';
import '../../core/widgets/financial/debt_indicator_badge.dart';
import '../../core/widgets/financial/amount_display.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/widgets/feedback/empty_state_view.dart';
import '../../core/widgets/feedback/error_state_view.dart';
import '../../core/widgets/feedback/loading_skeleton.dart';
import '../../core/widgets/inputs/app_text_field.dart';
import '../../core/di/injection.dart';
import '../../core/models/friend_model.dart';

class FriendsListScreen extends StatefulWidget {
  final Function(FriendModel) onFriendTap;
  final VoidCallback? onAddFriend;

  const FriendsListScreen({
    super.key,
    required this.onFriendTap,
    this.onAddFriend,
  });

  @override
  State<FriendsListScreen> createState() => _FriendsListScreenState();
}

class _FriendsListScreenState extends State<FriendsListScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<FriendModel> _friends = [];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final friends = await Injection.friendRepository.listFriends();
      if (mounted) {
        setState(() {
          _friends = friends;
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

  void _showAddFriendDialog(BuildContext context) {
    final emailController = TextEditingController();
    bool isAdding = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.person_add_rounded,
                    color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                const Text('Add Friend', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter the email address of the person you want to split bills with directly.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 14),
                AppTextField(
                  label: 'Friend\'s Email',
                  hintText: 'alex@example.com',
                  controller: emailController,
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                  foregroundColor: isDark ? AppColors.darkBackground : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: isAdding
                    ? null
                    : () async {
                        final email = emailController.text.trim();
                        if (email.isEmpty || !email.contains('@')) {
                          AppSnackbar.showError(ctx, 'Please enter a valid email address');
                          return;
                        }

                        setDialogState(() => isAdding = true);
                        try {
                          final friend = await Injection.friendRepository.addFriend(email);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            AppSnackbar.showSuccess(context, 'Friend ${friend.name} added!');
                            _loadFriends();
                          }
                        } catch (e) {
                          setDialogState(() => isAdding = false);
                          if (ctx.mounted) {
                            AppSnackbar.showError(ctx, 'Failed to add friend: $e');
                          }
                        }
                      },
                child: isAdding
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Add Friend', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Add Friend',
            onPressed: () => _showAddFriendDialog(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadFriends,
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
          LoadingSkeleton(width: double.infinity, height: 70, borderRadius: AppRadius.roundedMd),
          SizedBox(height: AppSpacing.sm),
          LoadingSkeleton(width: double.infinity, height: 60, borderRadius: AppRadius.roundedMd),
          SizedBox(height: AppSpacing.sm),
          LoadingSkeleton(width: double.infinity, height: 60, borderRadius: AppRadius.roundedMd),
        ],
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ErrorStateView(
            title: 'Could Not Load Friends',
            message: _errorMessage!,
            onRetry: _loadFriends,
          ),
        ),
      );
    }

    double totalOwedToMe = 0.0;
    double totalIOwe = 0.0;
    String currency = 'INR';
    for (final f in _friends) {
      currency = f.currency;
      if (f.netBalance > 0) {
        totalOwedToMe += f.netBalance;
      } else if (f.netBalance < 0) {
        totalIOwe += f.netBalance.abs();
      }
    }

    return ListView(
      padding: AppSpacing.screenPadding,
      children: [
        // Top 1-on-1 Balance Summary Card
        if (_friends.isNotEmpty) ...[
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.arrow_downward_rounded,
                            size: 14,
                            color: isDark ? AppColors.positiveGreenDark : AppColors.positiveGreen,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Friends owe you',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AmountDisplay(
                        amount: totalOwedToMe,
                        currency: currency,
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
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.arrow_upward_rounded,
                            size: 14,
                            color: isDark ? AppColors.negativeRedDark : AppColors.negativeRed,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'You owe friends',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      AmountDisplay(
                        amount: totalIOwe,
                        currency: currency,
                        overrideColor: isDark ? AppColors.negativeRedDark : AppColors.negativeRed,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('All Friends (${_friends.length})', style: AppTypography.labelLarge(isDark)),
            TextButton.icon(
              icon: const Icon(Icons.person_add_alt_1, size: 16),
              label: const Text('Add Friend', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              onPressed: () => _showAddFriendDialog(context),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),

        if (_friends.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 36.0),
            child: EmptyStateView(
              icon: Icons.people_outline_rounded,
              title: 'No Friends Added Yet',
              description: 'Add friends by email to split non-group expenses and track 1-on-1 debts.',
              buttonLabel: 'Add a Friend',
              onButtonPressed: () => _showAddFriendDialog(context),
            ),
          )
        else
          ..._friends.map(
            (fr) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => widget.onFriendTap(fr),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        UserAvatar(name: fr.name, size: 46),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fr.name,
                                style: AppTypography.titleMedium(isDark).copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                fr.email,
                                style: AppTypography.bodyMedium(isDark).copyWith(
                                  fontSize: 12,
                                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        DebtIndicatorBadge(
                          netAmount: fr.netBalance,
                          currency: fr.currency,
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
