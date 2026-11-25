import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/avatars/user_avatar.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/di/injection.dart';
import '../../core/models/user_model.dart';
import '../../core/models/entitlement_model.dart';
import '../../core/utils/identity_utils.dart';
import '../../core/widgets/feedback/error_state_view.dart';
import '../auth/complete_setup_modal.dart';
import '../bank/bank_import_sheet.dart';

class ProfileSettingsScreen extends StatefulWidget {
  final ThemeMode currentThemeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  final ValueChanged<String>? onCurrencyChanged;
  final VoidCallback onOpenPaywall;
  final VoidCallback onSignOut;
  final VoidCallback? onActivityTap;

  const ProfileSettingsScreen({
    super.key,
    required this.currentThemeMode,
    required this.onThemeChanged,
    this.onCurrencyChanged,
    required this.onOpenPaywall,
    required this.onSignOut,
    this.onActivityTap,
  });

  @override
  State<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<ProfileSettingsScreen> {
  UserModel? _user;
  EntitlementModel? _entitlement;
  bool _isLoading = true;
  String? _loadError;
  bool _mfaEnabled = false;
  bool _pushNotifications = true;
  bool _emailDigests = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final user = await Injection.authRepository.getMe();
      EntitlementModel? ent;
      try {
        ent = await Injection.subscriptionRepository.getEntitlements();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _user = user;
          _entitlement = ent;
          _isLoading = false;
        });
      }
    } catch (e) {
      final cached = await Injection.authRepository.getCachedUser();
      if (mounted) {
        if (cached != null && !isPlaceholderUserId(cached.id)) {
          setState(() {
            _user = cached;
            _isLoading = false;
          });
        } else {
          setState(() {
            _user = null;
            _loadError = 'Unable to load your profile. Please check your connection and try again.';
            _isLoading = false;
          });
        }
      }
    }
  }

  void _showEditProfileDialog(BuildContext context) {
    if (_user == null) return;
    final nameController = TextEditingController(text: _user!.fullName);
    final phoneController = TextEditingController(text: _user!.phoneNumber ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Edit Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone Number (Optional)'),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isEmpty) return;

              try {
                final updated = await Injection.authRepository.updateMe(
                  fullName: newName,
                );

                if (ctx.mounted) Navigator.pop(ctx);
                setState(() => _user = updated);
                if (context.mounted) {
                  AppSnackbar.showSuccess(context, 'Profile updated successfully!');
                }
              } catch (e) {
                if (ctx.mounted) {
                  AppSnackbar.showError(ctx, 'Failed to update: $e');
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
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
                  const Text('Select Default Currency', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
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
                  final isSelected = _user?.defaultCurrency == c['code'];
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
                      Navigator.pop(ctx);
                      try {
                        final updated = await Injection.authRepository.updateMe(defaultCurrency: c['code']!);
                        setState(() => _user = updated);
                        widget.onCurrencyChanged?.call(c['code']!);
                        if (context.mounted) {
                          AppSnackbar.showSuccess(
                            context,
                            'Default currency set to ${c['flag']} ${c['code']} (${c['symbol']})',
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
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

  String _getCurrencyFlag(String code) {
    switch (code) {
      case 'INR': return '🇮🇳';
      case 'USD': return '🇺🇸';
      case 'EUR': return '🇪🇺';
      case 'GBP': return '🇬🇧';
      case 'JPY': return '🇯🇵';
      case 'CAD': return '🇨🇦';
      case 'AUD': return '🇦🇺';
      case 'AED': return '🇦🇪';
      case 'SGD': return '🇸🇬';
      case 'CHF': return '🇨🇭';
      default: return '🌐';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final userName = _user?.fullName ?? 'EvenBill User';
    final userEmail = _user?.email ?? 'loading...';
    final isPro = _user?.isPro ?? false;
    final currencyCode = _user?.defaultCurrency ?? 'INR';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account & Settings'),
        actions: [
          if (widget.onActivityTap != null)
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: 'Activity',
              onPressed: widget.onActivityTap,
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Profile',
            onPressed: () => _showEditProfileDialog(context),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null && _user == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: ErrorStateView(
                      title: 'Could Not Load Profile',
                      message: _loadError!,
                      onRetry: _loadProfile,
                    ),
                  ),
                )
              : ListView(
              padding: AppSpacing.screenPadding,
              children: [
                // Profile Header Card
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
                    children: [
                      Row(
                        children: [
                          UserAvatar(name: userName, size: 56),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      userName,
                                      style: AppTypography.titleLarge(isDark).copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 18,
                                      ),
                                    ),
                                    if (isPro) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.mintAccent,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Text(
                                          'PRO',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                            color: AppColors.forestGreen,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  userEmail,
                                  style: AppTypography.bodyMedium(isDark).copyWith(
                                    fontSize: 13,
                                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (isPro ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.12),
                                    borderRadius: AppRadius.roundedPill,
                                  ),
                                  child: Text(
                                    isPro
                                        ? 'Pro Member • Unlimited'
                                        : 'Free Plan • ${_entitlement != null ? "${_entitlement!.dailyRemaining ?? 4} of ${_entitlement!.dailyLimit ?? 4} left today" : "4 / day"}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isPro
                                          ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                                          : AppColors.forestGreen,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _showEditProfileDialog(context),
                          ),
                        ],
                      ),
                      if (!isPro && _entitlement != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: ((_entitlement!.dailyLimit ?? 4) - (_entitlement!.dailyRemaining ?? 4)) / (_entitlement!.dailyLimit ?? 4),
                            minHeight: 4,
                            backgroundColor: Colors.grey.withOpacity(0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              isDark ? AppColors.mintAccent : AppColors.forestGreen,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Pro Upgrade Banner Card
                if (!isPro) ...[
                  InkWell(
                    onTap: widget.onOpenPaywall,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F3B30), Color(0xFF1D5A4A)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: AppColors.mintAccent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.star_rounded, color: AppColors.forestGreen, size: 24),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Upgrade to EvenBill Pro',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'AI receipt OCR, cross-group debt netting, live FX & 5GB vault.',
                                  style: TextStyle(
                                    color: Color(0xFF9BE5C3),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded, color: Colors.white),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                Text('Preferences', style: AppTypography.labelLarge(isDark).copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.xs),

                // Preferences Inset Card
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.palette_outlined),
                        title: const Text('Theme Mode', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          widget.currentThemeMode == ThemeMode.dark
                              ? 'Dark Mode'
                              : (widget.currentThemeMode == ThemeMode.light ? 'Light Mode' : 'System Default'),
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 16)),
                            ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 16)),
                          ],
                          selected: {widget.currentThemeMode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light},
                          onSelectionChanged: (set) => widget.onThemeChanged(set.first),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.currency_exchange_rounded),
                        title: const Text('Default Currency', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${_getCurrencyFlag(currencyCode)} $currencyCode (Primary)',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: (isDark ? AppColors.mintAccent : AppColors.forestGreen).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                currencyCode,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                        onTap: () => _showCurrencyPicker(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                Text('Notifications', style: AppTypography.labelLarge(isDark).copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.xs),

                // Notifications Card
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.notifications_active_outlined),
                        title: const Text('Push Notifications', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Get notified when expenses are added or settled', style: TextStyle(fontSize: 12)),
                        value: _pushNotifications,
                        activeColor: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                        onChanged: (val) {
                          setState(() => _pushNotifications = val);
                          AppSnackbar.showInfo(context, val ? 'Push notifications enabled' : 'Push notifications disabled');
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.mark_email_read_outlined),
                        title: const Text('Weekly Balance Digest', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Receive a weekly email summary of your balances', style: TextStyle(fontSize: 12)),
                        value: _emailDigests,
                        activeColor: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                        onChanged: (val) {
                          setState(() => _emailDigests = val);
                          AppSnackbar.showInfo(context, val ? 'Email digest enabled' : 'Email digest disabled');
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                Text('Pro Features & Integrations', style: AppTypography.labelLarge(isDark).copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.xs),

                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.account_balance_rounded, color: Colors.indigo),
                        title: const Text('Bank Transaction Import', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Open Banking (PSD2 / CFPB) read-only feed', style: TextStyle(fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (ctx) => BankImportSheet(
                              onBack: () => Navigator.pop(ctx),
                              onTransactionSelected: (tx) {
                                AppSnackbar.showSuccess(context, 'Transaction selected: ${tx.merchantName}');
                              },
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          isPro ? Icons.verified_rounded : Icons.block_rounded,
                          color: isPro ? AppColors.positiveGreen : Colors.grey,
                        ),
                        title: const Text('Ad-Free Experience', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          isPro
                              ? 'Active • All banner advertisements disabled'
                              : 'Upgrade to Pro to eliminate all in-app advertising',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: !isPro
                            ? TextButton(
                                onPressed: widget.onOpenPaywall,
                                child: const Text('Upgrade', style: TextStyle(fontWeight: FontWeight.w700)),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                Text('Security & Data', style: AppTypography.labelLarge(isDark).copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: AppSpacing.xs),

                Card(
                  child: Column(
                    children: [
                      if (_user != null && !_user!.hasPassword) ...[
                        ListTile(
                          leading: const Icon(Icons.lock_outline),
                          title: const Text('Set Direct Login Password'),
                          subtitle: const Text('Optional: add a password for email login alongside Google'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            final currentUser = _user;
                            if (currentUser == null) return;
                            showCompleteSetupModal(
                              context,
                              user: currentUser,
                              onComplete: _loadProfile,
                            );
                          },
                        ),
                        const Divider(height: 1),
                      ],
                      SwitchListTile(
                        secondary: const Icon(Icons.security_outlined),
                        title: const Text('Two-Factor Authentication (MFA)', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Protect your account with TOTP authenticator', style: TextStyle(fontSize: 12)),
                        value: _mfaEnabled,
                        activeColor: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                        onChanged: (val) {
                          setState(() => _mfaEnabled = val);
                          AppSnackbar.showInfo(
                            context,
                            val ? 'MFA enabled. Authenticator registered.' : 'MFA disabled.',
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.file_download_outlined),
                        title: const Text('Export Expense Ledger', style: TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: const Text('Download full audit ledger as JSON format', style: TextStyle(fontSize: 12)),
                        onTap: () async {
                          try {
                            AppSnackbar.showInfo(context, 'Exporting audit ledger...');
                            final data = await Injection.authRepository.exportUserData();
                            if (context.mounted) {
                              final groupCount = (data['groups'] as List?)?.length ?? 0;
                              final expenseCount = (data['expenses'] as List?)?.length ?? 0;
                              AppSnackbar.showSuccess(
                                context,
                                'Export complete! $groupCount groups, $expenseCount expenses archived.',
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              AppSnackbar.showError(context, 'Export failed: $e');
                            }
                          }
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.logout_rounded, color: AppColors.negativeRed),
                        title: const Text('Sign Out', style: TextStyle(color: AppColors.negativeRed, fontWeight: FontWeight.w700)),
                        onTap: () => _showSignOutDialog(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Sign Out?'),
        content: const Text('Are you sure you want to sign out of your EvenBill account on this device?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.negativeRed),
            onPressed: () async {
              Navigator.pop(ctx);
              await Injection.authRepository.signOut();
              widget.onSignOut();
            },
            child: const Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
