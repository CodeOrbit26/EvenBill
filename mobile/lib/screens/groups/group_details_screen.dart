import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/avatars/user_avatar.dart';
import '../../core/widgets/avatars/group_avatar.dart';
import '../../core/widgets/financial/debt_indicator_badge.dart';
import '../../core/widgets/financial/expense_row.dart';
import '../../core/widgets/financial/amount_display.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/widgets/feedback/empty_state_view.dart';
import '../../core/widgets/feedback/error_state_view.dart';
import '../../core/widgets/inputs/app_text_field.dart';
import '../../core/di/injection.dart';
import '../../core/models/group_model.dart';
import '../../core/models/expense_model.dart';
import '../../core/models/group_invitation_model.dart';
import '../../core/network/api_client.dart';
import '../expenses/split_preset_picker_modal.dart';

class GroupDetailsScreen extends StatefulWidget {
  final GroupModel group;
  final VoidCallback onAddExpense;
  final Function(ExpenseModel) onExpenseTap;
  final Function(String debtorId, String debtorName, String creditorId, String creditorName, double amount, String currency)? onSettleDebt;
  final VoidCallback onBack;

  const GroupDetailsScreen({
    super.key,
    required this.group,
    required this.onAddExpense,
    required this.onExpenseTap,
    this.onSettleDebt,
    required this.onBack,
  });

  @override
  State<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends State<GroupDetailsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  String? _errorMessage;
  GroupDetailModel? _groupDetail;
  List<ExpenseModel> _expenses = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final detailFuture = Injection.groupRepository.getGroupDetails(widget.group.id);
      final expensesFuture = Injection.expenseRepository.listGroupExpenses(widget.group.id);

      final results = await Future.wait([detailFuture, expensesFuture]);
      if (mounted) {
        setState(() {
          _groupDetail = results[0] as GroupDetailModel;
          _expenses = results[1] as List<ExpenseModel>;
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

  void _showAddMemberSheet(BuildContext context) {
    final nameController = TextEditingController();
    final contactController = TextEditingController();
    bool isAdding = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.roundedTopSheet),
      builder: (ctx) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final isDark = Theme.of(sheetContext).brightness == Brightness.dark;

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 24,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Add Member to ${widget.group.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleLarge(isDark),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  Text(
                    'Add someone directly by name so you can split bills and record settlements right away.',
                    style: AppTypography.bodyMedium(isDark).copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    label: 'Member Name',
                    hintText: 'e.g. Rahul Sharma',
                    controller: nameController,
                    prefixIcon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppTextField(
                    label: 'Email or Phone (Optional)',
                    hintText: 'rahul@email.com or +91 98...',
                    controller: contactController,
                    prefixIcon: Icons.alternate_email_rounded,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                        foregroundColor: isDark ? AppColors.darkBackground : Colors.white,
                      ),
                      icon: isAdding
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.person_add_rounded, size: 18),
                      label: Text(
                        isAdding ? 'Adding...' : 'Add to Group',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      onPressed: isAdding
                          ? null
                          : () async {
                              final name = nameController.text.trim();
                              if (name.isEmpty) {
                                AppSnackbar.showError(sheetContext, 'Please enter the member\'s name');
                                return;
                              }
                              final contact = contactController.text.trim();
                              final isEmail = contact.contains('@');

                              setSheetState(() => isAdding = true);
                              try {
                                final added = await Injection.groupRepository.addGroupMember(
                                  groupId: widget.group.id,
                                  fullName: name,
                                  email: isEmail ? contact : null,
                                  phoneNumber: (!isEmail && contact.isNotEmpty) ? contact : null,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                await _loadData();
                                if (mounted) {
                                  AppSnackbar.showSuccess(
                                    context,
                                    '${added.fullName} added to ${widget.group.name}!',
                                  );
                                }
                              } catch (e) {
                                setSheetState(() => isAdding = false);
                                if (e is ApiException && e.statusCode == 409) {
                                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                                  await _loadData();
                                  if (mounted) {
                                    AppSnackbar.showWarning(
                                      context,
                                      'This member is already in the group or was added concurrently. Refreshing...',
                                    );
                                  }
                                } else {
                                  if (sheetContext.mounted) {
                                    AppSnackbar.showError(sheetContext, e.toString());
                                  }
                                }
                              }
                            },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Center(
                    child: TextButton.icon(
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: const Text('Or share invite code / send email invite'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _showInviteSheet(context);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showInviteSheet(BuildContext context) {
    final emailController = TextEditingController();
    bool isInviting = false;
    List<GroupInvitationModel> invitations = [];
    bool loadingInvites = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.roundedTopSheet),
      builder: (ctx) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
          final inviteLink = 'https://evenbill.app/join/${widget.group.inviteCode}';

          if (loadingInvites) {
            Injection.groupRepository.listInvitations(widget.group.id).then((invs) {
              if (sheetContext.mounted) {
                setSheetState(() {
                  invitations = invs;
                  loadingInvites = false;
                });
              }
            }).catchError((_) {
              if (sheetContext.mounted) {
                setSheetState(() => loadingInvites = false);
              }
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 24,
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Invite to ${widget.group.name}', style: AppTypography.titleLarge(isDark)),
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Shareable Link Section
                  Card(
                    color: isDark ? AppColors.darkCard : AppColors.lightCardSubtle,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.link_rounded, color: isDark ? AppColors.mintAccent : AppColors.forestGreen),
                              const SizedBox(width: 8),
                              const Text('Shareable Group Invite Link', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            inviteLink,
                            style: const TextStyle(fontSize: 12, color: Colors.grey, fontFamily: 'monospace'),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                                icon: const Icon(Icons.copy_rounded, size: 16),
                                label: const Text('Copy Link', style: TextStyle(fontSize: 12)),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: inviteLink));
                                  AppSnackbar.showSuccess(sheetContext, 'Shareable invite link copied to clipboard!');
                                },
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                                icon: const Icon(Icons.vpn_key_rounded, size: 16),
                                label: Text('Code: ${widget.group.inviteCode}', style: const TextStyle(fontSize: 12)),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: widget.group.inviteCode));
                                  AppSnackbar.showSuccess(sheetContext, 'Invite code copied!');
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Send Direct Email Invite
                  Text('Or Send Email Invitation', style: AppTypography.labelLarge(isDark).copyWith(fontSize: 13)),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          label: 'Friend\'s Email',
                          hintText: 'alex@example.com',
                          controller: emailController,
                          prefixIcon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: ElevatedButton(
                          onPressed: isInviting
                              ? null
                              : () async {
                                  final email = emailController.text.trim();
                                  if (email.isEmpty || !email.contains('@')) {
                                    AppSnackbar.showError(sheetContext, 'Please enter a valid email address');
                                    return;
                                  }

                                  setSheetState(() => isInviting = true);
                                  try {
                                    final inv = await Injection.groupRepository.createInvitation(
                                      groupId: widget.group.id,
                                      email: email,
                                    );
                                    emailController.clear();
                                    setSheetState(() {
                                      invitations.insert(0, inv);
                                      isInviting = false;
                                    });
                                    if (sheetContext.mounted) {
                                      AppSnackbar.showSuccess(sheetContext, 'Invitation sent to $email!');
                                    }
                                  } catch (e) {
                                    setSheetState(() => isInviting = false);
                                    if (sheetContext.mounted) {
                                      AppSnackbar.showError(sheetContext, 'Failed to send invite: $e');
                                    }
                                  }
                                },
                          child: isInviting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Send'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Active / Pending Invitations List
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Sent Invitations (${invitations.length})', style: AppTypography.labelLarge(isDark)),
                      if (loadingInvites)
                        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),

                  if (!loadingInvites && invitations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12.0),
                      child: Text('No invitations pending.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    )
                  else
                    ...invitations.map((inv) {
                      Color statusColor = Colors.orange;
                      if (inv.isAccepted) statusColor = AppColors.positiveGreen;
                      if (inv.isExpired) statusColor = Colors.grey;
                      if (inv.isRevoked) statusColor = AppColors.negativeRed;

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          inv.isAccepted
                              ? Icons.check_circle_rounded
                              : (inv.isExpired || inv.isRevoked ? Icons.cancel_outlined : Icons.hourglass_top_rounded),
                          color: statusColor,
                          size: 20,
                        ),
                        title: Text(inv.email, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Text(
                          'Status: ${inv.status} • Expires: ${inv.expiresAt.toIso8601String().substring(0, 10)}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        trailing: inv.isPending
                            ? TextButton(
                                style: TextButton.styleFrom(foregroundColor: AppColors.negativeRed),
                                onPressed: () {
                                  _confirmRevokeInvitation(sheetContext, inv, () {
                                    setSheetState(() {
                                      final idx = invitations.indexWhere((i) => i.id == inv.id);
                                      if (idx >= 0) {
                                        invitations[idx] = inv.copyWith(status: 'REVOKED');
                                      }
                                    });
                                  });
                                },
                                child: const Text('Revoke', style: TextStyle(fontSize: 11)),
                              )
                            : null,
                      );
                    }),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmRevokeInvitation(BuildContext context, GroupInvitationModel inv, VoidCallback onSuccess) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke Invitation?'),
        content: Text('Are you sure you want to cancel the invitation for ${inv.email}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.negativeRed),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Injection.groupRepository.revokeInvitation(inv.id);
                AppSnackbar.showSuccess(context, 'Invitation for ${inv.email} revoked.');
                onSuccess();
              } catch (e) {
                AppSnackbar.showError(context, 'Failed to revoke: $e');
              }
            },
            child: const Text('Revoke', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showGroupOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.roundedTopSheet),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit Group Details'),
              onTap: () {
                Navigator.pop(ctx);
                _showEditGroupDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded, color: AppColors.secondaryEvergreen),
              title: const Text('Saved Split Presets (Pro)'),
              subtitle: const Text('Configure default group split templates'),
              onTap: () {
                Navigator.pop(ctx);
                _showSplitPresetsSheet(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.negativeRed),
              title: const Text('Archive / Delete Group', style: TextStyle(color: AppColors.negativeRed)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteGroup(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSplitPresetsSheet(BuildContext context) {
    final membersList = (_groupDetail?.members ?? []).map((m) {
      return {'id': m.userId, 'name': m.fullName};
    }).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SplitPresetPickerModal(
        groupId: widget.group.id,
        members: membersList,
        onTemplateSelected: (tmpl) {
          AppSnackbar.showSuccess(context, 'Selected preset "${tmpl.name}" as default.');
        },
      ),
    );
  }

  void _showEditGroupDialog(BuildContext context) {
    final nameController = TextEditingController(text: widget.group.name);
    bool simplifyDebts = widget.group.simplifyDebts;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dCtx, setDState) => AlertDialog(
          title: const Text('Edit Group'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Group Name'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Simplify Debts', style: TextStyle(fontSize: 14)),
                value: simplifyDebts,
                onChanged: (val) => setDState(() => simplifyDebts = val),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                try {
                  await Injection.groupRepository.updateGroup(
                    groupId: widget.group.id,
                    name: name,
                    simplifyDebts: simplifyDebts,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  AppSnackbar.showSuccess(context, 'Group updated!');
                  _loadData();
                } catch (e) {
                  AppSnackbar.showError(ctx, 'Failed to update: $e');
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteGroup(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group?'),
        content: Text('Are you sure you want to archive "${widget.group.name}"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.negativeRed),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await Injection.groupRepository.deleteGroup(widget.group.id);
                if (context.mounted) {
                  AppSnackbar.showSuccess(context, 'Group "${widget.group.name}" archived.');
                  widget.onBack();
                }
              } catch (e) {
                AppSnackbar.showError(context, 'Failed to delete group: $e');
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: Text(widget.group.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            tooltip: 'Add Member',
            onPressed: () => _showAddMemberSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.link_rounded),
            tooltip: 'Invite Members',
            onPressed: () => _showInviteSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => _showGroupOptions(context),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: isDark ? AppColors.mintAccent : AppColors.forestGreen,
          unselectedLabelColor: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
          indicatorColor: isDark ? AppColors.mintAccent : AppColors.forestGreen,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Expenses'),
            Tab(text: 'Balances'),
            Tab(text: 'Members'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: ErrorStateView(
                      title: 'Error Loading Group',
                      message: _errorMessage!,
                      onRetry: _loadData,
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildExpensesTab(isDark),
                    _buildBalancesTab(isDark),
                    _buildMembersTab(isDark),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: isDark ? AppColors.mintAccent : AppColors.forestGreen,
        foregroundColor: isDark ? AppColors.darkBackground : Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Expense', style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: widget.onAddExpense,
      ),
    );
  }

  Widget _buildExpensesTab(bool isDark) {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
      child: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          // Elevated Group Summary Card
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(16),
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
                  children: [
                    GroupAvatar(groupType: widget.group.type, size: 52),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.group.name,
                            style: AppTypography.titleLarge(isDark).copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  widget.group.type,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '• Base ${widget.group.currency}',
                                style: AppTypography.bodyMedium(isDark).copyWith(fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    DebtIndicatorBadge(
                      netAmount: widget.group.netBalance,
                      currency: widget.group.currency,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: widget.group.inviteCode));
                        HapticFeedback.lightImpact();
                        AppSnackbar.showSuccess(context, 'Invite code ${widget.group.inviteCode} copied!');
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded, size: 13, color: isDark ? AppColors.mintAccent : AppColors.forestGreen),
                            const SizedBox(width: 6),
                            Text(
                              'Code: ${widget.group.inviteCode}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _showAddMemberSheet(context),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_add_rounded, size: 13, color: isDark ? AppColors.mintAccent : AppColors.forestGreen),
                            const SizedBox(width: 5),
                            Text(
                              '${_groupDetail?.members.length ?? widget.group.memberCount} members • + Add',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Group Expenses (${_expenses.length})', style: AppTypography.labelLarge(isDark)),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add', style: TextStyle(fontSize: 12)),
                onPressed: widget.onAddExpense,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          if (_expenses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36.0),
              child: EmptyStateView(
                icon: Icons.receipt_long_outlined,
                title: 'No Expenses Recorded',
                description: 'Start tracking shared bills for ${widget.group.name}.',
                buttonLabel: 'Add First Group Expense',
                onButtonPressed: widget.onAddExpense,
              ),
            )
          else
            ..._expenses.map(
              (exp) => ExpenseRow(
                description: exp.description,
                category: exp.category,
                groupName: widget.group.name,
                dateFormatted: exp.dateFormatted,
                payerText: exp.paidBy,
                netShare: exp.yourNetShare,
                currency: exp.currency,
                onTap: () => widget.onExpenseTap(exp),
              ),
            ),
          const SizedBox(height: 70), // Spacing for FAB
        ],
      ),
    );
  }

  Widget _buildBalancesTab(bool isDark) {
    final simplified = _groupDetail?.simplifiedDebts ?? [];
    final bilateral = _groupDetail?.bilateralDebts ?? [];

    return RefreshIndicator(
      onRefresh: _loadData,
      color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
      child: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          Card(
            color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.auto_graph_rounded, color: isDark ? AppColors.mintAccent : AppColors.forestGreen),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.group.simplifyDebts ? 'Debt Simplification Active' : 'Standard Bilateral Debts',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                          ),
                        ),
                        Text(
                          widget.group.simplifyDebts
                              ? 'Transactions minimized mathematically to resolve all debts with fewest cash transfers.'
                              : 'Pairwise individual member balances without graph netting.',
                          style: AppTypography.bodyMedium(isDark).copyWith(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          Text(
            widget.group.simplifyDebts
                ? 'Suggested Simplified Transfers (${simplified.length})'
                : 'Bilateral Debts (${bilateral.length})',
            style: AppTypography.labelLarge(isDark),
          ),
          const SizedBox(height: AppSpacing.xs),

          if (widget.group.simplifyDebts) ...[
            if (simplified.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36.0),
                child: Center(
                  child: Text('All group debts are completely settled!', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              ...simplified.map(
                (transfer) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        UserAvatar(name: transfer.debtorName, size: 36),
                        const SizedBox(width: 6),
                        const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
                        const SizedBox(width: 6),
                        UserAvatar(name: transfer.creditorName, size: 36),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${transfer.debtorName} pays ${transfer.creditorName}',
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                              ),
                              AmountDisplay(
                                amount: transfer.amount,
                                currency: transfer.currency,
                              ),

                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          onPressed: () {
                            if (widget.onSettleDebt != null) {
                              widget.onSettleDebt!(
                                transfer.debtorId,
                                transfer.debtorName,
                                transfer.creditorId,
                                transfer.creditorName,
                                transfer.amount,
                                transfer.currency,
                              );
                            }
                          },
                          child: const Text('Settle', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ] else ...[
            if (bilateral.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 36.0),
                child: Center(
                  child: Text('No outstanding bilateral debts.', style: TextStyle(color: Colors.grey)),
                ),
              )
            else
              ...bilateral.map(
                (b) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: UserAvatar(name: b.debtorName, size: 36),
                    title: Text('${b.debtorName} owes ${b.creditorName}'),
                    trailing: AmountDisplay(amount: b.amount, currency: b.currency),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 70),
        ],
      ),
    );
  }

  Widget _buildMembersTab(bool isDark) {
    final members = _groupDetail?.members ?? [];
    final netBalances = _groupDetail?.netBalances ?? [];

    return RefreshIndicator(
      onRefresh: _loadData,
      color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
      child: ListView(
        padding: AppSpacing.screenPadding,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Group Members (${members.length})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.labelLarge(isDark),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.link_rounded, size: 15),
                label: const Text('Invite', style: TextStyle(fontSize: 12)),
                onPressed: () => _showInviteSheet(context),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => _showAddMemberSheet(context),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_add_rounded,
                        size: 14,
                        color: isDark ? AppColors.darkBackground : Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Add',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.darkBackground : Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),

          ...members.map((m) {
            final netBal = netBalances.firstWhere(
              (nb) => nb.userId == m.userId,
              orElse: () => NetBalanceModel(userId: m.userId, fullName: m.fullName, netBalance: 0.0, currency: widget.group.currency),
            );
            final displayContact = m.email.endsWith('@member.evenbill.local')
                ? 'Added directly'
                : m.email;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: UserAvatar(name: m.fullName),
                title: Text(m.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${m.role} • $displayContact',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                trailing: DebtIndicatorBadge(
                  netAmount: netBal.netBalance,
                  currency: netBal.currency,
                ),
              ),
            );
          }),
          const SizedBox(height: 70),
        ],
      ),
    );
  }
}
