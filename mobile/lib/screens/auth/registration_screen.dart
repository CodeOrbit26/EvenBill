import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons/primary_button.dart';
import '../../core/widgets/buttons/social_auth_button.dart';
import '../../core/widgets/inputs/app_text_field.dart';
import '../../core/widgets/feedback/app_snackbar.dart';
import '../../core/widgets/logo/evenbill_logo.dart';
import '../../core/network/api_client.dart';
import '../../core/models/user_model.dart';
import '../../core/di/injection.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/services/google_auth_service.dart';

class RegistrationScreen extends ConsumerStatefulWidget {
  final VoidCallback onRegisterSuccess;
  final VoidCallback onNavigateToLogin;
  final VoidCallback onBack;

  const RegistrationScreen({
    super.key,
    required this.onRegisterSuccess,
    required this.onNavigateToLogin,
    required this.onBack,
  });

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  String _selectedCurrency = 'USD';
  bool _isLoading = false;
  bool _isSocialLoading = false;

  final List<String> _currencies = [
    'USD',
    'EUR',
    'GBP',
    'INR',
    'JPY',
    'CAD',
    'AUD',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || email.isEmpty || password.length < 8) {
      AppSnackbar.showError(
        context,
        'Please complete required fields (Password min 8 chars)',
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      UserModel user;
      try {
        user = await ref
            .read(authProvider.notifier)
            .register(
              email: email,
              password: password,
              fullName: name,
              phoneNumber: phone.isNotEmpty ? phone : null,
              defaultCurrency: _selectedCurrency,
            );
      } catch (e) {
        if (e.toString().contains('ProviderScope')) {
          user = await Injection.authRepository.register(
            email: email,
            password: password,
            fullName: name,
            phoneNumber: phone.isNotEmpty ? phone : null,
            defaultCurrency: _selectedCurrency,
          );
        } else {
          rethrow;
        }
      }
      if (mounted) {
        setState(() => _isLoading = false);
        AppSnackbar.showSuccess(
          context,
          'Account created! Welcome, ${user.fullName}!',
        );
        widget.onRegisterSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        String msg;
        if (e is ApiException) {
          if (e.isConnectionError) {
            msg = 'Unable to connect to EvenBill server. Please verify backend is running.';
          } else if (e.statusCode == 409) {
            msg = 'An account with this email already exists. Please sign in instead.';
          } else {
            msg = e.message;
          }
        } else {
          msg = e.toString();
        }
        AppSnackbar.showError(context, msg);
      }
    }
  }

  Future<void> _handleGoogleSignUp() async {
    setState(() => _isSocialLoading = true);
    try {
      final googleResult = await GoogleAuthService.signIn();
      if (googleResult == null) {
        // User dismissed or cancelled the Google prompt
        if (mounted) setState(() => _isSocialLoading = false);
        return;
      }

      UserModel user;
      try {
        user = await ref
            .read(authProvider.notifier)
            .loginWithOAuth(
              provider: 'google',
              idToken: googleResult.idToken,
              email: googleResult.email,
              fullName: googleResult.fullName,
              avatarUrl: googleResult.avatarUrl,
            );
      } catch (e) {
        if (e.toString().contains('ProviderScope')) {
          user = await Injection.authRepository.loginWithOAuth(
            provider: 'google',
            idToken: googleResult.idToken,
            email: googleResult.email,
            fullName: googleResult.fullName,
            avatarUrl: googleResult.avatarUrl,
          );
        } else {
          rethrow;
        }
      }
      if (mounted) {
        setState(() => _isSocialLoading = false);
        AppSnackbar.showSuccess(
          context,
          'Welcome to EvenBill, ${user.fullName}!',
        );
        widget.onRegisterSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSocialLoading = false);
        final msg = e is ApiException ? e.message : e.toString();
        AppSnackbar.showError(context, 'Google Sign Up failed: $msg');
      }
    }
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
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EvenBillLogo(size: 40, showWordmark: true),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Create Your Account',
                style: AppTypography.displayMedium(isDark),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Join EvenBill for effortless, transparent group finances.',
                style: AppTypography.bodyMedium(isDark),
              ),
              const SizedBox(height: AppSpacing.lg),

              AppTextField(
                label: 'Full Name',
                hintText: 'Jane Doe',
                controller: _nameController,
                prefixIcon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: AppSpacing.md),

              AppTextField(
                label: 'Email Address',
                hintText: 'name@example.com',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.email_outlined,
              ),
              const SizedBox(height: AppSpacing.md),

              AppTextField(
                label: 'Phone Number (Optional)',
                hintText: '+1 234 567 8900 or 9876543210',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                prefixIcon: Icons.phone_outlined,
              ),
              const SizedBox(height: AppSpacing.md),

              AppTextField(
                label: 'Password',
                hintText: 'At least 8 characters',
                controller: _passwordController,
                obscureText: true,
                prefixIcon: Icons.lock_outline_rounded,
              ),
              const SizedBox(height: AppSpacing.md),

              // Currency Selector
              Text('Default Currency', style: AppTypography.labelLarge(isDark)),
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                  color: isDark ? AppColors.darkCard : Colors.white,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCurrency,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    items: _currencies.map((curr) {
                      return DropdownMenuItem<String>(
                        value: curr,
                        child: Text(
                          curr,
                          style: AppTypography.bodyMedium(isDark)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCurrency = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              PrimaryButton(
                label: 'Create Account',
                onPressed: _handleRegister,
                isLoading: _isLoading,
                icon: Icons.arrow_forward_rounded,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Divider
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR SIGN UP WITH',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Social Sign-Up options
              GoogleSignInButton(
                onPressed: _handleGoogleSignUp,
                isLoading: _isSocialLoading,
                label: 'Sign up with Google',
              ),
              const SizedBox(height: AppSpacing.xl),

              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Already have an account?',
                      style: AppTypography.bodyMedium(isDark),
                    ),
                    TextButton(
                      onPressed: widget.onNavigateToLogin,
                      child: Text(
                        'Sign In',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? AppColors.mintAccent
                              : AppColors.forestGreen,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
