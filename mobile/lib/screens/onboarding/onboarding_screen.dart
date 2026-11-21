import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/buttons/primary_button.dart';
import '../../core/widgets/buttons/secondary_button.dart';
import '../../core/widgets/logo/evenbill_logo.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSignIn;
  final VoidCallback onSkipToApp;

  const OnboardingScreen({
    super.key,
    required this.onGetStarted,
    required this.onSignIn,
    required this.onSkipToApp,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<Map<String, dynamic>> _slides = [
    {
      'title': 'Every expense.\nEveryone accounted for.',
      'description': 'Effortlessly split bills, travel expenses, and shared rent with absolute mathematical precision and zero floating-point loss.',
      'icon': Icons.balance_rounded,
      'accent': AppColors.forestGreen,
    },
    {
      'title': 'Bipartite Debt\nSimplification.',
      'description': 'Transform tangled webs of IOUs into minimal, elegant cash-flow settlements. Fewer transfers, less friction, total transparency.',
      'icon': Icons.auto_graph_rounded,
      'accent': AppColors.evergreen,
    },
    {
      'title': 'International\nFinancial Harmony.',
      'description': 'Seamless multi-currency groups with frozen exchange rates, AI-assisted receipt itemization, and instant UPI & cash settle-up.',
      'icon': Icons.public_rounded,
      'accent': Color(0xFF0284C7),
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const EvenBillLogo(size: 28, showWordmark: true),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (idx) => setState(() => _currentPage = idx),
                  itemCount: _slides.length,
                  itemBuilder: (ctx, idx) {
                    final slide = _slides[idx];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: (slide['accent'] as Color).withOpacity(isDark ? 0.25 : 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            slide['icon'] as IconData,
                            size: 46,
                            color: isDark ? AppColors.mintAccent : slide['accent'] as Color,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        Text(
                          slide['title'] as String,
                          textAlign: TextAlign.center,
                          style: AppTypography.displayMedium(isDark),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          slide['description'] as String,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyLarge(isDark).copyWith(
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              // Page Indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _slides.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: _currentPage == i ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _currentPage == i
                          ? (isDark ? AppColors.mintAccent : AppColors.forestGreen)
                          : (isDark ? AppColors.darkCardSubtle : AppColors.lightBorder),
                      borderRadius: AppRadius.roundedPill,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              // Action Buttons
              PrimaryButton(
                label: 'Get Started',
                onPressed: widget.onGetStarted,
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: 'Sign In',
                isSubtle: true,
                onPressed: widget.onSignIn,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
