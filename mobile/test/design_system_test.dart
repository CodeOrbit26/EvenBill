import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:evenbill/core/theme/app_theme.dart';
import 'package:evenbill/core/widgets/logo/evenbill_logo.dart';
import 'package:evenbill/core/widgets/buttons/primary_button.dart';
import 'package:evenbill/core/widgets/financial/amount_display.dart';
import 'package:evenbill/core/widgets/financial/debt_indicator_badge.dart';
import 'package:evenbill/core/widgets/financial/category_icon.dart';
import 'package:evenbill/core/widgets/avatars/user_avatar.dart';

void main() {
  Widget createTestWidget(Widget child, {ThemeData? theme}) {
    return MaterialApp(
      theme: theme ?? AppTheme.lightTheme,
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('EvenBillLogo renders vector mark and wordmark', (tester) async {
    await tester.pumpWidget(createTestWidget(
      const EvenBillLogo(
        size: 50,
        showWordmark: true,
        showTagline: true,
      ),
    ));

    expect(find.byType(EvenBillLogo), findsOneWidget);
    expect(find.text('Even'), findsOneWidget);
    expect(find.text('Bill'), findsOneWidget);
    expect(find.text('Every expense. Everyone accounted for.'), findsOneWidget);
  });

  testWidgets('PrimaryButton renders and triggers callback', (tester) async {
    bool tapped = false;
    await tester.pumpWidget(createTestWidget(
      PrimaryButton(
        label: 'Save Expense',
        onPressed: () => tapped = true,
      ),
    ));

    expect(find.text('Save Expense'), findsOneWidget);
    await tester.tap(find.text('Save Expense'));
    expect(tapped, isTrue);
  });

  testWidgets('AmountDisplay formats positive, negative and zero amounts', (tester) async {
    // Positive
    await tester.pumpWidget(createTestWidget(
      const AmountDisplay(amount: 45.50, currency: 'USD', showSign: true),
    ));
    expect(find.text('+\$45.50'), findsOneWidget);

    // Negative
    await tester.pumpWidget(createTestWidget(
      const AmountDisplay(amount: -20.00, currency: 'USD', showSign: true),
    ));
    expect(find.text('-\$20.00'), findsOneWidget);
  });

  testWidgets('DebtIndicatorBadge displays settled up badge when net balance is zero', (tester) async {
    await tester.pumpWidget(createTestWidget(
      const DebtIndicatorBadge(netAmount: 0.0, currency: 'USD'),
    ));
    expect(find.text('settled up'), findsOneWidget);
  });

  testWidgets('UserAvatar computes initials and renders correctly', (tester) async {
    await tester.pumpWidget(createTestWidget(
      const UserAvatar(name: 'Elena Rostova'),
    ));
    expect(find.text('ER'), findsOneWidget);
  });

  testWidgets('CategoryIcon renders appropriate icons without error', (tester) async {
    await tester.pumpWidget(createTestWidget(
      const CategoryIcon(category: 'FOOD'),
    ));
    expect(find.byType(CategoryIcon), findsOneWidget);
  });
}
