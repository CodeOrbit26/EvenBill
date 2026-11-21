import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:evenbill/main.dart';
import 'package:evenbill/core/theme/app_colors.dart';
import 'package:evenbill/core/theme/app_spacing.dart';
import 'package:evenbill/core/theme/app_theme.dart';
import 'package:evenbill/core/providers/theme_provider.dart';
import 'package:evenbill/routing/route_names.dart';
import 'package:evenbill/core/widgets/logo/evenbill_logo.dart';
import 'package:evenbill/core/widgets/buttons/primary_button.dart';
import 'package:evenbill/core/widgets/buttons/secondary_button.dart';
import 'package:evenbill/core/widgets/buttons/action_pill.dart';
import 'package:evenbill/core/widgets/inputs/app_text_field.dart';
import 'package:evenbill/core/widgets/financial/amount_display.dart';
import 'package:evenbill/core/widgets/financial/debt_indicator_badge.dart';
import 'package:evenbill/core/widgets/financial/category_icon.dart';
import 'package:evenbill/core/widgets/avatars/user_avatar.dart';
import 'package:evenbill/core/widgets/avatars/group_avatar.dart';
import 'package:evenbill/core/widgets/feedback/loading_skeleton.dart';
import 'package:evenbill/core/widgets/feedback/empty_state_view.dart';
import 'package:evenbill/core/widgets/feedback/offline_banner.dart';
import 'package:evenbill/core/di/injection.dart';
import 'mocks/mock_repositories.dart';

void main() {
  setUp(() {
    Injection.setMockRepositories(
      auth: MockAuthRepository(),
      group: MockGroupRepository(),
      expense: MockExpenseRepository(),
      settlement: MockSettlementRepository(),
      friend: MockFriendRepository(),
      activity: MockActivityRepository(),
      subscription: MockSubscriptionRepository(),
    );
  });

  tearDown(() {
    Injection.reset();
  });

  Widget wrapInTestApp(Widget child, {ThemeData? theme}) {
    return ProviderScope(
      child: MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  group('Phase 1: Design Tokens & Typography', () {
    test('AppColors verifies brand color palette consistency', () {
      expect(AppColors.forestGreen, const Color(0xFF153C32));
      expect(AppColors.evergreen, const Color(0xFF286B56));
      expect(AppColors.mintAccent, const Color(0xFF9BE5C3));
      expect(AppColors.positiveGreen, const Color(0xFF0F9B6C));
      expect(AppColors.negativeRed, const Color(0xFFDC2626));
      expect(AppColors.warningAmber, const Color(0xFFD97706));
    });

    test('AppSpacing verifies 4px-grid system', () {
      expect(AppSpacing.xxs, 4.0);
      expect(AppSpacing.xs, 8.0);
      expect(AppSpacing.sm, 12.0);
      expect(AppSpacing.md, 16.0);
      expect(AppSpacing.xl, 24.0);
      expect(AppSpacing.xxl, 32.0);
    });

    testWidgets('AppTheme generates consistent light and dark Material 3 themes', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: const Scaffold(body: SizedBox()),
        ),
      );

      final light = AppTheme.lightTheme;
      final dark = AppTheme.darkTheme;
      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.colorScheme.primary, AppColors.forestGreen);
      expect(dark.colorScheme.primary, AppColors.mintAccent);
    });
  });

  group('Phase 1: Reusable Widgets & Logo', () {
    testWidgets('EvenBillLogo renders in light, dark, and monochrome styles', (tester) async {
      await tester.pumpWidget(wrapInTestApp(
        const Column(
          children: [
            EvenBillLogo(size: 40, showWordmark: true, showTagline: true),
            EvenBillLogo(size: 40, variant: LogoVariant.monochrome),
          ],
        ),
      ));

      expect(find.byType(EvenBillLogo), findsNWidgets(2));
      expect(find.text('Even'), findsOneWidget);
      expect(find.text('Bill'), findsOneWidget);
      expect(find.text('Every expense. Everyone accounted for.'), findsOneWidget);
    });

    testWidgets('Buttons render and handle interactions', (tester) async {
      bool primaryClicked = false;
      bool secondaryClicked = false;
      bool pillClicked = false;

      await tester.pumpWidget(wrapInTestApp(
        Column(
          children: [
            PrimaryButton(label: 'Submit', onPressed: () => primaryClicked = true),
            SecondaryButton(label: 'Cancel', onPressed: () => secondaryClicked = true),
            ActionPill(label: 'Active Filter', isSelected: true, onTap: () => pillClicked = true),
          ],
        ),
      ));

      await tester.tap(find.text('Submit'));
      expect(primaryClicked, isTrue);

      await tester.tap(find.text('Cancel'));
      expect(secondaryClicked, isTrue);

      await tester.tap(find.text('Active Filter'));
      expect(pillClicked, isTrue);
    });

    testWidgets('Inputs render labels and receive text values', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(wrapInTestApp(
        AppTextField(
          controller: controller,
          label: 'Full Name',
          hintText: 'Enter your name',
        ),
      ));

      expect(find.text('Full Name'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Elena Rostova');
      expect(controller.text, 'Elena Rostova');
    });

    testWidgets('Financial widgets format amounts and debt badges accurately', (tester) async {
      await tester.pumpWidget(wrapInTestApp(
        const Column(
          children: [
            AmountDisplay(amount: 125.75, currency: 'USD', showSign: true),
            AmountDisplay(amount: -45.00, currency: 'EUR', showSign: true),
            DebtIndicatorBadge(netAmount: 50.0, currency: 'USD'),
            DebtIndicatorBadge(netAmount: -30.0, currency: 'USD'),
            DebtIndicatorBadge(netAmount: 0.0, currency: 'USD'),
          ],
        ),
      ));

      expect(find.text('+\$125.75'), findsOneWidget);
      expect(find.text('-€45.00'), findsOneWidget);
      expect(find.text('you are owed'), findsOneWidget);
      expect(find.text('you owe'), findsOneWidget);
      expect(find.text('settled up'), findsOneWidget);
    });

    testWidgets('Avatars and category icons render correctly', (tester) async {
      await tester.pumpWidget(wrapInTestApp(
        const Row(
          children: [
            UserAvatar(name: 'Marcus Brody'),
            GroupAvatar(groupType: 'TRIP'),
            CategoryIcon(category: 'FOOD'),
            CategoryIcon(category: 'TRANSPORT'),
            CategoryIcon(category: 'LODGING'),
          ],
        ),
      ));

      expect(find.text('MB'), findsOneWidget);
      expect(find.byType(GroupAvatar), findsOneWidget);
      expect(find.byType(CategoryIcon), findsNWidgets(3));
    });

    testWidgets('Feedback views render loading, empty, and offline states', (tester) async {
      await tester.pumpWidget(wrapInTestApp(
        const Column(
          children: [
            LoadingSkeleton(height: 40, width: 200),
            EmptyStateView(
              icon: Icons.receipt_long_rounded,
              title: 'No Expenses Yet',
              description: 'Add an expense to start tracking.',
            ),
            OfflineBanner(pendingSyncCount: 3),
          ],
        ),
      ));

      expect(find.text('No Expenses Yet'), findsOneWidget);
      expect(find.text('Add an expense to start tracking.'), findsOneWidget);
      expect(find.text('Offline Mode — 3 changes queued for sync'), findsOneWidget);
    });
  });

  group('Phase 1: Riverpod Theme State Management', () {
    testWidgets('themeModeProvider toggles theme between light and dark', (tester) async {
      ThemeMode? observedMode;

      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (context, ref, _) {
              observedMode = ref.watch(themeModeProvider);
              return MaterialApp(
                themeMode: observedMode,
                home: Scaffold(
                  body: ElevatedButton(
                    onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
                    child: Text('Toggle: ${observedMode?.name}'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      expect(observedMode, ThemeMode.light);
      expect(find.text('Toggle: light'), findsOneWidget);

      await tester.tap(find.text('Toggle: light'));
      await tester.pump();

      expect(observedMode, ThemeMode.dark);
      expect(find.text('Toggle: dark'), findsOneWidget);
    });
  });

  group('Phase 1: GoRouter Declarative Navigation', () {
    testWidgets('GoRouter navigates to deep link initial location /onboarding', (tester) async {
      await tester.pumpWidget(
        const EvenBillApp(
          useRouter: true,
          initialLocation: AppRoutes.onboarding,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Get Started'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
    });

    testWidgets('GoRouter navigates to deep link /sign-in', (tester) async {
      await tester.pumpWidget(
        const EvenBillApp(
          useRouter: true,
          initialLocation: AppRoutes.signIn,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign In to EvenBill'), findsOneWidget);
      expect(find.text('Manage shared expenses with clarity and peace of mind.'), findsOneWidget);
    });

    testWidgets('GoRouter navigates to deep link /register', (tester) async {
      await tester.pumpWidget(
        const EvenBillApp(
          useRouter: true,
          initialLocation: AppRoutes.registration,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Create Your Account'), findsOneWidget);
      expect(find.text('Join EvenBill for effortless, transparent group finances.'), findsOneWidget);
    });

    testWidgets('GoRouter navigates directly to /shell authenticated dashboard', (tester) async {
      await tester.pumpWidget(
        const EvenBillApp(
          useRouter: true,
          initialLocation: AppRoutes.shell,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recent Expenses'), findsOneWidget);
      expect(find.text('Add Expense'), findsOneWidget);
    });
  });
}
