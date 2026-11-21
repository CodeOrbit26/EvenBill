import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons/primary_button.dart';
import '../../core/widgets/inputs/app_text_field.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/models/user_model.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/di/injection.dart';
import '../../core/network/api_client.dart';

Future<void> showCompleteSetupModal(
  BuildContext context, {
  required UserModel user,
  required VoidCallback onComplete,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (ctx) => _CompleteSetupSheet(user: user, onComplete: onComplete),
  );
}

class _CompleteSetupSheet extends ConsumerStatefulWidget {
  final UserModel user;
  final VoidCallback onComplete;

  const _CompleteSetupSheet({
    required this.user,
    required this.onComplete,
  });

  @override
  ConsumerState<_CompleteSetupSheet> createState() => _CompleteSetupSheetState();
}

class _CompleteSetupSheetState extends ConsumerState<_CompleteSetupSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.user.fullName);
    _phoneController = TextEditingController(text: widget.user.phoneNumber ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final password = _passwordController.text;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();

    if (password.length < 8) {
      AppSnackbar.showError(
        context,
        'Please enter a password with at least 8 characters.',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      try {
        await ref.read(authProvider.notifier).setPassword(
              password: password,
              phoneNumber: phone.isNotEmpty ? phone : null,
              fullName: name.isNotEmpty ? name : null,
            );
      } catch (e) {
        if (e.toString().contains('ProviderScope')) {
          await Injection.authRepository.setPassword(
            password: password,
            phoneNumber: phone.isNotEmpty ? phone : null,
            fullName: name.isNotEmpty ? name : null,
          );
        } else {
          rethrow;
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.of(context).pop();
        AppSnackbar.showSuccess(
          context,
          'Password & direct login credentials saved!',
        );
        widget.onComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final msg = e is ApiException ? e.message : e.toString();
        AppSnackbar.showError(context, 'Failed to save setup: $msg');
      }
    }
  }

  void _handleSkip() {
    Navigator.of(context).pop();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: 24 + bottomInset,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBackground : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.forestGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    color: AppColors.forestGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Set Direct Login Password',
                        style: AppTypography.displayMedium(isDark).copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Log in with Google OR by typing email/password',
                        style: AppTypography.bodySmall(isDark).copyWith(
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            // Fetched Email Box (Read-Only)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.darkCard
                    : const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.mark_email_read_rounded,
                    color: AppColors.forestGreen,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Google Account (Fetched)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.user.email,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 18,
                    color: AppColors.forestGreen,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            // Name / Username
            AppTextField(
              label: 'Username / Full Name',
              hintText: 'Your name',
              controller: _nameController,
              prefixIcon: Icons.person_outline_rounded,
            ),
            const SizedBox(height: AppSpacing.md),

            // Phone Number
            AppTextField(
              label: 'Phone Number (Optional)',
              hintText: '+1 234 567 8900 or 9876543210',
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              prefixIcon: Icons.phone_outlined,
            ),
            const SizedBox(height: AppSpacing.md),

            // Password Field
            AppTextField(
              label: 'Create Direct Login Password',
              hintText: 'At least 8 characters',
              controller: _passwordController,
              obscureText: _obscurePassword,
              prefixIcon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),

            Text(
              'Setting a password lets you type in your email or phone number with this password to sign in anytime without Google.',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            PrimaryButton(
              label: 'Save Password & Enter App',
              onPressed: _handleSave,
              isLoading: _isLoading,
              icon: Icons.check_circle_outline_rounded,
            ),
            const SizedBox(height: AppSpacing.xs),

            Center(
              child: TextButton(
                onPressed: _isLoading ? null : _handleSkip,
                child: Text(
                  'Skip for Now',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
