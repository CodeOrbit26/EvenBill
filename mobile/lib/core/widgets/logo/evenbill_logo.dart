import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

enum LogoVariant {
  standard,
  dark,
  monochrome,
  white,
}

/// Official EvenBill Vector Logo & Wordmark
class EvenBillLogo extends StatelessWidget {
  final double size;
  final LogoVariant? variant;
  final bool showWordmark;
  final bool showTagline;
  final bool isVertical;

  const EvenBillLogo({
    super.key,
    this.size = 36.0,
    this.variant,
    this.showWordmark = false,
    this.showTagline = false,
    this.isVertical = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedVariant = variant ?? (isDark ? LogoVariant.dark : LogoVariant.standard);

    final icon = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _EvenBillLogoPainter(variant: resolvedVariant),
      ),
    );

    if (!showWordmark) {
      return icon;
    }

    final textColor = resolvedVariant == LogoVariant.dark || resolvedVariant == LogoVariant.white
        ? AppColors.darkTextPrimary
        : AppColors.forestGreen;

    final taglineColor = resolvedVariant == LogoVariant.dark || resolvedVariant == LogoVariant.white
        ? AppColors.darkTextSecondary
        : AppColors.evergreen;

    final textColumn = Column(
      crossAxisAlignment: isVertical ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Even',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: size * 0.65,
                fontWeight: FontWeight.w800,
                color: textColor,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Bill',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: size * 0.65,
                fontWeight: FontWeight.w800,
                color: resolvedVariant == LogoVariant.standard ? AppColors.evergreen : AppColors.mintAccent,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        if (showTagline) ...[
          const SizedBox(height: 2),
          Text(
            'Every expense. Everyone accounted for.',
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: size * 0.22,
              fontWeight: FontWeight.w500,
              color: taglineColor,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ],
    );

    if (isVertical) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          SizedBox(height: size * 0.25),
          textColumn,
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        SizedBox(width: size * 0.3),
        textColumn,
      ],
    );
  }
}

class _EvenBillLogoPainter extends CustomPainter {
  final LogoVariant variant;

  _EvenBillLogoPainter({required this.variant});

  @override
  void paint(Canvas canvas, Size size) {
    // Coordinate scale mapping from 120x120 viewBox
    final double scale = size.width / 120.0;
    canvas.save();
    canvas.scale(scale, scale);

    Color topPillColor;
    Color bottomPillColor;
    Color rupeeColor;
    Color counterweightColor;

    switch (variant) {
      case LogoVariant.standard:
        topPillColor = AppColors.forestGreen;
        bottomPillColor = AppColors.evergreen;
        rupeeColor = AppColors.forestGreen;
        counterweightColor = AppColors.mintAccent;
        break;
      case LogoVariant.dark:
        topPillColor = AppColors.mintAccent;
        bottomPillColor = const Color(0xFF4E9B80);
        rupeeColor = AppColors.mintAccent;
        counterweightColor = AppColors.warmBackground;
        break;
      case LogoVariant.monochrome:
        topPillColor = AppColors.primaryText;
        bottomPillColor = AppColors.primaryText;
        rupeeColor = AppColors.primaryText;
        counterweightColor = AppColors.primaryText;
        break;
      case LogoVariant.white:
        topPillColor = Colors.white;
        bottomPillColor = Colors.white;
        rupeeColor = Colors.white;
        counterweightColor = Colors.white;
        break;
    }

    final topPaint = Paint()..color = topPillColor..style = PaintingStyle.fill;
    final bottomPaint = Paint()..color = bottomPillColor..style = PaintingStyle.fill;
    final counterPaint = Paint()..color = counterweightColor..style = PaintingStyle.fill;

    // 1. Top Balance Capsule (width 66, height 20, rx 10 at (22, 28))
    final topRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(22, 28, 66, 20),
      const Radius.circular(10),
    );
    canvas.drawRRect(topRect, topPaint);

    // 2. Bottom Balance Capsule (width 66, height 20, rx 10 at (32, 72))
    final bottomRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(32, 72, 66, 20),
      const Radius.circular(10),
    );
    canvas.drawRRect(bottomRect, bottomPaint);

    // 3. Central Currency Symbol (Rupee sign in the between)
    final textPainter = TextPainter(
      text: TextSpan(
        text: '₹',
        style: TextStyle(
          color: rupeeColor,
          fontSize: 22,
          fontWeight: FontWeight.w900,
          fontFamily: 'Inter',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        60 - (textPainter.width / 2),
        60 - (textPainter.height / 2) + 0.5,
      ),
    );

    // 4. Counterweight Balancing Nodes
    canvas.drawCircle(const Offset(98, 38), 6, counterPaint);
    canvas.drawCircle(const Offset(22, 82), 6, counterPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _EvenBillLogoPainter oldDelegate) {
    return oldDelegate.variant != variant;
  }
}
