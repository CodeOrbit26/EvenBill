import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'routing/app_router.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/auth/sign_in_screen.dart';
import 'screens/auth/registration_screen.dart';
import 'screens/shell/app_navigation_shell.dart';
import 'core/di/injection.dart';

void main() {
  runApp(const EvenBillApp(useRouter: true));
}

enum AppFlowState {
  splash,
  onboarding,
  signIn,
  registration,
  authenticatedShell,
}

class EvenBillApp extends StatefulWidget {
  final bool useRouter;
  final String? initialLocation;

  const EvenBillApp({
    super.key,
    this.useRouter = false,
    this.initialLocation,
  });

  @override
  State<EvenBillApp> createState() => _EvenBillAppState();
}

class _EvenBillAppState extends State<EvenBillApp> {
  ThemeMode _themeMode = ThemeMode.light;
  AppFlowState _flowState = AppFlowState.splash;

  void _handleThemeChange(ThemeMode mode) {
    setState(() => _themeMode = mode);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.useRouter) {
      return ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            final activeThemeMode = ref.watch(themeModeProvider);
            final router = widget.initialLocation != null
                ? createAppRouter(
                    getThemeMode: () => ref.watch(themeModeProvider),
                    onThemeChanged: (mode) => ref.read(themeModeProvider.notifier).setThemeMode(mode),
                    initialLocation: widget.initialLocation!,
                  )
                : ref.watch(appRouterProvider);

            return MaterialApp.router(
              title: 'EvenBill',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: activeThemeMode,
              routerConfig: router,
            );
          },
        ),
      );
    }

    return ProviderScope(
      child: MaterialApp(
        title: 'EvenBill',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _themeMode,
        home: _buildCurrentScreen(),
      ),
    );
  }

  Widget _buildCurrentScreen() {
    switch (_flowState) {
      case AppFlowState.splash:
        return SplashScreen(
          onFinish: () async {
            try {
              final token = await Injection.tokenStorage.getAccessToken();
              if (token != null && token.isNotEmpty && mounted) {
                setState(() => _flowState = AppFlowState.authenticatedShell);
                return;
              }
            } catch (_) {}
            if (mounted) {
              setState(() => _flowState = AppFlowState.onboarding);
            }
          },
        );

      case AppFlowState.onboarding:
        return OnboardingScreen(
          onGetStarted: () => setState(() => _flowState = AppFlowState.registration),
          onSignIn: () => setState(() => _flowState = AppFlowState.signIn),
          onSkipToApp: () => setState(() => _flowState = AppFlowState.authenticatedShell),
        );

      case AppFlowState.signIn:
        return SignInScreen(
          onSignInSuccess: () => setState(() => _flowState = AppFlowState.authenticatedShell),
          onNavigateToRegister: () => setState(() => _flowState = AppFlowState.registration),
          onBack: () => setState(() => _flowState = AppFlowState.onboarding),
        );

      case AppFlowState.registration:
        return RegistrationScreen(
          onRegisterSuccess: () => setState(() => _flowState = AppFlowState.authenticatedShell),
          onNavigateToLogin: () => setState(() => _flowState = AppFlowState.signIn),
          onBack: () => setState(() => _flowState = AppFlowState.onboarding),
        );

      case AppFlowState.authenticatedShell:
        return AppNavigationShell(
          currentThemeMode: _themeMode,
          onThemeChanged: _handleThemeChange,
          onSignOut: () => setState(() => _flowState = AppFlowState.signIn),
        );
    }
  }
}
