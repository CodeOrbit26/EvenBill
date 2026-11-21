import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Inter Typography Hierarchy for EvenBill
class AppTypography {
  static TextStyle displayLarge([bool isDark = false]) => GoogleFonts.inter(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
        color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
      );

  static TextStyle displayMedium([bool isDark = false]) => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.6,
        color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
      );

  static TextStyle headline([bool isDark = false]) => GoogleFonts.inter(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
      );

  static TextStyle headlineSmall([bool isDark = false]) => GoogleFonts.inter(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
      );

  static TextStyle titleLarge([bool isDark = false]) => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
      );

  static TextStyle titleMedium([bool isDark = false]) => GoogleFonts.inter(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
      );

  static TextStyle titleSmall([bool isDark = false]) => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
      );

  static TextStyle bodyLarge([bool isDark = false]) => GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
        height: 1.45,
      );

  static TextStyle bodyMedium([bool isDark = false]) => GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
        height: 1.4,
      );

  static TextStyle bodySmall([bool isDark = false]) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
        height: 1.35,
      );

  static TextStyle labelLarge([bool isDark = false]) => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: isDark ? AppColors.darkTextPrimary : AppColors.primaryText,
      );

  static TextStyle labelSmall([bool isDark = false]) => GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
      );


  static TextStyle numericLarge(bool isDark, {Color? color}) => GoogleFonts.inter(
        fontSize: 28,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color ?? (isDark ? AppColors.darkTextPrimary : AppColors.primaryText),
      );

  static TextStyle numericMedium(bool isDark, {Color? color}) => GoogleFonts.inter(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: color ?? (isDark ? AppColors.darkTextPrimary : AppColors.primaryText),
      );
}
