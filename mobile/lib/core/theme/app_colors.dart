import 'package:flutter/material.dart';

/// EvenBill Official Brand & Semantic Design Tokens
class AppColors {
  // Primary Brand Identity (Strict Specification)
  static const Color forestGreen = Color(0xFF153C32); // Primary Forest Green
  static const Color evergreen = Color(0xFF286B56);   // Secondary Evergreen
  static const Color mintAccent = Color(0xFF9BE5C3);  // Mint Accent
  static const Color warmBackground = Color(0xFFF7F6EF); // Warm Background
  static const Color primaryText = Color(0xFF19241F); // Primary Text

  // Brand and Semantic Aliases
  static const Color primaryForest = forestGreen;
  static const Color secondaryEvergreen = evergreen;
  static const Color error = negativeRed;
  static const Color warning = warningAmber;
  static const Color success = positiveGreen;


  // Light Mode Surfaces & Neutrals
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardSubtle = Color(0xFFF1F0E7);
  static const Color lightBorder = Color(0xFFE4E1D3);
  static const Color lightBorderSubtle = Color(0xFFEDEADF);
  static const Color lightTextPrimary = primaryText;
  static const Color lightTextSecondary = Color(0xFF526159);
  static const Color lightTextMuted = Color(0xFF7F9188);

  // Dark Mode Surfaces & Neutrals
  static const Color darkBackground = Color(0xFF0C1814); // Deep Forest Night
  static const Color darkSurface = Color(0xFF132620);    // Forest Surface
  static const Color darkCard = Color(0xFF1B352D);       // Forest Card
  static const Color darkCardSubtle = Color(0xFF224339);
  static const Color darkBorder = Color(0xFF2A5246);
  static const Color darkBorderSubtle = Color(0xFF1E3C33);
  static const Color darkTextPrimary = Color(0xFFF7F6EF); // Warm White
  static const Color darkTextSecondary = Color(0xFF9BB2A7);
  static const Color darkTextMuted = Color(0xFF6B8378);

  // Semantic Financial Colors (Accessible Tested Contrast)
  static const Color positiveGreen = Color(0xFF0F9B6C); // You are owed / Settlement received
  static const Color positiveGreenLight = Color(0xFFE6F7F0);
  static const Color positiveGreenDark = Color(0xFF17C388);

  static const Color negativeRed = Color(0xFFDC2626);   // You owe / Expense
  static const Color negativeRedLight = Color(0xFFFEE2E2);
  static const Color negativeRedDark = Color(0xFFF87171);

  static const Color warningAmber = Color(0xFFD97706);  // Unbalanced / Pending
  static const Color warningAmberLight = Color(0xFFFEF3C7);
  static const Color warningAmberDark = Color(0xFFFBBF24);

  static const Color infoBlue = Color(0xFF2563EB);      // Neutral info
  static const Color infoBlueLight = Color(0xFFEFF6FF);
  static const Color infoBlueDark = Color(0xFF60A5FA);

  // Category Colors
  static const Color categoryFood = Color(0xFFF97316);       // Orange
  static const Color categoryTravel = Color(0xFF0284C7);     // Sky Blue
  static const Color categoryHome = Color(0xFF8B5CF6);       // Violet
  static const Color categoryEntertainment = Color(0xFFEC4899); // Pink
  static const Color categoryUtilities = Color(0xFF14B8A6);  // Teal
  static const Color categoryGroceries = Color(0xFF10B981);  // Emerald
  static const Color categoryGeneral = Color(0xFF64748B);    // Slate
}
