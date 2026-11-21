import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

class CategoryIcon extends StatelessWidget {
  final String category;
  final double size;

  const CategoryIcon({
    super.key,
    required this.category,
    this.size = 40.0,
  });

  IconData _getIcon(String cat) {
    switch (cat.toUpperCase()) {
      case 'FOOD':
      case 'DINING':
        return Icons.restaurant_rounded;
      case 'GROCERIES':
        return Icons.local_grocery_store_rounded;
      case 'TRAVEL':
      case 'FLIGHT':
        return Icons.flight_takeoff_rounded;
      case 'HOME':
      case 'RENT':
        return Icons.home_rounded;
      case 'UTILITIES':
        return Icons.bolt_rounded;
      case 'ENTERTAINMENT':
        return Icons.movie_rounded;
      case 'GENERAL':
      default:
        return Icons.receipt_long_rounded;
    }
  }

  Color _getColor(String cat) {
    switch (cat.toUpperCase()) {
      case 'FOOD':
      case 'DINING':
        return AppColors.categoryFood;
      case 'GROCERIES':
        return AppColors.categoryGroceries;
      case 'TRAVEL':
      case 'FLIGHT':
        return AppColors.categoryTravel;
      case 'HOME':
      case 'RENT':
        return AppColors.categoryHome;
      case 'UTILITIES':
        return AppColors.categoryUtilities;
      case 'ENTERTAINMENT':
        return AppColors.categoryEntertainment;
      case 'GENERAL':
      default:
        return AppColors.categoryGeneral;
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = _getIcon(category);
    final color = _getColor(category);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}
