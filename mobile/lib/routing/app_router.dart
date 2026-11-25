import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/theme_provider.dart';
import '../core/providers/auth_provider.dart';
import '../core/di/injection.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/auth/sign_in_screen.dart';
import '../screens/auth/registration_screen.dart';
import '../screens/auth/complete_setup_screen.dart';
import '../screens/shell/app_navigation_shell.dart';
import '../screens/expenses/add_edit_expense_screen.dart';
import '../screens/settlements/record_settlement_screen.dart';
import '../screens/analytics/spending_insights_screen.dart';
import '../screens/subscription/pro_paywall_screen.dart';
import 'route_names.dart';

/// Global provider for GoRouter instance with Riverpod bindings and Auth Guarding
final appRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(authProvider.notifier);
  final authListenable = ref.watch(authRouterListenableProvider);

  return createAppRouter(
    getThemeMode: () => ref.watch(themeModeProvider),
    onThemeChanged: (mode) =>
        ref.read(themeModeProvider.notifier).setThemeMode(mode),
    getAuthState: () => ref.read(authProvider),
    refreshListenable: authListenable,
    onSignOut: () async {
      await authNotifier.signOut();
    },
  );
});

/// Factory function to create GoRouter configuration
GoRouter createAppRouter({
  ThemeMode Function()? getThemeMode,
  void Function(ThemeMode)? onThemeChanged,
  String initialLocation = AppRoutes.splash,
  AuthState Function()? getAuthState,
  Listenable? refreshListenable,
  Future<void> Function()? onSignOut,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      if (getAuthState == null) return null;
      final auth = getAuthState();
      final path = state.uri.path;

      final isPublicAuthPath =
          path == AppRoutes.onboarding ||
          path == AppRoutes.signIn ||
          path == AppRoutes.registration;
      final isSplash = path == AppRoutes.splash;

      switch (auth.status) {
        case AuthStatus.initializing:
          return isSplash ? null : AppRoutes.splash;

        case AuthStatus.unauthenticated:
        case AuthStatus.error:
          if (isSplash) return AppRoutes.onboarding;
          if (isPublicAuthPath) return null;
          return AppRoutes.onboarding;

        case AuthStatus.expired:
          return path == AppRoutes.signIn ? null : AppRoutes.signIn;

        case AuthStatus.authenticated:
          if (isPublicAuthPath || isSplash || path == AppRoutes.completeSetup) {
            return AppRoutes.shell;
          }
          return null;
      }
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => SplashScreen(
          onFinish: () {
            final auth = getAuthState != null ? getAuthState() : null;
            if (auth == null || !auth.isAuthenticated) {
              context.go(AppRoutes.onboarding);
            } else {
              context.go(AppRoutes.shell);
            }
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => OnboardingScreen(
          onGetStarted: () => context.go(AppRoutes.registration),
          onSignIn: () => context.go(AppRoutes.signIn),
          onSkipToApp: () {
            final auth = getAuthState != null ? getAuthState() : null;
            if (auth != null && auth.isAuthenticated) {
              context.go(AppRoutes.shell);
            } else {
              context.go(AppRoutes.signIn);
            }
          },
        ),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        builder: (context, state) {
          final auth = getAuthState != null ? getAuthState() : null;
          final expiredMsg = auth?.isExpired == true
              ? auth?.errorMessage
              : null;
          return SignInScreen(
            sessionExpiredMessage: expiredMsg,
            onSignInSuccess: () => context.go(AppRoutes.shell),
            onNavigateToRegister: () => context.go(AppRoutes.registration),
            onBack: () => context.go(AppRoutes.onboarding),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.registration,
        builder: (context, state) => RegistrationScreen(
          onRegisterSuccess: () => context.go(AppRoutes.shell),
          onNavigateToLogin: () => context.go(AppRoutes.signIn),
          onBack: () => context.go(AppRoutes.onboarding),
        ),
      ),
      GoRoute(
        path: AppRoutes.completeSetup,
        builder: (context, state) => CompleteSetupScreen(
          onSetupComplete: () => context.go(AppRoutes.shell),
        ),
      ),
      GoRoute(
        path: AppRoutes.shell,
        builder: (context, state) {
          final themeMode = getThemeMode != null
              ? getThemeMode()
              : ThemeMode.light;
          final currentUserId = getAuthState?.call().user?.id;
          return AppNavigationShell(
            key: ValueKey('shell_${currentUserId ?? 'anon'}'),
            currentThemeMode: themeMode,
            onThemeChanged: onThemeChanged ?? (_) {},
            onSignOut: () async {
              if (onSignOut != null) {
                await onSignOut();
              } else {
                await Injection.authRepository.signOut();
              }
              if (context.mounted) {
                context.go(AppRoutes.signIn);
              }
            },
          );
        },
      ),
      GoRoute(
        path: AppRoutes.addExpense,
        builder: (context, state) => AddEditExpenseScreen(
          onSaved: () => context.pop(),
          onBack: () => context.pop(),
        ),
      ),
      GoRoute(
        path: AppRoutes.recordSettlement,
        builder: (context, state) => RecordSettlementScreen(
          onSettled: () => context.pop(),
          onBack: () => context.pop(),
        ),
      ),
      GoRoute(
        path: AppRoutes.spendingInsights,
        builder: (context, state) =>
            SpendingInsightsScreen(onBack: () => context.pop()),
      ),
      GoRoute(
        path: AppRoutes.proPaywall,
        builder: (context, state) =>
            ProPaywallScreen(onBack: () => context.pop()),
      ),
    ],
  );
}
