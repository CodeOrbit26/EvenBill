import 'package:flutter_test/flutter_test.dart';
import 'package:evenbill/main.dart';
import 'package:evenbill/screens/splash/splash_screen.dart';
import 'package:evenbill/screens/onboarding/onboarding_screen.dart';

void main() {
  testWidgets('EvenBillApp starts with SplashScreen and transitions to Onboarding', (tester) async {
    await tester.pumpWidget(const EvenBillApp());

    // Initially on Splash Screen
    expect(find.byType(SplashScreen), findsOneWidget);

    // Fast-forward past splash duration (2200ms)
    await tester.pump(const Duration(milliseconds: 2300));
    await tester.pumpAndSettle();

    // Now on Onboarding Screen
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });
}
