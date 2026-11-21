import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/avatars/group_avatar.dart';
import '../../core/widgets/financial/debt_indicator_badge.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/widgets/feedback/loading_skeleton.dart';
import '../../core/widgets/feedback/empty_state_view.dart';
import '../../core/widgets/feedback/error_state_view.dart';
import '../../core/widgets/inputs/app_text_field.dart';
import '../../core/di/injection.dart';
import '../../core/models/group_model.dart';
import '../../core/network/api_client.dart';
import 'create_group_bottom_sheet.dart';

class GroupsListScreen extends StatefulWidget {
  final Function(GroupModel) onGroupTap;
  final VoidCallback? onCreateGroup;
  final String? defaultCurrency;
  final VoidCallback? onActivityTap;

  const GroupsListScreen({
    super.key,
    required this.onGroupTap,
    this.onCreateGroup,
    this.defaultCurrency,
    this.onActivityTap,
  });

  @override
  State<GroupsListScreen> createState() => _GroupsListScreenState();
}

class _GroupsListScreenState extends State<GroupsListScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<GroupModel> _groups = [];

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final groups = await Injection.groupRepository.listGroups();
      if (mounted) {
        setState(() {
          _groups = groups;
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

  void _showCreateGroupModal(BuildContext context) {
    showCreateGroupModal(
      context: context,
      defaultCurrency: widget.defaultCurrency,
      onGroupCreated: (newGroup) {
        _loadGroups();
        widget.onGroupTap(newGroup);
      },
    );
  }

  void _showJoinGroupDialog(BuildContext context) {
    final controller = TextEditingController();
    bool isJoining = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.vpn_key_rounded, size: 22),
              SizedBox(width: 8),
              Text('Join with Invite Code'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the 8-character invite code shared by the group creator.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 1.5, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'e.g. APT404EB',
                  prefixIcon: const Icon(Icons.qr_code_2_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isJoining
                  ? null
                  : () async {
                      final code = controller.text.trim();
                      if (code.isEmpty) {
                        AppSnackbar.showError(ctx, 'Please enter an invite code');
                        return;
                      }

                      setDialogState(() => isJoining = true);
                      try {
                        final group = await Injection.groupRepository.joinGroupByCode(code);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          AppSnackbar.showSuccess(context, 'Successfully joined ${group.name}!');
                          _loadGroups();
                          widget.onGroupTap(group);
                        }
                      } catch (e) {
                        setDialogState(() => isJoining = false);
                        if (e is ApiException && e.statusCode == 409) {
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            AppSnackbar.showWarning(
                              context,
                              'You are already a member or this invite code was already claimed. Refreshing groups...',
                            );
                            _loadGroups();
                          }
                        } else {
                          if (ctx.mounted) {
                            AppSnackbar.showError(ctx, 'Failed to join group: $e');
                          }
                        }
                      }
                    },
              child: isJoining
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Join Group'),
            ),
          ],
        ),
      ),
    );
  }

  void _copyInviteCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.lightImpact();
    AppSnackbar.showSuccess(context, 'Invite code $code copied to clipboard!');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          if (widget.onActivityTap != null)
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Activity',
              onPressed: widget.onActivityTap,
            ),
          IconButton(
            icon: const Icon(Icons.group_add_outlined),
            tooltip: 'Create Group',
            onPressed: () => _showCreateGroupModal(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadGroups,
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
            title: 'Could Not Load Groups',
            message: _errorMessage!,
            onRetry: _loadGroups,
          ),
        ),
      );
    }

    return ListView(
      padding: AppSpacing.screenPadding,
      children: [
        // Frosted Info banner for invite code
        Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCardSubtle,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm + 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Have an invite code?',
                        style: AppTypography.titleMedium(isDark).copyWith(fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Join an existing group with friends',
                        style: AppTypography.bodyMedium(isDark).copyWith(fontSize: 12),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    side: BorderSide(
                      color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                    ),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => _showJoinGroupDialog(context),
                  child: Text(
                    'Join',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Active Groups (${_groups.length})', style: AppTypography.labelLarge(isDark)),
            TextButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Group', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              onPressed: () => _showCreateGroupModal(context),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),

        if (_groups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32.0),
            child: EmptyStateView(
              icon: Icons.group_work_outlined,
              title: 'No Groups Yet',
              description: 'Create a group for an upcoming trip, shared apartment, or event to start splitting bills.',
              buttonLabel: 'Create Your First Group',
              onButtonPressed: () => _showCreateGroupModal(context),
            ),
          )
        else
          ..._groups.map(
            (grp) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => widget.onGroupTap(grp),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            GroupAvatar(groupType: grp.type, size: 48),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    grp.name,
                                    style: AppTypography.titleMedium(isDark).copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          grp.type,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '• ${grp.memberCount} ${grp.memberCount == 1 ? "member" : "members"}',
                                        style: AppTypography.bodyMedium(isDark).copyWith(fontSize: 11),
                                      ),
                                    ],
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
                        const SizedBox(height: 10),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            InkWell(
                              onTap: () => _copyInviteCode(grp.inviteCode),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkCardSubtle : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.copy_rounded,
                                      size: 13,
                                      color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      'Code: ${grp.inviteCode}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Text(
                                  'Base: ${grp.currency}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  size: 16,
                                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _showCreateGroupModal(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard.withOpacity(0.6) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? AppColors.mintAccent.withOpacity(0.35)
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
    );
  }
}
