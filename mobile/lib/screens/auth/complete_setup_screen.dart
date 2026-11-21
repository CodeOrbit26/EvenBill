import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons/primary_button.dart';
import '../../core/widgets/inputs/app_text_field.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/widgets/logo/evenbill_logo.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/network/api_client.dart';

class CompleteSetupScreen extends ConsumerStatefulWidget {
  final VoidCallback onSetupComplete;

  const CompleteSetupScreen({
    super.key,
    required this.onSetupComplete,
  });

  @override
  ConsumerState<CompleteSetupScreen> createState() => _CompleteSetupScreenState();
}

class _CompleteSetupScreenState extends ConsumerState<CompleteSetupScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider).user;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _phoneController = TextEditingController(text: user?.phoneNumber ?? '');
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
      await ref.read(authProvider.notifier).setPassword(
            password: password,
            phoneNumber: phone.isNotEmpty ? phone : null,
            fullName: name.isNotEmpty ? name : null,
          );

      if (mounted) {
        setState(() => _isLoading = false);
        AppSnackbar.showSuccess(
          context,
          'Password & direct login credentials saved!',
        );
        widget.onSetupComplete();
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
    ref.read(authProvider.notifier).skipSetup();
    widget.onSetupComplete();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = ref.watch(authProvider).user;
    final email = user?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account Setup'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _handleSkip,
            child: Text(
              'Skip',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EvenBillLogo(size: 38, showWordmark: true),
              const SizedBox(height: AppSpacing.md),

              Text(
                'Set Direct Login Password',
                style: AppTypography.displayMedium(isDark),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Create a password so you can sign in by typing your email/phone directly anytime without Google.',
                style: AppTypography.bodyMedium(isDark),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Fetched Google Email Box (Read-Only)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : const Color(0xFFF3F4F6),
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
                            email,
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

              // Username / Full Name
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

              // Direct Login Password
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
                'Next time, you can type this email or phone number with your password to log in instantly.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              PrimaryButton(
                label: 'Save Password & Enter App',
                onPressed: _handleSave,
                isLoading: _isLoading,
                icon: Icons.check_circle_outline_rounded,
              ),
              const SizedBox(height: AppSpacing.sm),

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
      ),
    );
  }
}

