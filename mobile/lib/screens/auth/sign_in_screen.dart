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

class SignInScreen extends ConsumerStatefulWidget {
  final VoidCallback onSignInSuccess;
  final VoidCallback onNavigateToRegister;
  final VoidCallback onBack;
  final String? sessionExpiredMessage;

  const SignInScreen({
    super.key,
    required this.onSignInSuccess,
    required this.onNavigateToRegister,
    required this.onBack,
    this.sessionExpiredMessage,
  });

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isSocialLoading = false;
  bool _obscurePassword = true;
  bool _rememberEmail = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  Future<void> _loadRememberedEmail() async {
    try {
      final isRemembered = await Injection.tokenStorage.isRememberEmailEnabled();
      if (isRemembered) {
        final lastEmail = await Injection.tokenStorage.getLastEmail();
        if (lastEmail != null && lastEmail.isNotEmpty && mounted) {
          setState(() {
            _rememberEmail = true;
            _emailController.text = lastEmail;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignIn() async {
    final loginIdentifier = _emailController.text.trim();
    final password = _passwordController.text;

    if (loginIdentifier.isEmpty || password.isEmpty) {
      AppSnackbar.showError(context, 'Please enter your email or phone and password');
      return;
    }

    setState(() => _isLoading = true);
    try {
      UserModel user;
      try {
        user = await ref.read(authProvider.notifier).login(
              email: loginIdentifier,
              password: password,
            );
      } catch (e) {
        if (e.toString().contains('ProviderScope')) {
          user = await Injection.authRepository.login(
            email: loginIdentifier,
            password: password,
          );
        } else {
          rethrow;
        }
      }
      if (mounted) {
        setState(() => _isLoading = false);
        if (_rememberEmail) {
          await Injection.tokenStorage.setRememberEmailEnabled(true);
          await Injection.tokenStorage.saveLastEmail(loginIdentifier);
        } else {
          await Injection.tokenStorage.setRememberEmailEnabled(false);
          await Injection.tokenStorage.clearLastEmail();
        }
        AppSnackbar.showSuccess(context, 'Welcome back, ${user.fullName}!');
        widget.onSignInSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        String msg;
        if (e is ApiException) {
          if (e.isConnectionError) {
            msg = 'Unable to connect to EvenBill server. Please verify backend is running.';
          } else if (e.statusCode == 401) {
            msg = 'Invalid email, phone number, or password. Please try again or create an account.';
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

  Future<void> _handleGoogleSignIn() async {
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
        user = await ref.read(authProvider.notifier).loginWithOAuth(
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
        AppSnackbar.showSuccess(context, 'Welcome, ${user.fullName}!');
        widget.onSignInSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSocialLoading = false);
        final msg = e is ApiException ? e.message : e.toString();
        AppSnackbar.showError(context, 'Google Sign In failed: $msg');
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
                'Sign In to EvenBill',
                style: AppTypography.displayMedium(isDark),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Manage shared expenses with clarity and peace of mind.',
                style: AppTypography.bodyMedium(isDark),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (widget.sessionExpiredMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.warningAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.warningAmber.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 20, color: AppColors.warningAmber),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.sessionExpiredMessage!,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.amber[200] : const Color(0xFFB45309),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              // Google Sign-In Button
              GoogleSignInButton(
                onPressed: _handleGoogleSignIn,
                isLoading: _isSocialLoading,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Divider
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR WITH EMAIL OR PHONE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              AppTextField(
                label: 'Email or Phone Number',
                hintText: 'name@example.com or +1 234 567 8900',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                prefixIcon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: AppSpacing.md),

              AppTextField(
                label: 'Password',
                hintText: 'Enter your password',
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
              const SizedBox(height: AppSpacing.sm),

              // Remember Email & Forgot Password Row
              Row(
                children: [
                  SizedBox(
                    height: 20,
                    width: 20,
                    child: Checkbox(
                      value: _rememberEmail,
                      activeColor: AppColors.forestGreen,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      onChanged: (val) {
                        setState(() {
                          _rememberEmail = val ?? false;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _rememberEmail = !_rememberEmail;
                      });
                    },
                    child: Text(
                      'Remember email on this device',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () async {
                      final email = _emailController.text.trim();
                      if (email.isNotEmpty) {
                        try {
                          await Injection.authRepository.resetPasswordForEmail(email);
                        } catch (_) {}
                      }
                      if (mounted) {
                        AppSnackbar.showInfo(
                          context,
                          'Password recovery instructions sent to your email if account exists.',
                        );
                      }
                    },
                    child: Text(
                      'Forgot Password?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              PrimaryButton(
                label: 'Sign In',
                onPressed: _handleSignIn,
                isLoading: _isLoading,
                icon: Icons.login_rounded,
              ),
              const SizedBox(height: AppSpacing.xl),

              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Don't have an account?",
                      style: AppTypography.bodyMedium(isDark),
                    ),
                    TextButton(
                      onPressed: widget.onNavigateToRegister,
                      child: Text(
                        'Sign Up',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: isDark ? AppColors.mintAccent : AppColors.forestGreen,
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
